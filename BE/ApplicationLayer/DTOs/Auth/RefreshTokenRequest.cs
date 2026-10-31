using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Auth
{
    public class RefreshTokenRequest
    {
        [Required(ErrorMessage = "RefreshToken là bắt buộc.")]
        public string RefreshToken { get; set; } = string.Empty;
    }
}

