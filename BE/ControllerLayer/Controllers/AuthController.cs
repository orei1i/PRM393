using ApplicationLayer.DTOs.Auth;
using ApplicationLayer.Interfaces;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>
    /// Authentication endpoints: login, register, forgot/verify/reset password.
    /// Route: /api/v1/auth
    /// </summary>
    [Route("api/v1/auth")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly IAuthService _authService;

        public AuthController(IAuthService authService)
        {
            _authService = authService;
        }

        /// <summary>Đăng nhập bằng email + mật khẩu. Trả về JWT + thông tin user.</summary>
        [HttpPost("login")]
        public async Task<ActionResult<ApiResponse<AuthResponse>>> Login([FromBody] LoginRequest request)
        {
            var result = await _authService.LoginAsync(request);
            return Ok(ApiResponse<AuthResponse>.Ok(result, "Đăng nhập thành công."));
        }

        /// <summary>Đăng ký tài khoản mới (role User). Trả về JWT + thông tin user.</summary>
        [HttpPost("register")]
        public async Task<ActionResult<ApiResponse<AuthResponse>>> Register([FromBody] RegisterRequest request)
        {
            var result = await _authService.RegisterAsync(request);
            return StatusCode(201, ApiResponse<AuthResponse>.Created(result, "Đăng ký thành công."));
        }

        /// <summary>Gửi mã đặt lại mật khẩu về email. Luôn trả 204 (không tiết lộ email tồn tại).</summary>
        [HttpPost("forgot-password")]
        public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
        {
            await _authService.ForgotPasswordAsync(request);
            return NoContent();
        }

        /// <summary>Xác minh mã đặt lại mật khẩu. Trả về resetToken nếu hợp lệ.</summary>
        [HttpPost("verify-reset-code")]
        public async Task<ActionResult<ApiResponse<VerifyResetCodeResponse>>> VerifyResetCode([FromBody] VerifyResetCodeRequest request)
        {
            var result = await _authService.VerifyResetCodeAsync(request);
            return Ok(ApiResponse<VerifyResetCodeResponse>.Ok(result));
        }

        /// <summary>Đặt lại mật khẩu bằng resetToken. Trả 204 nếu thành công.</summary>
        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
        {
            await _authService.ResetPasswordAsync(request);
            return NoContent();
        }
    }
}
