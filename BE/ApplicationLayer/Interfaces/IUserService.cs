using ApplicationLayer.DTOs.Users;

namespace ApplicationLayer.Interfaces
{
    /// <summary>
    /// Service interface xử lý business logic liên quan đến User.
    /// </summary>
    public interface IUserService
    {
        /// <summary>Lấy danh sách tất cả users.</summary>
        Task<IEnumerable<UserResponse>> GetAllUsersAsync();

        /// <summary>Lấy thông tin user theo Id.</summary>
        Task<UserResponse?> GetUserByIdAsync(string id);

        /// <summary>Cập nhật thông tin user.</summary>
        Task<UserResponse> UpdateUserAsync(string id, UpdateUserRequest request);

        /// <summary>Xóa mềm user (soft delete).</summary>
        Task<bool> DeleteUserAsync(string id);
    }
}
