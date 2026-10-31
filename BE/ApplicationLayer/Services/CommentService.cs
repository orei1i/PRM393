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

        public async Task<IEnumerable<CommentResponse>> GetPostCommentsAsync(string postId, int page, int pageSize)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy bài viết với id: {postId}");
            }

            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 50);

            // Chỉ lấy các bình luận gốc (ParentId == null), mới nhất trước
            var topComments = (await _commentRepo.FindPagedAsync(
                c => c.PostId == postId && c.ParentId == null && !c.IsDeleted,
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
                !r.IsDeleted
            )).OrderBy(r => r.CreatedAt).ToList();

            // Thu thập toàn bộ UserIds của người bình luận để lấy thông tin tác giả một lần
            var userIds = topComments.Select(c => c.UserId)
                .Concat(allReplies.Select(r => r.UserId))
                .Distinct()
                .ToList();

            var authors = (await _userRepo.FindAsync(u => userIds.Contains(u.Id) && !u.IsDeleted))
                .ToDictionary(
                    u => u.Id,
                    u => new AuthorSummaryDto
                    {
                        Id = u.Id,
                        FullName = u.FullName,
                        IsVerifiedChef = u.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                    });

            var result = new List<CommentResponse>();
            foreach (var comment in topComments)
            {
                var commentAuthor = authors.TryGetValue(comment.UserId, out var a)
                    ? a
                    : new AuthorSummaryDto { Id = comment.UserId, FullName = "Thành viên" };

                var repliesForThisComment = allReplies
                    .Where(r => r.ParentId == comment.Id)
                    .Take(2)
                    .Select(r => new CommentResponse
                    {
                        Id = r.Id,
                        PostId = r.PostId,
                        ParentId = r.ParentId,
                        Author = authors.TryGetValue(r.UserId, out var ra)
                            ? ra
                            : new AuthorSummaryDto { Id = r.UserId, FullName = "Thành viên" },
                        Content = r.Content,
                        CreatedAt = r.CreatedAt,
                        UpdatedAt = r.UpdatedAt,
                        ReplyCount = 0,
                        Replies = new List<CommentResponse>()
                    })
                    .ToList();

                result.Add(new CommentResponse
                {
                    Id = comment.Id,
                    PostId = comment.PostId,
                    ParentId = null,
                    Author = commentAuthor,
                    Content = comment.Content,
                    CreatedAt = comment.CreatedAt,
                    UpdatedAt = comment.UpdatedAt,
                    ReplyCount = Math.Max(comment.ReplyCount, allReplies.Count(r => r.ParentId == comment.Id)),
                    Replies = repliesForThisComment
                });
            }

            return result;
        }

        public async Task<CommentResponse> CreateCommentAsync(string postId, CreateCommentRequest request, string currentUserId)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy bài viết với id: {postId}");
            }

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
                if (parentComment == null || parentComment.IsDeleted)
                {
                    throw new NotFoundException("Không tìm thấy bình luận gốc để phản hồi.");
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
                CreatedAt = DateTime.UtcNow
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

        public async Task<bool> DeleteCommentAsync(string commentId, string currentUserId, string? role)
        {
            var comment = await _commentRepo.FindByIdAsync(commentId);
            if (comment == null || comment.IsDeleted)
            {
                return false;
            }

            var isAdmin = role?.Equals("Admin", StringComparison.OrdinalIgnoreCase) == true;
            if (comment.UserId != currentUserId && !isAdmin)
            {
                throw new ForbiddenException("Bạn không có quyền xóa bình luận này.");
            }

            comment.IsDeleted = true;
            comment.DeletedAt = DateTime.UtcNow;
            await _commentRepo.UpdateAsync(commentId, comment);

            // Giảm số lượng comment của bài viết
            await _postRepo.IncrementFieldAsync(comment.PostId, p => p.CommentCount, -1);

            // Nếu đây là phản hồi con, giảm replyCount của comment cha
            if (!string.IsNullOrEmpty(comment.ParentId))
            {
                await _commentRepo.IncrementFieldAsync(comment.ParentId, c => c.ReplyCount, -1);
            }

            return true;
        }
    }
}
