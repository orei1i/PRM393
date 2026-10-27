using ApplicationLayer.DTOs.Auth;

namespace ApplicationLayer.Interfaces
{
    /// <summary>
    /// Service xử lý authentication: login, register, forgot-password, verify-reset-code, reset-password.
    /// </summary>
    public interface IAuthService
    {
        /// <summary>POST /auth/login — xác thực email + password, trả JWT.</summary>
        Task<AuthResponse> LoginAsync(LoginRequest request);

        /// <summary>POST /auth/register — tạo tài khoản role "User", trả JWT.</summary>
        Task<AuthResponse> RegisterAsync(RegisterRequest request);

        /// <summary>POST /auth/forgot-password — gửi mã reset (luôn 204, không tiết lộ email).</summary>
        Task ForgotPasswordAsync(ForgotPasswordRequest request);

        /// <summary>POST /auth/verify-reset-code — xác minh mã, trả resetToken.</summary>
        Task<VerifyResetCodeResponse> VerifyResetCodeAsync(VerifyResetCodeRequest request);

        /// <summary>POST /auth/reset-password — đặt lại mật khẩu bằng resetToken.</summary>
        Task ResetPasswordAsync(ResetPasswordRequest request);
    }
}
