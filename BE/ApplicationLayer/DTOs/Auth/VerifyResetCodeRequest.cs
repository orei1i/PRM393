using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO xác minh mã reset. POST /auth/verify-reset-code
    /// Trả về resetToken nếu hợp lệ.
    /// </summary>
    public class VerifyResetCodeRequest
    {
        [Required(ErrorMessage = "Email là bắt buộc.")]
        [EmailAddress(ErrorMessage = "Email không đúng định dạng.")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Mã xác minh là bắt buộc.")]
        [StringLength(6, MinimumLength = 6, ErrorMessage = "Mã xác minh phải đúng 6 ký tự.")]
        public string Code { get; set; } = string.Empty;
    }
}
