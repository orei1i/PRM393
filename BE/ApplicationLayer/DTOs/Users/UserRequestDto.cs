using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Users
{
    /// <summary>
    /// DTO dùng khi đăng ký tài khoản mới.
    /// </summary>
    public class RegisterRequest
    {
        [Required(ErrorMessage = "Email là bắt buộc.")]
        [EmailAddress(ErrorMessage = "Email không hợp lệ.")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mật khẩu là bắt buộc.")]
        [MinLength(6, ErrorMessage = "Mật khẩu phải có ít nhất 6 ký tự.")]
        public string Password { get; set; } = string.Empty;

        [Required(ErrorMessage = "Họ tên là bắt buộc.")]
        public string FullName { get; set; } = string.Empty;

        [Required(ErrorMessage = "Số điện thoại là bắt buộc.")]
        [Phone(ErrorMessage = "Số điện thoại không hợp lệ.")]
        public string Phone { get; set; } = string.Empty;
    }

    /// <summary>
    /// DTO dùng khi đăng nhập bằng email/password.
    /// </summary>
    public class LoginRequest
    {
        [Required(ErrorMessage = "Email là bắt buộc.")]
        [EmailAddress(ErrorMessage = "Email không hợp lệ.")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mật khẩu là bắt buộc.")]
        public string Password { get; set; } = string.Empty;
    }

    /// <summary>PATCH /users/{id}/role. "Chef" chỉ được cấp khi duyệt hồ sơ chuyên gia, không đổi ở đây.</summary>
    public class ChangeUserRoleRequest
    {
        [Required(ErrorMessage = "Vai trò là bắt buộc.")]
        [RegularExpression("^(Admin|User)$", ErrorMessage = "Vai trò chỉ nhận 'Admin' hoặc 'User'.")]
        public string Role { get; set; } = string.Empty;
    }

    /// <summary>PATCH /users/{id}/status.</summary>
    public class ChangeUserStatusRequest
    {
        [Required(ErrorMessage = "Trạng thái là bắt buộc.")]
        [RegularExpression("^(Active|Locked|Banned)$", ErrorMessage = "Trạng thái chỉ nhận 'Active', 'Locked' hoặc 'Banned'.")]
        public string Status { get; set; } = string.Empty;

        [MaxLength(500, ErrorMessage = "Lý do không được vượt quá 500 ký tự.")]
        public string? Reason { get; set; }
    }

    /// <summary>
    /// DTO dùng khi cập nhật thông tin cá nhân.
    /// </summary>
    public class UpdateUserRequest
    {
        [Required(ErrorMessage = "Họ tên là bắt buộc.")]
        [StringLength(100, MinimumLength = 2, ErrorMessage = "Họ tên phải từ 2 đến 100 ký tự.")]
        public string FullName { get; set; } = string.Empty;

        [RegularExpression(@"^$|^(0|\+84)[0-9]{8,11}$", ErrorMessage = "Số điện thoại không hợp lệ.")]
        public string? Phone { get; set; }
    }
}
