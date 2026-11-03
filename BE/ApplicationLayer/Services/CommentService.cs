using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    public class CommentService : ICommentService
    {
        private const string Visible = "Visible";
        private const string Hidden = "Hidden";
        private const string CommentNotFound = "Không tìm thấy bình luận.";

        private readonly IGenericRepository<Comment> _commentRepo;
        private readonly IGenericRepository<Post> _postRepo;
        private readonly IGenericRepository<User> _userRepo;

        public CommentService(
            IGenericRepository<Comment> commentRepo,
            IGenericRepository<Post> postRepo,
            IGenericRepository<User> userRepo)
        {
            _commentRepo = commentRepo;
            _postRepo = postRepo;
            _userRepo = userRepo;
        }

        /// <summary>B69: bài chưa đăng thì người ngoài coi như không có bài, kể cả bình luận của nó.</summary>
        private async Task<Post> VisiblePostAsync(string postId, string? currentUserId, string? role)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || !PostAccess.CanSee(post, currentUserId, role))
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }
            return post;
        }

        public async Task<IEnumerable<CommentResponse>> GetPostCommentsAsync(string postId, int page, int pageSize, string? currentUserId = null, string? role = null)
        {
            await VisiblePostAsync(postId, currentUserId, role);

            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 50);

            // Chỉ lấy các bình luận gốc (ParentId == null), mới nhất trước
            var topComments = (await _commentRepo.FindPagedAsync(
                c => c.PostId == postId && c.ParentId == null && !c.IsDeleted && c.Status != Hidden,
                page,
                pageSize,
                sortDesc: c => c.CreatedAt
            )).ToList();

            if (!topComments.Any())
            {
                return Enumerable.Empty<CommentResponse>();
            }

            var topCommentIds = topComments.Select(c => c.Id).ToList();

            // Lấy các replies của các top comments này (để preview 2 replies đầu tiên theo contract)
            var allReplies = (await _commentRepo.FindAsync(r =>
                r.PostId == postId &&
                r.ParentId != null &&
                topCommentIds.Contains(r.ParentId) &&
                !r.IsDeleted &&
                r.Status != Hidden
            )).OrderBy(r => r.CreatedAt).ToList();

            var authors = await AuthorsOfAsync(topComments.Select(c => c.UserId).Concat(allReplies.Select(r => r.UserId)));

            var result = new List<CommentResponse>();
            foreach (var comment in topComments)
            {
                var repliesForThisComment = allReplies
                    .Where(r => r.ParentId == comment.Id)
                    .Take(2)
                    .Select(r => MapToResponse(r, authors, 0))
                    .ToList();

                var dto = MapToResponse(comment, authors, Math.Max(comment.ReplyCount, allReplies.Count(r => r.ParentId == comment.Id)));
                dto.ParentId = null;
                dto.Replies = repliesForThisComment;
                result.Add(dto);
            }

            return result;
        }

        public async Task<CommentResponse> CreateCommentAsync(string postId, CreateCommentRequest request, string currentUserId, string? role = null)
        {
            await VisiblePostAsync(postId, currentUserId, role);

            string? validParentId = null;
            var rawParentId = request.ParentId?.Trim();
            if (!string.IsNullOrWhiteSpace(rawParentId)
                && !rawParentId.Equals("string", StringComparison.OrdinalIgnoreCase)
                && MongoDB.Bson.ObjectId.TryParse(rawParentId, out _))
            {
                validParentId = rawParentId;
            }

            if (!string.IsNullOrEmpty(validParentId))
            {
                var parentComment = await _commentRepo.FindByIdAsync(validParentId);

                // B40: phản hồi phải nằm cùng bài với bình luận gốc.
                if (parentComment == null || parentComment.IsDeleted || parentComment.Status == Hidden || parentComment.PostId != postId)
                {
                    throw new NotFoundException("Không tìm thấy bình luận gốc để phản hồi.");
                }

                // B16/B39: Flatten reply về root comment (1 cấp duy nhất)
                if (!string.IsNullOrEmpty(parentComment.ParentId))
                {
                    validParentId = parentComment.ParentId;
                }

                // Tăng reply count cho bình luận gốc
                await _commentRepo.IncrementFieldAsync(validParentId, c => c.ReplyCount, 1);
            }

            var comment = new Comment
            {
                PostId = postId,
                UserId = currentUserId,
                ParentId = validParentId,
                Content = request.Content.Trim(),
                ReplyCount = 0,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = null
            };

            await _commentRepo.CreateAsync(comment);

            // Tăng comment count của bài viết
            await _postRepo.IncrementFieldAsync(postId, p => p.CommentCount, 1);

            var user = await _userRepo.FindByIdAsync(currentUserId);
            var author = new AuthorSummaryDto
            {
                Id = currentUserId,
                FullName = user?.FullName ?? "Thành viên",
                IsVerifiedChef = user?.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
            };

            return new CommentResponse
            {
                Id = comment.Id,
                PostId = comment.PostId,
                ParentId = comment.ParentId,
                Author = author,
                Content = comment.Content,
                CreatedAt = comment.CreatedAt,
                ReplyCount = 0,
                Replies = new List<CommentResponse>()
            };
        }

        /// <summary>Chỉ tác giả được sửa, kể cả admin cũng không viết lời vào miệng người khác.</summary>
        public async Task<CommentResponse> UpdateCommentAsync(string postId, string commentId, UpdateCommentRequest request, string currentUserId, string? role = null)
        {
            await VisiblePostAsync(postId, currentUserId, role);

            var comment = await _commentRepo.FindByIdAsync(commentId);
            if (comment == null || comment.IsDeleted || comment.PostId != postId || comment.Status == Hidden)
            {
                throw new NotFoundException(CommentNotFound);
            }

            if (comment.UserId != currentUserId)
            {
                throw new ForbiddenException("Bạn không có quyền sửa bình luận này.");
            }

            comment.Content = request.Content.Trim();
            comment.UpdatedAt = DateTime.UtcNow;
            await _commentRepo.UpdateAsync(commentId, comment);

            var authors = await AuthorsOfAsync(new[] { comment.UserId });
            return MapToResponse(comment, authors, comment.ReplyCount);
        }

        public async Task<bool> DeleteCommentAsync(string commentId, string currentUserId, string? role)
        {
            var comment = await _commentRepo.FindByIdAsync(commentId);
            if (comment == null || comment.IsDeleted)
            {
                return false;
            }

            var isAdmin = PostAccess.IsAdmin(role);
            if (comment.UserId != currentUserId && !isAdmin)
            {
                throw new ForbiddenException("Bạn không có quyền xóa bình luận này.");
            }

            await SoftDeleteBranchAsync(comment);
            return true;
        }

        public async Task<IEnumerable<CommentResponse>> GetCommentRepliesAsync(string commentId, string? postId = null, string? currentUserId = null, string? role = null)
        {
            var parent = await _commentRepo.FindByIdAsync(commentId);
            if (parent == null || parent.IsDeleted || parent.Status == Hidden)
            {
                throw new NotFoundException(CommentNotFound);
            }

            // B40: Route replies kiểm tra comment có thuộc về postId hay không
            if (!string.IsNullOrEmpty(postId) && parent.PostId != postId)
            {
                throw new NotFoundException("Bình luận không thuộc bài viết này.");
            }

            // B69: phản hồi của bài chưa đăng cũng không lộ ra cho người ngoài.
            await VisiblePostAsync(parent.PostId, currentUserId, role);

            var replies = (await _commentRepo.FindAsync(r =>
                r.ParentId == commentId &&
                !r.IsDeleted &&
                r.Status != Hidden
            )).OrderBy(r => r.CreatedAt).ToList();

            if (!replies.Any())
            {
                return Enumerable.Empty<CommentResponse>();
            }

            var authors = await AuthorsOfAsync(replies.Select(r => r.UserId));
            return replies.Select(r => MapToResponse(r, authors, 0)).ToList();
        }

        public async Task<IEnumerable<MyCommentResponse>> GetMyCommentsAsync(string currentUserId)
        {
            var comments = (await _commentRepo.FindPagedAsync(
                c => c.UserId == currentUserId && !c.IsDeleted && c.Status != Hidden,
                1,
                200,
                sortDesc: c => c.CreatedAt)).ToList();
            if (!comments.Any()) return Enumerable.Empty<MyCommentResponse>();

            var posts = await PostsOfAsync(comments);

            // Bài đã xoá thì bỏ cả dòng. Bài bị ẩn thì giữ lời của mình nhưng không để lộ tiêu đề.
            return comments
                .Where(c => posts.ContainsKey(c.PostId))
                .Select(c => new MyCommentResponse
                {
                    Id = c.Id,
                    PostId = c.PostId,
                    PostTitle = PostAccess.CanSee(posts[c.PostId], currentUserId, null) ? posts[c.PostId].Title : "Bài viết không còn hiển thị",
                    ParentId = c.ParentId,
                    Content = c.Content,
                    CreatedAt = c.CreatedAt,
                    UpdatedAt = c.UpdatedAt
                })
                .ToList();
        }

        public async Task<IEnumerable<AdminCommentResponse>> GetAdminCommentsAsync(string? view, string? search, string? authorId, string? postId)
        {
            var mode = string.IsNullOrWhiteSpace(view) ? "all" : view.Trim().ToLowerInvariant();
            if (mode != "all" && mode != "reported" && mode != "hidden")
            {
                throw new BadRequestException("view chỉ nhận all, reported hoặc hidden.", "invalid_view");
            }
            authorId = RequireObjectIdOrNull(authorId, "authorId");
            postId = RequireObjectIdOrNull(postId, "postId");

            var term = string.IsNullOrWhiteSpace(search) ? null : search.Trim().ToLowerInvariant();
            var matchingAuthors = new List<string>();
            if (term != null)
            {
                matchingAuthors = (await _userRepo.FindAsync(u => u.FullName.ToLower().Contains(term))).Select(u => u.Id).ToList();
            }

            var comments = (await _commentRepo.FindPagedAsync(
                c => !c.IsDeleted &&
                     (mode != "hidden" || c.Status == Hidden) &&
                     (mode != "reported" || c.ReportCount > 0) &&
                     (authorId == null || c.UserId == authorId) &&
                     (postId == null || c.PostId == postId) &&
                     (term == null || c.Content.ToLower().Contains(term) || matchingAuthors.Contains(c.UserId)),
                1,
                200,
                sortDesc: c => c.CreatedAt)).ToList();

            return await MapAdminAsync(comments);
        }

        public async Task<bool> AdminDeleteCommentAsync(string commentId, string? reason)
        {
            var comment = await _commentRepo.FindByIdAsync(commentId);
            if (comment == null || comment.IsDeleted) return false;

            comment.DeleteReason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim();
            await SoftDeleteBranchAsync(comment);
            return true;
        }

        public async Task<AdminCommentResponse> AdminActOnCommentAsync(string commentId, string action)
        {
            var comment = await _commentRepo.FindByIdAsync(commentId);
            if (comment == null || comment.IsDeleted)
            {
                throw new NotFoundException(CommentNotFound);
            }

            var target = action switch
            {
                "hide" => Hidden,
                "unhide" => Visible,
                _ => throw new BadRequestException("action chỉ nhận hide hoặc unhide.", "invalid_action")
            };

            if (comment.Status != target)
            {
                comment.Status = target;
                await _commentRepo.UpdateFieldAsync(commentId, c => c.Status, target);

                // Bình luận bị ẩn không còn tính vào số đếm mà người đọc thấy.
                var delta = target == Hidden ? -1 : 1;
                var branch = 1;
                if (string.IsNullOrEmpty(comment.ParentId))
                {
                    branch += (await _commentRepo.FindAsync(c => c.ParentId == commentId && !c.IsDeleted && c.Status != Hidden)).Count();
                }
                else
                {
                    await _commentRepo.IncrementFieldAsync(comment.ParentId, c => c.ReplyCount, delta);
                }
                await _postRepo.IncrementFieldAsync(comment.PostId, p => p.CommentCount, delta * branch);
            }

            return (await MapAdminAsync(new List<Comment> { comment })).Single();
        }

        private async Task SoftDeleteBranchAsync(Comment comment)
        {
            comment.IsDeleted = true;
            comment.DeletedAt = DateTime.UtcNow;
            await _commentRepo.UpdateAsync(comment.Id, comment);

            // B16 Fix: Xoá theo cả nhánh (cascade soft-delete child replies)
            var commentId = comment.Id;
            var childReplies = (await _commentRepo.FindAsync(c => c.ParentId == commentId && !c.IsDeleted)).ToList();
            foreach (var child in childReplies)
            {
                child.IsDeleted = true;
                child.DeletedAt = DateTime.UtcNow;
                await _commentRepo.UpdateAsync(child.Id, child);
            }

            // Phần đã ẩn thì lúc ẩn đã trừ rồi, không trừ lần nữa.
            var removed = (comment.Status == Hidden ? 0 : 1 + childReplies.Count(c => c.Status != Hidden));
            if (removed > 0)
            {
                await _postRepo.IncrementFieldAsync(comment.PostId, p => p.CommentCount, -removed);
            }

            // Nếu đây là phản hồi con, giảm replyCount của comment cha
            if (!string.IsNullOrEmpty(comment.ParentId) && comment.Status != Hidden)
            {
                await _commentRepo.IncrementFieldAsync(comment.ParentId, c => c.ReplyCount, -1);
            }
        }

        private async Task<List<AdminCommentResponse>> MapAdminAsync(List<Comment> comments)
        {
            if (!comments.Any()) return new List<AdminCommentResponse>();

            var posts = await PostsOfAsync(comments);
            var parentIds = comments.Where(c => c.ParentId != null).Select(c => c.ParentId!).Distinct().ToList();
            var parents = parentIds.Any()
                ? (await _commentRepo.FindAsync(c => parentIds.Contains(c.Id))).ToDictionary(c => c.Id)
                : new Dictionary<string, Comment>();
            var authors = await AuthorsOfAsync(comments.Select(c => c.UserId).Concat(parents.Values.Select(p => p.UserId)));

            return comments
                .Where(c => posts.ContainsKey(c.PostId))
                .Select(c =>
                {
                    var author = AuthorOf(c.UserId, authors);
                    Comment? parent = null;
                    if (c.ParentId != null) parents.TryGetValue(c.ParentId, out parent);
                    return new AdminCommentResponse
                    {
                        Id = c.Id,
                        PostId = c.PostId,
                        PostTitle = posts[c.PostId].Title,
                        ParentId = c.ParentId,
                        ReplyTo = parent == null ? null : new AdminCommentReplyToDto { Id = parent.Id, AuthorName = AuthorOf(parent.UserId, authors).FullName },
                        ReplyCount = Math.Max(0, c.ReplyCount),
                        Author = new AdminCommentAuthorDto { Id = author.Id, FullName = author.FullName },
                        Content = c.Content,
                        Status = string.IsNullOrEmpty(c.Status) ? Visible : c.Status,
                        ReportCount = c.ReportCount,
                        CreatedAt = c.CreatedAt,
                        UpdatedAt = c.UpdatedAt
                    };
                })
                .ToList();
        }

        private async Task<Dictionary<string, Post>> PostsOfAsync(IEnumerable<Comment> comments)
        {
            var postIds = comments.Select(c => c.PostId).Distinct().ToList();
            return (await _postRepo.FindAsync(p => postIds.Contains(p.Id) && !p.IsDeleted)).ToDictionary(p => p.Id);
        }

        private async Task<Dictionary<string, AuthorSummaryDto>> AuthorsOfAsync(IEnumerable<string> ids)
        {
            var userIds = ids.Distinct().ToList();
            return (await _userRepo.FindAsync(u => userIds.Contains(u.Id) && !u.IsDeleted))
                .ToDictionary(
                    u => u.Id,
                    u => new AuthorSummaryDto
                    {
                        Id = u.Id,
                        FullName = u.FullName,
                        IsVerifiedChef = u.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                    });
        }

        private static AuthorSummaryDto AuthorOf(string userId, Dictionary<string, AuthorSummaryDto> authors) =>
            authors.TryGetValue(userId, out var a) ? a : new AuthorSummaryDto { Id = userId, FullName = "Thành viên" };

        private static CommentResponse MapToResponse(Comment c, Dictionary<string, AuthorSummaryDto> authors, int replyCount) => new()
        {
            Id = c.Id,
            PostId = c.PostId,
            ParentId = c.ParentId,
            Author = AuthorOf(c.UserId, authors),
            Content = c.Content,
            CreatedAt = c.CreatedAt,
            UpdatedAt = c.UpdatedAt,
            ReplyCount = replyCount,
            Replies = new List<CommentResponse>()
        };

        private static string? RequireObjectIdOrNull(string? value, string name)
        {
            if (string.IsNullOrWhiteSpace(value)) return null;
            if (!MongoDB.Bson.ObjectId.TryParse(value.Trim(), out _))
            {
                throw new BadRequestException($"{name} không hợp lệ.", "invalid_id");
            }
            return value.Trim();
        }
    }
}
