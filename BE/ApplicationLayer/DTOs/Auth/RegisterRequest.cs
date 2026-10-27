using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO nhận request đăng ký. POST /auth/register
    /// Luôn tạo role "User". Trở thành Chef phải được Admin duyệt riêng.
    /// </summary>
    public class RegisterRequest
    {
        [Required(ErrorMessage = "Họ tên là bắt buộc.")]
        [MaxLength(100, ErrorMessage = "Họ tên không được vượt quá 100 ký tự.")]
        public string FullName { get; set; } = string.Empty;

        [Required(ErrorMessage = "Email là bắt buộc.")]
        [EmailAddress(ErrorMessage = "Email không đúng định dạng.")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mật khẩu là bắt buộc.")]
        [MinLength(8, ErrorMessage = "Mật khẩu phải có ít nhất 8 ký tự.")]
        public string Password { get; set; } = string.Empty;

        [MaxLength(15, ErrorMessage = "Số điện thoại không hợp lệ.")]
        public string? Phone { get; set; }
    }
}
