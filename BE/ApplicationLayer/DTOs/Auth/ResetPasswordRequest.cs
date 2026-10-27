using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO đặt lại mật khẩu. POST /auth/reset-password
    /// </summary>
    public class ResetPasswordRequest
    {
        [Required(ErrorMessage = "Reset token là bắt buộc.")]
        public string ResetToken { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mật khẩu mới là bắt buộc.")]
        [MinLength(8, ErrorMessage = "Mật khẩu phải có ít nhất 8 ký tự.")]
        public string NewPassword { get; set; } = string.Empty;
    }
}
