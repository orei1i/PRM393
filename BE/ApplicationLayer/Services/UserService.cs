using ApplicationLayer.DTOs.Users;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Xử lý business logic liên quan đến User.
    /// Không inject Repository trực tiếp vào Controller nữa — tất cả đi qua đây.
    /// </summary>
    public class UserService : IUserService
    {
        private readonly IGenericRepository<User> _userRepository;

        public UserService(IGenericRepository<User> userRepository)
        {
            _userRepository = userRepository;
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
                       ?? throw new KeyNotFoundException($"Không tìm thấy user với id: {id}");

            if (user.IsDeleted)
                throw new KeyNotFoundException($"Không tìm thấy user với id: {id}");

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

        // ─── Mapping helper ──────────────────────────────────────────────
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
    }
}
