using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO nhận request đăng nhập. POST /auth/login
    /// </summary>
    public class LoginRequest
    {
        [Required(ErrorMessage = "Email là bắt buộc.")]
        [EmailAddress(ErrorMessage = "Email không đúng định dạng.")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mật khẩu là bắt buộc.")]
        public string Password { get; set; } = string.Empty;
    }
}
