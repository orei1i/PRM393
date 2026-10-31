using ApplicationLayer.DTOs.Users;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Enums;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Xá»­ lÃ½ business logic liÃªn quan Ä‘áº¿n User.
    /// KhÃ´ng inject Repository trá»±c tiáº¿p vÃ o Controller ná»¯a â€” táº¥t cáº£ Ä‘i qua Ä‘Ã¢y.
    /// </summary>
    public class UserService : IUserService
    {
        private readonly IGenericRepository<User> _userRepository;
        private readonly IGenericRepository<Post> _postRepository;

        public UserService(IGenericRepository<User> userRepository, IGenericRepository<Post> postRepository)
        {
            _userRepository = userRepository;
            _postRepository = postRepository;
        }

        public async Task<IEnumerable<UserResponse>> GetAllUsersAsync()
        {
            var users = await _userRepository.GetAllAsync();
            return users.Where(u => !u.IsDeleted).Select(MapToResponse);
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
                       ?? throw new KeyNotFoundException($"KhÃ´ng tÃ¬m tháº¥y user vá»›i id: {id}");

            if (user.IsDeleted)
                throw new KeyNotFoundException($"KhÃ´ng tÃ¬m tháº¥y user vá»›i id: {id}");

            user.FullName = request.FullName;
            if (request.Phone != null) user.Phone = request.Phone;
            user.UpdatedAt = DateTime.UtcNow;

            await _userRepository.UpdateAsync(id, user);
            return MapToResponse(user);
        }

        public async Task<bool> DeleteUserAsync(string id)
        {
            var user = await _userRepository.FindByIdAsync(id);
            if (user == null || user.IsDeleted) return false;

            // Soft delete
            user.IsDeleted = true;
            user.DeletedAt = DateTime.UtcNow;
            user.UpdatedAt = DateTime.UtcNow;

            await _userRepository.UpdateAsync(id, user);
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

        // ─── Mapping helpers ──────────────────────────────────────────────
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
