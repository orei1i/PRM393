using ApplicationLayer.DTOs.Users;

namespace ApplicationLayer.DTOs.Auth
{
    /// <summary>
    /// DTO trả về sau khi đăng nhập / đăng ký thành công.
    /// </summary>
    public class AuthResponse
    {
        public string AccessToken { get; set; } = string.Empty;
        public string? RefreshToken { get; set; }
        public DateTime ExpiresAt { get; set; }
        public UserResponse User { get; set; } = null!;
    }
}
