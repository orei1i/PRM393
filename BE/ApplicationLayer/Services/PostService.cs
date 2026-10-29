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
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    public class PostService : IPostService
    {
        private readonly IGenericRepository<Post> _postRepo;
        private readonly IGenericRepository<User> _userRepo;
        private readonly IGenericRepository<PostLike> _likeRepo;
        private readonly IGenericRepository<PostReport> _reportRepo;
        private readonly IMediaService _mediaService;
        private readonly ILogger<PostService> _logger;

        public PostService(
            IGenericRepository<Post> postRepo,
            IGenericRepository<User> userRepo,
            IGenericRepository<PostLike> likeRepo,
            IGenericRepository<PostReport> reportRepo,
            IMediaService mediaService,
            ILogger<PostService> logger)
        {
            _postRepo = postRepo;
            _userRepo = userRepo;
            _likeRepo = likeRepo;
            _reportRepo = reportRepo;
            _mediaService = mediaService;
            _logger = logger;
        }

        public async Task<FeedPageResponse> GetFeedAsync(
            int page,
            int pageSize,
            string? type,
            string? mediaType,
            string? currentUserId)
        {
            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 50);

            // Filter chỉ bài Published và chưa xóa
            Expression<Func<Post, bool>> filter = x =>
                !x.IsDeleted &&
                x.Status == "Published" &&
                (string.IsNullOrEmpty(type) || x.Type == type) &&
                (string.IsNullOrEmpty(mediaType) || x.MediaType == mediaType);

            var totalItems = await _postRepo.CountAsync(filter);
            var posts = (await _postRepo.FindPagedAsync(
                filter,
                page,
                pageSize,
                sortDesc: x => x.CreatedAt
            )).ToList();

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

            // Gộp danh sách tác giả từ MongoDB để tránh N+1 query
            var authorIds = posts.Select(p => p.UserId).Distinct().ToList();
            var authors = (await _userRepo.FindAsync(u => authorIds.Contains(u.Id) && !u.IsDeleted))
                .ToDictionary(
                    u => u.Id,
                    u => new AuthorSummaryDto
                    {
                        Id = u.Id,
                        FullName = u.FullName,
                        IsVerifiedChef = u.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                    });

            // Lấy danh sách post mà user hiện tại đã like
            var likedPostIds = new HashSet<string>();
            if (!string.IsNullOrEmpty(currentUserId))
            {
                var postIds = posts.Select(p => p.Id).ToList();
                var userLikes = await _likeRepo.FindAsync(l =>
                    l.UserId == currentUserId &&
                    postIds.Contains(l.PostId) &&
                    !l.IsDeleted);

                likedPostIds = userLikes.Select(l => l.PostId).ToHashSet();
            }

            var postDtos = posts.Select(p => MapToResponse(
                p,
                authors.TryGetValue(p.UserId, out var author) ? author : new AuthorSummaryDto { Id = p.UserId, FullName = "Thành viên" },
                likedPostIds.Contains(p.Id)
            )).ToList();

            return new FeedPageResponse
            {
                Items = postDtos,
                Page = page,
                PageSize = pageSize,
                TotalItems = totalItems,
                TotalPages = (int)Math.Ceiling(totalItems / (double)pageSize),
                NextCursor = postDtos.Count == pageSize ? postDtos.Last().Id : null
            };
        }

        public async Task<PostResponse> GetPostByIdAsync(string id, string? currentUserId)
        {
            var post = await _postRepo.FindByIdAsync(id);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy bài viết với id: {id}");
            }

            // Nếu bài viết không phải Published, chỉ tác giả mới xem được
            if (post.Status != "Published" && post.UserId != currentUserId)
            {
                throw new NotFoundException("Bài viết đang chờ duyệt hoặc không khả dụng.");
            }

            var user = await _userRepo.FindByIdAsync(post.UserId);
            var author = user != null
                ? new AuthorSummaryDto
                {
                    Id = user.Id,
                    FullName = user.FullName,
                    IsVerifiedChef = user.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                }
                : new AuthorSummaryDto { Id = post.UserId, FullName = "Thành viên" };

            var liked = false;
            if (!string.IsNullOrEmpty(currentUserId))
            {
                var like = await _likeRepo.FirstOrDefaultAsync(l =>
                    l.PostId == id &&
                    l.UserId == currentUserId &&
                    !l.IsDeleted);
                liked = like != null;
            }

            return MapToResponse(post, author, liked);
        }

        public async Task<PostResponse> CreatePostAsync(CreatePostRequest request, string currentUserId)
        {
            // Kiểm tra URL media có do chính user này upload lên không
            if (!string.IsNullOrWhiteSpace(request.MediaUrl))
            {
                var isOwner = await _mediaService.ValidateOwnerAsync(request.MediaUrl, currentUserId);
                if (!isOwner)
                {
                    throw new BadRequestException("Tài nguyên media không tồn tại hoặc không thuộc quyền sở hữu của bạn.");
                }
            }

            var post = new Post
            {
                UserId = currentUserId,
                Type = string.IsNullOrWhiteSpace(request.Type) ? "discussion" : request.Type.ToLowerInvariant(),
                Title = request.Title.Trim(),
                Body = request.Body.Trim(),
                Tags = request.Tags ?? new List<string>(),
                MediaType = !string.IsNullOrWhiteSpace(request.MediaType)
                    ? request.MediaType
                    : (!string.IsNullOrWhiteSpace(request.MediaUrl) ? "Image" : "Text"),
                MediaUrl = request.MediaUrl,
                RestaurantId = request.RestaurantId,
                Status = "Published",
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

            return MapToResponse(post, author, false);
        }

        public async Task<bool> DeletePostAsync(string id, string currentUserId, string? role)
        {
            var post = await _postRepo.FindByIdAsync(id);
            if (post == null || post.IsDeleted)
            {
                return false;
            }

            var isAdmin = role?.Equals("Admin", StringComparison.OrdinalIgnoreCase) == true;
            if (post.UserId != currentUserId && !isAdmin)
            {
                throw new ForbiddenException("Bạn không có quyền xóa bài viết này.");
            }

            post.IsDeleted = true;
            post.DeletedAt = DateTime.UtcNow;
            await _postRepo.UpdateAsync(id, post);
            return true;
        }

        public async Task<LikeResponse> ToggleLikeAsync(string postId, string currentUserId)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy bài viết với id: {postId}");
            }

            var existingLike = await _likeRepo.FirstOrDefaultAsync(l =>
                l.PostId == postId &&
                l.UserId == currentUserId &&
                !l.IsDeleted);

            if (existingLike != null)
            {
                // Bỏ like
                existingLike.IsDeleted = true;
                existingLike.DeletedAt = DateTime.UtcNow;
                await _likeRepo.UpdateAsync(existingLike.Id, existingLike);

                await _postRepo.IncrementFieldAsync(postId, p => p.LikeCount, -1);
                var newCount = Math.Max(0, post.LikeCount - 1);
                return new LikeResponse { Liked = false, LikeCount = newCount };
            }
            else
            {
                // Thêm like
                var like = new PostLike
                {
                    PostId = postId,
                    UserId = currentUserId,
                    CreatedAt = DateTime.UtcNow
                };
                await _likeRepo.CreateAsync(like);

                await _postRepo.IncrementFieldAsync(postId, p => p.LikeCount, 1);
                var newCount = post.LikeCount + 1;
                return new LikeResponse { Liked = true, LikeCount = newCount };
            }
        }

        public async Task<bool> ReportPostAsync(string postId, string currentUserId, ReportPostRequest request)
        {
            var post = await _postRepo.FindByIdAsync(postId);
            if (post == null || post.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy bài viết với id: {postId}");
            }

            var existingReport = await _reportRepo.FirstOrDefaultAsync(r =>
                r.PostId == postId &&
                r.UserId == currentUserId &&
                !r.IsDeleted);

            if (existingReport != null)
            {
                throw new ConflictException("Bạn đã báo cáo bài viết này rồi.");
            }

            var report = new PostReport
            {
                PostId = postId,
                UserId = currentUserId,
                Reason = request.Reason.Trim(),
                CreatedAt = DateTime.UtcNow
            };
            await _reportRepo.CreateAsync(report);

            await _postRepo.IncrementFieldAsync(postId, p => p.ReportCount, 1);
            var currentReportCount = post.ReportCount + 1;

            // Nếu bài viết bị báo cáo từ 3 lần trở lên -> chuyển sang Pending để ẩn khỏi feed
            if (currentReportCount >= 3 && post.Status == "Published")
            {
                await _postRepo.UpdateFieldAsync(postId, p => p.Status, "Pending");
                _logger.LogWarning("Bài viết {PostId} đã bị ẩn khỏi feed do nhận {Count} lượt báo cáo vi phạm.", postId, currentReportCount);
            }

            return true;
        }

        private static PostResponse MapToResponse(Post p, AuthorSummaryDto author, bool likedByMe)
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
                LikedByMe = likedByMe,
                SavedByMe = false,
                IsPinned = p.IsPinned,
                CreatedAt = p.CreatedAt,
                Status = p.Status,
                MediaType = p.MediaType,
                MediaUrl = p.MediaUrl,
                Video = p.MediaType == "Video" && !string.IsNullOrEmpty(p.MediaUrl)
                    ? new VideoSummaryDto { Id = p.Id, DurationSeconds = 0, AiStatus = "ready" }
                    : null,
                Restaurant = null,
                UpdatedAt = p.UpdatedAt
            };
        }
    }
}
