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

        /// <summary>Lấy danh sách users có phân trang và tìm kiếm.</summary>
        Task<(IEnumerable<AdminUserResponse> Items, long TotalCount)> GetPagedUsersAsync(int page, int pageSize, string? search = null, string? role = null, string? status = null);

        /// <summary>Đổi vai trò. Admin không tự đổi được của mình.</summary>
        Task<AdminUserResponse> ChangeRoleAsync(string id, string role, string currentUserId);

        /// <summary>Khoá hoặc mở khoá. Admin không tự khoá được mình. Khoá thì token của người đó hết tác dụng ngay.</summary>
        Task<AdminUserResponse> ChangeStatusAsync(string id, string status, string? reason, string currentUserId);

        /// <summary>Lấy thông tin user theo Id.</summary>
        Task<UserResponse?> GetUserByIdAsync(string id);

        /// <summary>Cập nhật thông tin user.</summary>
        Task<UserResponse> UpdateUserAsync(string id, UpdateUserRequest request);

        /// <summary>Xóa mềm user (soft delete).</summary>
        Task<bool> DeleteUserAsync(string id, string? currentUserId = null);

        /// <summary>Lấy thông tin hồ sơ của người dùng hiện tại (kèm stats và chefApplication).</summary>
        Task<UserProfileResponse> GetCurrentUserProfileAsync(string userId);
    }
}
