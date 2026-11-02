using ApplicationLayer.DTOs.Users;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Enums;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Xử lý business logic liên quan đến User.
    /// </summary>
    public class UserService : IUserService
    {
        private readonly IGenericRepository<User> _userRepository;
        private readonly IGenericRepository<Post> _postRepository;
        private readonly IMemoryCache? _cache;

        public UserService(
            IGenericRepository<User> userRepository,
            IGenericRepository<Post> postRepository,
            IMemoryCache? cache = null)
        {
            _userRepository = userRepository;
            _postRepository = postRepository;
            _cache = cache;
        }

        public async Task<IEnumerable<UserResponse>> GetAllUsersAsync()
        {
            var users = await _userRepository.GetAllAsync();
            return users.Where(u => !u.IsDeleted).Select(MapToResponse);
        }

        public async Task<(IEnumerable<UserResponse> Items, long TotalCount)> GetPagedUsersAsync(int page, int pageSize, string? search = null)
        {
            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 100);

            System.Linq.Expressions.Expression<Func<User, bool>> filter;
            if (!string.IsNullOrWhiteSpace(search))
            {
                var s = search.Trim();
                filter = u => !u.IsDeleted && (u.FullName.Contains(s) || u.Email.Contains(s));
            }
            else
            {
                filter = u => !u.IsDeleted;
            }

            var totalCount = await _userRepository.CountAsync(filter);
            var users = await _userRepository.FindPagedAsync(
                filter,
                page,
                pageSize,
                sortDesc: u => u.CreatedAt);

            return (users.Select(MapToResponse), totalCount);
        }

        public async Task<UserResponse?> GetUserByIdAsync(string id)
        {
            var user = await _userRepository.FindByIdAsync(id);
            if (user == null || user.IsDeleted) return null;
            return MapToResponse(user);
        }

        public async Task<UserResponse> UpdateUserAsync(string id, UpdateUserRequest request)
        {
            var user = await _userRepository.FindByIdAsync(id)
                       ?? throw new NotFoundException($"Không tìm thấy user với id: {id}");

            if (user.IsDeleted)
                throw new NotFoundException($"Không tìm thấy user với id: {id}");

            user.FullName = request.FullName;
            if (request.Phone != null) user.Phone = request.Phone;
            user.UpdatedAt = DateTime.UtcNow;

            await _userRepository.UpdateAsync(id, user);
            return MapToResponse(user);
        }

        public async Task<bool> DeleteUserAsync(string id, string? currentUserId = null)
        {
            if (!string.IsNullOrEmpty(currentUserId) && id == currentUserId)
            {
                throw new BadRequestException("Không thể tự xóa tài khoản của chính mình.");
            }

            var user = await _userRepository.FindByIdAsync(id);
            if (user == null || user.IsDeleted) return false;

            if (user.Role == "Admin")
            {
                var adminCount = await _userRepository.CountAsync(u => u.Role == "Admin" && !u.IsDeleted);
                if (adminCount <= 1)
                {
                    throw new ConflictException("Không thể xóa Quản trị viên cuối cùng của hệ thống.");
                }
            }

            // Soft delete
            user.IsDeleted = true;
            user.DeletedAt = DateTime.UtcNow;
            user.UpdatedAt = DateTime.UtcNow;
            user.RefreshTokenHash = null;
            user.RefreshTokenExpiresAt = null;

            await _userRepository.UpdateAsync(id, user);

            // B54: Xóa cache trạng thái user ngay lập tức để token mất hiệu lực
            _cache?.Remove(UserCacheKeys.UserStatus(id));

            return true;
        }

        public async Task<UserProfileResponse> GetCurrentUserProfileAsync(string userId)
        {
            var user = await _userRepository.FindByIdAsync(userId);
            if (user == null || user.IsDeleted)
                throw new NotFoundException($"Không tìm thấy user với id: {userId}");

            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException();

            var userPosts = await _postRepository.FindAsync(p => p.UserId == userId && !p.IsDeleted);
            var postList = userPosts.ToList();
            var totalPosts = postList.Count;
            var totalLikes = postList.Sum(p => p.LikeCount);

            return MapToProfileResponse(user, totalPosts, totalLikes);
        }

        // ─── Mapping helpers ──────────────────────────────────────────────────
        private static UserResponse MapToResponse(User user) => new()
        {
            Id        = user.Id,
            Email     = user.Email,
            FullName  = user.FullName,
            Phone     = user.Phone,
            Role      = user.Role,
            Status    = user.Status,
            AuthType  = user.AuthType,
            CreatedAt = user.CreatedAt
        };

        private static UserProfileResponse MapToProfileResponse(User user, int totalPosts = 0, int totalLikes = 0) => new()
        {
            Id        = user.Id,
            Email     = user.Email,
            FullName  = user.FullName,
            Phone     = user.Phone,
            Role      = user.Role,
            Status    = user.Status,
            AuthType  = user.AuthType,
            CreatedAt = user.CreatedAt,
            Stats     = new UserStatsDto
            {
                Posts = totalPosts,
                LikesReceived = totalLikes,
                Saved = 0
            },
            ChefApplication = new ChefApplicationSummaryDto
            {
                Status = user.Role == "Chef" ? "approved" : "none",
                RejectReason = null
            }
        };
    }
}
