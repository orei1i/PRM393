using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO nhận request quên mật khẩu. POST /auth/forgot-password
    /// Server luôn trả 204 dù email có tồn tại hay không (tránh enumeration).
    /// </summary>
    public class ForgotPasswordRequest
    {
        [Required(ErrorMessage = "Email là bắt buộc.")]
        [EmailAddress(ErrorMessage = "Email không đúng định dạng.")]
        public string Email { get; set; } = string.Empty;
    }
}
