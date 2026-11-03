using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    /// <summary>Ai được thấy bài chưa đăng: chỉ tác giả và admin. Người khác coi như bài không tồn tại.</summary>
    internal static class PostAccess
    {
        public const string Published = "Published";
        public const string Pending = "Pending";
        public const string Rejected = "Rejected";
        public const string Hidden = "Hidden";

        public const string NotFoundMessage = "Không tìm thấy bài viết.";

        public static bool IsAdmin(string? role) => string.Equals(role, "Admin", StringComparison.OrdinalIgnoreCase);

        public static bool CanSee(Post post, string? userId, string? role) =>
            !post.IsDeleted &&
            (post.Status == Published || (!string.IsNullOrEmpty(userId) && post.UserId == userId) || IsAdmin(role));

        public static string? CanonicalStatus(string? status)
        {
            if (string.IsNullOrWhiteSpace(status)) return null;
            return status.Trim().ToLowerInvariant() switch
            {
                "published" => Published,
                "pending" => Pending,
                "rejected" => Rejected,
                "hidden" => Hidden,
                _ => throw new BadRequestException($"Trạng thái bài viết không hợp lệ: '{status}'. Các trạng thái hợp lệ: Published, Pending, Rejected, Hidden.", "invalid_status")
            };
        }
    }

    public class PostService : IPostService
    {
        private readonly IGenericRepository<Post> _postRepo;
        private readonly IGenericRepository<User> _userRepo;
        private readonly IGenericRepository<PostLike> _likeRepo;
        private readonly IGenericRepository<PostReport> _reportRepo;
        private readonly IMediaService _mediaService;
        private readonly ILogger<PostService> _logger;
        private readonly IGenericRepository<PostSave>? _saveRepo;
        private readonly IConfiguration? _config;
        private readonly IGenericRepository<Restaurant>? _restaurantRepo;

        public PostService(
            IGenericRepository<Post> postRepo,
            IGenericRepository<User> userRepo,
            IGenericRepository<PostLike> likeRepo,
            IGenericRepository<PostReport> reportRepo,
            IMediaService mediaService,
            ILogger<PostService> logger,
            IGenericRepository<PostSave>? saveRepo = null,
            IConfiguration? config = null,
            IGenericRepository<Restaurant>? restaurantRepo = null)
        {
            _restaurantRepo = restaurantRepo;
            _postRepo = postRepo;
            _userRepo = userRepo;
            _likeRepo = likeRepo;
            _reportRepo = reportRepo;
            _mediaService = mediaService;
            _logger = logger;
            _saveRepo = saveRepo;
            _config = config;
        }

        /// <summary>Bài mới và bài sửa có phải chờ duyệt không. appsettings.json bật sẵn, xem Posts:RequireApproval.</summary>
        private bool RequiresApproval =>
            string.Equals(_config?["Posts:RequireApproval"], "true", StringComparison.OrdinalIgnoreCase);

        public async Task<FeedPageResponse> GetFeedAsync(
            int page,
            int pageSize,
            string? type,
            string? mediaType,
            string? currentUserId,
            string? cursor = null,
            int? limit = null)
        {
            if (limit.HasValue && limit.Value > 0)
            {
                pageSize = Math.Clamp(limit.Value, 1, 50);
            }
            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 50);

            // Filter chỉ bài Published và chưa xóa
            Expression<Func<Post, bool>> filter = x =>
                !x.IsDeleted &&
                x.Status == "Published" &&
                (string.IsNullOrEmpty(type) || x.Type == type) &&
                (string.IsNullOrEmpty(mediaType) || x.MediaType == mediaType);

            var totalItems = await _postRepo.CountAsync(filter);
            List<Post> posts;
            string? nextCursor = null;

            if (!string.IsNullOrWhiteSpace(cursor))
            {
                // B15: Phân trang con trỏ theo _id giảm dần với limit + 1
                (posts, nextCursor) = await CursorPageAsync(filter, cursor, pageSize);
            }
            else
            {
                posts = (await _postRepo.FindPagedAsync(filter, page, pageSize, sortDesc: x => x.CreatedAt)).ToList();
                nextCursor = (posts.Count == pageSize && (page * pageSize) < totalItems) ? posts.Last().Id : null;
            }

            if (!posts.Any())
            {
                return new FeedPageResponse
                {
                    Items = new List<PostResponse>(),
                    Page = page,
                    PageSize = pageSize,
                    TotalItems = totalItems,
                    TotalPages = (int)Math.Ceiling(totalItems / (double)pageSize)
                };
            }

            return new FeedPageResponse
            {
                Items = await MapManyAsync(posts, currentUserId),
                Page = page,
                PageSize = pageSize,
                TotalItems = totalItems,
                TotalPages = (int)Math.Ceiling(totalItems / (double)pageSize),
                NextCursor = nextCursor
            };
        }

        public async Task<PostResponse> GetPostByIdAsync(string id, string? currentUserId, string? role = null)
        {
            var post = await _postRepo.FindByIdAsync(id);

            // B53, B71: Bài chưa đăng chỉ tác giả hoặc Admin mới xem được; người khác nhận đúng lời như bài không tồn tại.
            if (post == null || !PostAccess.CanSee(post, currentUserId, role))
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            var author = await AuthorOfAsync(post.UserId);

            var liked = false;
            var saved = false;
            if (!string.IsNullOrEmpty(currentUserId))
            {
                var like = await _likeRepo.FirstOrDefaultAsync(l => l.PostId == id && l.UserId == currentUserId && !l.IsDeleted);
                liked = like != null;
                if (_saveRepo != null)
                {
                    saved = await _saveRepo.FirstOrDefaultAsync(s => s.PostId == id && s.UserId == currentUserId && !s.IsDeleted) != null;
                }
            }

            return await WithRestaurantAsync(post, MapToResponse(post, author, liked, saved));
        }

        public async Task<PostResponse> CreatePostAsync(CreatePostRequest request, string currentUserId)
        {
            var content = await ValidateContentAsync(request, currentUserId, null);

            var post = new Post
            {
                UserId = currentUserId,
                Type = content.Type,
                Title = content.Title,
                Body = content.Body,
                Tags = content.Tags,
                MediaType = content.MediaType,
                MediaUrl = content.MediaUrl,
                RestaurantId = content.RestaurantId,
                Status = RequiresApproval ? PostAccess.Pending : PostAccess.Published,
                LikeCount = 0,
                CommentCount = 0,
                ReportCount = 0,
                CreatedAt = DateTime.UtcNow
            };

            await _postRepo.CreateAsync(post);

            var user = await _userRepo.FindByIdAsync(currentUserId);
            var author = new AuthorSummaryDto
            {
                Id = currentUserId,
                FullName = user?.FullName ?? "Thành viên",
                IsVerifiedChef = user?.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
            };

            return await WithRestaurantAsync(post, MapToResponse(post, author, false));
        }

        /// <summary>
        /// Sửa bài của chính mình. Bài bị admin ẩn không sửa được (sửa không được gỡ quyết định của admin).
        /// Bật Posts:RequireApproval thì mọi bài sửa về Pending. Tắt thì bài đã đăng giữ nguyên, nhưng bài bị từ chối
        /// vẫn phải qua duyệt lại, để không ai tự gỡ từ chối bằng cách sửa bài.
        /// </summary>
        public async Task<PostResponse> UpdatePostAsync(string id, CreatePostRequest request, string currentUserId)
        {
            var post = await _postRepo.FindByIdAsync(id);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            if (post.UserId != currentUserId)
            {
                // Bài chưa đăng của người khác thì không để lộ là có tồn tại.
                if (post.Status != PostAccess.Published) throw new NotFoundException(PostAccess.NotFoundMessage);
                throw new ForbiddenException("Bạn không có quyền sửa bài viết này.");
            }

            if (post.Status == PostAccess.Hidden)
            {
                throw new ConflictException("Bài viết đã bị quản trị viên ẩn nên không sửa được.", "post_hidden");
            }

            var content = await ValidateContentAsync(request, currentUserId, post.MediaUrl);

            post.Type = content.Type;
            post.Title = content.Title;
            post.Body = content.Body;
            post.Tags = content.Tags;
            post.MediaType = content.MediaType;
            post.MediaUrl = content.MediaUrl;
            post.RestaurantId = content.RestaurantId;
            if (RequiresApproval || post.Status == PostAccess.Rejected)
            {
                post.Status = PostAccess.Pending;
            }
            post.RejectionReason = null;
            post.UpdatedAt = DateTime.UtcNow;

            await _postRepo.UpdateAsync(id, post);

            var liked = await _likeRepo.FirstOrDefaultAsync(l => l.PostId == id && l.UserId == currentUserId && !l.IsDeleted) != null;
            var saved = _saveRepo != null
                && await _saveRepo.FirstOrDefaultAsync(s => s.PostId == id && s.UserId == currentUserId && !s.IsDeleted) != null;
            return await WithRestaurantAsync(post, MapToResponse(post, await AuthorOfAsync(post.UserId), liked, saved));
        }

        private sealed record PostContent(string Type, string Title, string Body, List<string> Tags, string MediaType, string? MediaUrl, string? RestaurantId);

        private async Task<PostContent> ValidateContentAsync(CreatePostRequest request, string currentUserId, string? currentMediaUrl)
        {
            if (request.Tags != null && request.Tags.Count > 10)
            {
                throw new BadRequestException("Số lượng thẻ tags tối đa là 10.");
            }
            if (request.Tags != null && request.Tags.Any(t => t != null && t.Length > 50))
            {
                throw new BadRequestException("Mỗi thẻ tối đa 50 ký tự.");
            }

            // Kiểm tra URL media có do chính user này upload lên không
            var rawMediaUrl = request.MediaUrl?.Trim();
            var mediaUrl = string.IsNullOrWhiteSpace(rawMediaUrl) || rawMediaUrl.Equals("string", StringComparison.OrdinalIgnoreCase)
                ? null
                : rawMediaUrl;

            if (!string.IsNullOrWhiteSpace(mediaUrl) && mediaUrl != currentMediaUrl)
            {
                var isOwner = await _mediaService.ValidateOwnerAsync(mediaUrl, currentUserId);
                if (!isOwner)
                {
                    throw new BadRequestException("Tài nguyên media không tồn tại hoặc không thuộc quyền sở hữu của bạn.");
                }
            }

            // Lọc an toàn RestaurantId: Chỉ nhận mã MongoDB ObjectId 24 ký tự hex hợp lệ
            string? validRestaurantId = null;
            var rawRestaurantId = request.RestaurantId?.Trim();
            if (!string.IsNullOrWhiteSpace(rawRestaurantId)
                && !rawRestaurantId.Equals("string", StringComparison.OrdinalIgnoreCase)
                && MongoDB.Bson.ObjectId.TryParse(rawRestaurantId, out _))
            {
                validRestaurantId = rawRestaurantId;
            }

            return new PostContent(
                string.IsNullOrWhiteSpace(request.Type) ? "discussion" : request.Type.ToLowerInvariant(),
                request.Title.Trim(),
                request.Body.Trim(),
                request.Tags ?? new List<string>(),
                !string.IsNullOrWhiteSpace(request.MediaType)
                    ? request.MediaType
                    : (!string.IsNullOrWhiteSpace(mediaUrl) ? "Image" : "Text"),
                mediaUrl,
                validRestaurantId);
        }

        public async Task<bool> DeletePostAsync(string id, string currentUserId, string? role)
        {
            var post = await _postRepo.FindByIdAsync(id);
            if (post == null || post.IsDeleted)
            {
                return false;
            }

            var isAdmin = PostAccess.IsAdmin(role);
            if (post.UserId != currentUserId && !isAdmin)
            {
                if (post.Status != PostAccess.Published) return false;
                throw new ForbiddenException("Bạn không có quyền xóa bài viết này.");
            }

            post.IsDeleted = true;
            post.DeletedAt = DateTime.UtcNow;
            await _postRepo.UpdateAsync(id, post);
            return true;
        }

        public async Task<LikeResponse> ToggleLikeAsync(string postId, string currentUserId, string? role = null)
        {
            var post = await _postRepo.FindByIdAsync(postId);

            // B69: bài chưa đăng không nhận tương tác từ người ngoài.
            if (post == null || !PostAccess.CanSee(post, currentUserId, role))
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            var existingLike = await _likeRepo.FirstOrDefaultAsync(l =>
                l.PostId == postId &&
                l.UserId == currentUserId);

            if (existingLike != null)
            {
                if (!existingLike.IsDeleted)
                {
                    existingLike.IsDeleted = true;
                    existingLike.DeletedAt = DateTime.UtcNow;
                    await _likeRepo.UpdateAsync(existingLike.Id, existingLike);

                    await _postRepo.IncrementFieldAsync(postId, p => p.LikeCount, -1);
                    return new LikeResponse { Liked = false, LikeCount = Math.Max(0, post.LikeCount - 1) };
                }

                existingLike.IsDeleted = false;
                existingLike.DeletedAt = null;
                existingLike.UpdatedAt = DateTime.UtcNow;
                await _likeRepo.UpdateAsync(existingLike.Id, existingLike);

                await _postRepo.IncrementFieldAsync(postId, p => p.LikeCount, 1);
                return new LikeResponse { Liked = true, LikeCount = post.LikeCount + 1 };
            }

            await _likeRepo.CreateAsync(new PostLike
            {
                PostId = postId,
                UserId = currentUserId,
                CreatedAt = DateTime.UtcNow
            });

            await _postRepo.IncrementFieldAsync(postId, p => p.LikeCount, 1);
            return new LikeResponse { Liked = true, LikeCount = post.LikeCount + 1 };
        }

        /// <summary>Công tắc. Bài đã lưu mà sau đó bị ẩn vẫn bỏ lưu được; bài chưa lưu thì như không tồn tại.</summary>
        public async Task<SaveResponse> ToggleSaveAsync(string postId, string currentUserId, string? role = null)
        {
            if (_saveRepo == null) throw new InvalidOperationException("PostSave repository chưa được đăng ký.");

            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            var existing = await _saveRepo.FirstOrDefaultAsync(s => s.PostId == postId && s.UserId == currentUserId);

            if (existing != null && !existing.IsDeleted)
            {
                existing.IsDeleted = true;
                existing.DeletedAt = DateTime.UtcNow;
                await _saveRepo.UpdateAsync(existing.Id, existing);
                return new SaveResponse { Saved = false };
            }

            if (!PostAccess.CanSee(post, currentUserId, role))
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            if (existing != null)
            {
                existing.IsDeleted = false;
                existing.DeletedAt = null;
                existing.CreatedAt = DateTime.UtcNow; // lưu lại thì lên đầu danh sách
                existing.UpdatedAt = DateTime.UtcNow;
                await _saveRepo.UpdateAsync(existing.Id, existing);
                return new SaveResponse { Saved = true };
            }

            try
            {
                await _saveRepo.CreateAsync(new PostSave { PostId = postId, UserId = currentUserId, CreatedAt = DateTime.UtcNow });
            }
            catch (Exception ex) when (IsDuplicateKey(ex))
            {
                // Hai lần bấm cùng lúc: dòng đã có, kết quả vẫn là đã lưu.
            }
            return new SaveResponse { Saved = true };
        }

        public async Task<FeedPageResponse> GetMyPostsAsync(string currentUserId, string? status, string? cursor, int? limit)
        {
            var canonical = PostAccess.CanonicalStatus(status);
            var pageSize = Math.Clamp(limit ?? 20, 1, 50);

            Expression<Func<Post, bool>> filter = x =>
                x.UserId == currentUserId &&
                !x.IsDeleted &&
                (canonical == null || x.Status == canonical);

            var totalItems = await _postRepo.CountAsync(filter);
            var (posts, nextCursor) = await CursorPageAsync(filter, cursor, pageSize);

            return new FeedPageResponse
            {
                Items = await MapManyAsync(posts, currentUserId),
                Page = 1,
                PageSize = pageSize,
                TotalItems = totalItems,
                TotalPages = (int)Math.Ceiling(totalItems / (double)pageSize),
                NextCursor = nextCursor
            };
        }

        public async Task<IEnumerable<PostResponse>> GetSavedPostsAsync(string currentUserId)
        {
            if (_saveRepo == null) return Enumerable.Empty<PostResponse>();

            var saves = (await _saveRepo.FindPagedAsync(
                s => s.UserId == currentUserId && !s.IsDeleted,
                1,
                200,
                sortDesc: s => s.CreatedAt)).ToList();
            if (!saves.Any()) return Enumerable.Empty<PostResponse>();

            var ids = saves.Select(s => s.PostId).ToList();
            var posts = (await _postRepo.FindAsync(p => ids.Contains(p.Id) && !p.IsDeleted))
                .Where(p => PostAccess.CanSee(p, currentUserId, null))
                .ToDictionary(p => p.Id);

            // Giữ thứ tự mới lưu trước; bài đã xoá hoặc đã bị ẩn thì bỏ qua nhưng không quên, ẩn xong bỏ ẩn sẽ hiện lại.
            var ordered = ids.Where(posts.ContainsKey).Select(id => posts[id]).ToList();
            return await MapManyAsync(ordered, currentUserId);
        }

        public async Task<bool> ReportPostAsync(string postId, string currentUserId, ReportPostRequest request, string? role = null)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || !PostAccess.CanSee(post, currentUserId, role))
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            var existingReport = await _reportRepo.FirstOrDefaultAsync(r =>
                r.PostId == postId &&
                r.UserId == currentUserId);

            if (existingReport != null && !existingReport.IsDeleted)
            {
                throw new ConflictException("Bạn đã báo cáo bài viết này rồi.");
            }

            if (existingReport != null)
            {
                // B51: báo cáo cũ đã được xử lý khi duyệt lại, người này được báo cáo lại.
                existingReport.IsDeleted = false;
                existingReport.DeletedAt = null;
                existingReport.Reason = request.Reason.Trim();
                existingReport.UpdatedAt = DateTime.UtcNow;
                await _reportRepo.UpdateAsync(existingReport.Id, existingReport);
            }
            else
            {
                await _reportRepo.CreateAsync(new PostReport
                {
                    PostId = postId,
                    UserId = currentUserId,
                    Reason = request.Reason.Trim(),
                    CreatedAt = DateTime.UtcNow
                });
            }

            await _postRepo.IncrementFieldAsync(postId, p => p.ReportCount, 1);
            var currentReportCount = post.ReportCount + 1;

            // Nếu bài viết bị báo cáo từ 3 lần trở lên -> chuyển sang Pending để ẩn khỏi feed
            if (currentReportCount >= 3 && post.Status == PostAccess.Published)
            {
                await _postRepo.UpdateFieldAsync(postId, p => p.Status, PostAccess.Pending);
                _logger.LogWarning("Bài viết {PostId} đã bị ẩn khỏi feed do nhận {Count} lượt báo cáo vi phạm.", postId, currentReportCount);
            }

            return true;
        }

        public async Task<PostResponse> ModeratePostAsync(string postId, string actionOrDecision, string? reason = null)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException(PostAccess.NotFoundMessage);
            }

            var cleanReason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim();
            var clearReports = false;

            var act = actionOrDecision.Trim().ToLowerInvariant();
            switch (act)
            {
                case "approve":
                case "published":
                    if (post.Status != PostAccess.Pending && post.Status != PostAccess.Rejected && post.Status != PostAccess.Published)
                    {
                        throw new ConflictException($"Không thể chuyển trạng thái bài viết từ '{post.Status}' sang 'Published'.");
                    }
                    post.Status = PostAccess.Published;
                    post.ReportCount = 0;
                    post.RejectionReason = null;
                    post.UpdatedAt = DateTime.UtcNow;
                    clearReports = true;
                    break;

                case "reject":
                case "rejected":
                    if (post.Status != PostAccess.Pending && post.Status != PostAccess.Published)
                    {
                        throw new ConflictException($"Không thể từ chối bài viết đang ở trạng thái '{post.Status}'.");
                    }
                    post.Status = PostAccess.Rejected;
                    post.RejectionReason = cleanReason ?? "Vi phạm tiêu chuẩn cộng đồng";
                    post.UpdatedAt = DateTime.UtcNow;
                    break;

                case "pending":
                    // Đưa về chờ duyệt: từ Published hoặc Rejected. Bài đang ẩn phải bỏ ẩn trước, để không gỡ ẩn lén.
                    if (post.Status == PostAccess.Hidden)
                    {
                        throw new ConflictException("Bài viết đang ẩn. Bỏ ẩn trước khi đưa về chờ duyệt.");
                    }
                    post.Status = PostAccess.Pending;
                    post.RejectionReason = null;
                    post.UpdatedAt = DateTime.UtcNow;
                    break;

                case "hide":
                case "hidden":
                    if (post.Status != PostAccess.Published)
                    {
                        throw new ConflictException($"Chỉ có thể ẩn bài viết đang ở trạng thái 'Published'. Trạng thái hiện tại: '{post.Status}'.");
                    }
                    post.Status = PostAccess.Hidden;
                    post.RejectionReason = cleanReason;
                    post.UpdatedAt = DateTime.UtcNow;
                    break;

                case "unhide":
                    if (post.Status != PostAccess.Hidden)
                    {
                        throw new ConflictException($"Chỉ có thể bỏ ẩn bài viết đang ở trạng thái 'Hidden'. Trạng thái hiện tại: '{post.Status}'.");
                    }
                    post.Status = PostAccess.Published;
                    post.ReportCount = 0;
                    post.RejectionReason = null;
                    post.UpdatedAt = DateTime.UtcNow;
                    clearReports = true;
                    break;

                case "pin":
                    post.IsPinned = true;
                    post.UpdatedAt = DateTime.UtcNow;
                    break;

                case "unpin":
                    post.IsPinned = false;
                    post.UpdatedAt = DateTime.UtcNow;
                    break;

                case "delete":
                    post.IsDeleted = true;
                    post.DeletedAt = DateTime.UtcNow;
                    break;

                default:
                    throw new BadRequestException($"Hành động kiểm duyệt không hợp lệ: '{actionOrDecision}'.");
            }

            await _postRepo.UpdateAsync(postId, post);

            if (clearReports)
            {
                // B51: đã xem xét xong các báo cáo này; ai từng báo cáo được báo cáo lại nếu bài lại có vấn đề.
                var reports = (await _reportRepo.FindAsync(r => r.PostId == postId && !r.IsDeleted)).ToList();
                foreach (var report in reports)
                {
                    report.IsDeleted = true;
                    report.DeletedAt = DateTime.UtcNow;
                    await _reportRepo.UpdateAsync(report.Id, report);
                }
            }

            return MapToResponse(post, await AuthorOfAsync(post.UserId), false);
        }

        public async Task<FeedPageResponse> GetAdminPostsAsync(string? status, int page, int pageSize, string? search = null)
        {
            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 50);

            var canonicalStatus = PostAccess.CanonicalStatus(status);
            var term = string.IsNullOrWhiteSpace(search) ? null : search.Trim().ToLowerInvariant();

            Expression<Func<Post, bool>> filter = x =>
                !x.IsDeleted &&
                (canonicalStatus == null || x.Status == canonicalStatus) &&
                (term == null || x.Title.ToLower().Contains(term) || x.Body.ToLower().Contains(term));

            var totalItems = await _postRepo.CountAsync(filter);
            var posts = (await _postRepo.FindPagedAsync(
                filter,
                page,
                pageSize,
                sortDesc: x => x.CreatedAt
            )).ToList();

            var authors = await AuthorsOfAsync(posts);

            var postDtos = posts.Select(p => MapToResponse(
                p,
                authors.TryGetValue(p.UserId, out var a) ? a : new AuthorSummaryDto { Id = p.UserId, FullName = "Thành viên" },
                false
            )).ToList();

            return new FeedPageResponse
            {
                Items = postDtos,
                Page = page,
                PageSize = pageSize,
                TotalItems = totalItems,
                TotalPages = (int)Math.Ceiling(totalItems / (double)pageSize),
                NextCursor = (posts.Count == pageSize && (page * pageSize) < totalItems) ? posts.Last().Id : null
            };
        }

        private async Task<(List<Post> Posts, string? NextCursor)> CursorPageAsync(Expression<Func<Post, bool>> filter, string? cursor, int pageSize)
        {
            if (!string.IsNullOrWhiteSpace(cursor) && !MongoDB.Bson.ObjectId.TryParse(cursor, out _))
            {
                throw new BadRequestException("Cursor không hợp lệ.");
            }

            var candidates = (await _postRepo.FindCursorAsync(filter, string.IsNullOrWhiteSpace(cursor) ? null : cursor, pageSize + 1)).ToList();
            if (candidates.Count <= pageSize) return (candidates, null);

            var posts = candidates.Take(pageSize).ToList();
            return (posts, posts.Last().Id);
        }

        private async Task<AuthorSummaryDto> AuthorOfAsync(string userId)
        {
            var user = await _userRepo.FindByIdAsync(userId);
            return user != null && !user.IsDeleted
                ? new AuthorSummaryDto
                {
                    Id = user.Id,
                    FullName = user.FullName,
                    IsVerifiedChef = user.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                }
                : new AuthorSummaryDto { Id = userId, FullName = "Thành viên" };
        }

        // Gộp danh sách tác giả từ MongoDB để tránh N+1 query
        private async Task<Dictionary<string, AuthorSummaryDto>> AuthorsOfAsync(IEnumerable<Post> posts)
        {
            var authorIds = posts.Select(p => p.UserId).Distinct().ToList();
            return (await _userRepo.FindAsync(u => authorIds.Contains(u.Id) && !u.IsDeleted))
                .ToDictionary(
                    u => u.Id,
                    u => new AuthorSummaryDto
                    {
                        Id = u.Id,
                        FullName = u.FullName,
                        IsVerifiedChef = u.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                    });
        }

        private async Task<List<PostResponse>> MapManyAsync(List<Post> posts, string? currentUserId)
        {
            var authors = await AuthorsOfAsync(posts);

            var likedPostIds = new HashSet<string>();
            var savedPostIds = new HashSet<string>();
            if (!string.IsNullOrEmpty(currentUserId))
            {
                var postIds = posts.Select(p => p.Id).ToList();
                var userLikes = await _likeRepo.FindAsync(l => l.UserId == currentUserId && postIds.Contains(l.PostId) && !l.IsDeleted);
                likedPostIds = userLikes.Select(l => l.PostId).ToHashSet();
                if (_saveRepo != null)
                {
                    var userSaves = await _saveRepo.FindAsync(s => s.UserId == currentUserId && postIds.Contains(s.PostId) && !s.IsDeleted);
                    savedPostIds = userSaves.Select(s => s.PostId).ToHashSet();
                }
            }

            var dtos = posts.Select(p => MapToResponse(
                p,
                authors.TryGetValue(p.UserId, out var author) ? author : new AuthorSummaryDto { Id = p.UserId, FullName = "Thành viên" },
                likedPostIds.Contains(p.Id),
                savedPostIds.Contains(p.Id)
            )).ToList();

            await AttachRestaurantsAsync(posts, dtos);
            return dtos;
        }

        private async Task<PostResponse> WithRestaurantAsync(Post post, PostResponse dto)
        {
            await AttachRestaurantsAsync(new[] { post }, new[] { dto });
            return dto;
        }

        /// <summary>Gộp một truy vấn cho cả trang. Quán chưa duyệt hoặc đã xoá thì không hiện.</summary>
        private async Task AttachRestaurantsAsync(IReadOnlyList<Post> posts, IReadOnlyList<PostResponse> dtos)
        {
            if (_restaurantRepo == null) return;
            var ids = posts.Where(p => !string.IsNullOrEmpty(p.RestaurantId)).Select(p => p.RestaurantId!).Distinct().ToList();
            if (ids.Count == 0) return;

            var restaurants = (await _restaurantRepo.FindAsync(r => ids.Contains(r.Id) && !r.IsDeleted && r.Status == RestaurantStatuses.Approved))
                .ToDictionary(r => r.Id);
            for (var i = 0; i < posts.Count; i++)
            {
                if (posts[i].RestaurantId is { } id && restaurants.TryGetValue(id, out var r))
                {
                    dtos[i].Restaurant = new { id = r.Id, name = r.Name, isCertified = r.IsVeganCertified };
                }
            }
        }

        private static bool IsDuplicateKey(Exception ex) =>
            ex.Message.Contains("11000") || ex.Message.Contains("duplicate key", StringComparison.OrdinalIgnoreCase);

        internal static PostResponse MapToResponse(Post p, AuthorSummaryDto author, bool likedByMe, bool savedByMe = false)
        {
            return new PostResponse
            {
                Id = p.Id,
                Type = p.Type,
                Author = author,
                Title = p.Title,
                Body = p.Body,
                Tags = p.Tags,
                CoverSeed = p.CoverSeed ?? p.Id,
                LikeCount = Math.Max(0, p.LikeCount),
                CommentCount = Math.Max(0, p.CommentCount),
                ReportCount = p.ReportCount,
                RejectionReason = p.RejectionReason,
                LikedByMe = likedByMe,
                SavedByMe = savedByMe,
                IsPinned = p.IsPinned,
                CreatedAt = p.CreatedAt,
                Status = p.Status,
                MediaType = p.MediaType,
                MediaUrl = p.MediaUrl,
                Video = null,
                Restaurant = null,
                UpdatedAt = p.UpdatedAt
            };
        }
    }
}
