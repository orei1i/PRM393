using ApplicationLayer.DTOs.Auth;

namespace ApplicationLayer.Interfaces
{
    /// <summary>
    /// Service xá»­ lÃ½ authentication: login, register, forgot-password, verify-reset-code, reset-password.
    /// </summary>
    public interface IAuthService
    {
        /// <summary>POST /auth/login — xác thực email + password, trả JWT.</summary>
        Task<AuthResponse> LoginAsync(LoginRequest request);

        /// <summary>POST /auth/admin/login — đăng nhập dành riêng cho Quản trị viên (Admin).</summary>
        Task<AuthResponse> AdminLoginAsync(LoginRequest request);

        /// <summary>POST /auth/refresh — làm mới access token bằng refresh token (xoay vòng token).</summary>
        Task<AuthResponse> RefreshTokenAsync(RefreshTokenRequest request);

        /// <summary>POST /auth/logout — thu hồi refresh token hiện tại.</summary>
        Task LogoutAsync(string userId);

        /// <summary>POST /auth/register â€” táº¡o tÃ i khoáº£n role "User", tráº£ JWT.</summary>
        Task<AuthResponse> RegisterAsync(RegisterRequest request);

        /// <summary>POST /auth/forgot-password â€” gá»­i mÃ£ reset (luÃ´n 204, khÃ´ng tiáº¿t lá»™ email).</summary>
        Task ForgotPasswordAsync(ForgotPasswordRequest request);

        /// <summary>POST /auth/verify-reset-code â€” xÃ¡c minh mÃ£, tráº£ resetToken.</summary>
        Task<VerifyResetCodeResponse> VerifyResetCodeAsync(VerifyResetCodeRequest request);

        /// <summary>POST /auth/reset-password â€” Ä‘áº·t láº¡i máº­t kháº©u báº±ng resetToken.</summary>
        Task ResetPasswordAsync(ResetPasswordRequest request);
    }
}
