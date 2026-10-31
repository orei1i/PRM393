using System.Security.Claims;
using ApplicationLayer.DTOs.Auth;
using ApplicationLayer.Interfaces;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
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

        /// <summary>Ã„ÂÃ„Æ’ng nhÃ¡ÂºÂ­p bÃ¡ÂºÂ±ng email + mÃ¡ÂºÂ­t khÃ¡ÂºÂ©u. TrÃ¡ÂºÂ£ vÃ¡Â»Â JWT + thÃƒÂ´ng tin user.</summary>
        [HttpPost("login")]
        public async Task<ActionResult<ApiResponse<AuthResponse>>> Login([FromBody] LoginRequest request)
        {
            var result = await _authService.LoginAsync(request);
            return Ok(ApiResponse<AuthResponse>.Ok(result, "Đăng nhập thành công."));
        }

        /// <summary>ÄÄƒng nháº­p dÃ nh riÃªng cho Quáº£n trá»‹ viÃªn Web Admin.</summary>
        [HttpPost("admin/login")]
        public async Task<ActionResult<ApiResponse<AuthResponse>>> AdminLogin([FromBody] LoginRequest request)
        {
            var result = await _authService.AdminLoginAsync(request);
            return Ok(ApiResponse<AuthResponse>.Ok(result, "Đăng nhập admin thành công."));
        }

        /// <summary>LÃ m má»›i Access Token báº±ng Refresh Token (xoay vÃ²ng token).</summary>
        [HttpPost("refresh")]
        public async Task<ActionResult<ApiResponse<AuthResponse>>> Refresh([FromBody] RefreshTokenRequest request)
        {
            var result = await _authService.RefreshTokenAsync(request);
            return Ok(ApiResponse<AuthResponse>.Ok(result, "Làm mới token thành công."));
        }

        /// <summary>ÄÄƒng xuáº¥t vÃ  thu há»“i Refresh Token hiá»‡n táº¡i.</summary>
        [HttpPost("logout")]
        [Authorize]
        public async Task<IActionResult> Logout()
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                         ?? User.FindFirst("sub")?.Value;
            if (!string.IsNullOrEmpty(userId))
            {
                await _authService.LogoutAsync(userId);
            }
            return NoContent();
        }

        /// <summary>Ã„ÂÃ„Æ’ng kÃƒÂ½ tÃƒÂ i khoÃ¡ÂºÂ£n mÃ¡Â»â€ºi (role User). TrÃ¡ÂºÂ£ vÃ¡Â»Â JWT + thÃƒÂ´ng tin user.</summary>
        [HttpPost("register")]
        public async Task<ActionResult<ApiResponse<AuthResponse>>> Register([FromBody] RegisterRequest request)
        {
            var result = await _authService.RegisterAsync(request);
            return StatusCode(201, ApiResponse<AuthResponse>.Created(result, "Ã„ÂÃ„Æ’ng kÃƒÂ½ thÃƒÂ nh cÃƒÂ´ng."));
        }

        /// <summary>GÃ¡Â»Â­i mÃƒÂ£ Ã„â€˜Ã¡ÂºÂ·t lÃ¡ÂºÂ¡i mÃ¡ÂºÂ­t khÃ¡ÂºÂ©u vÃ¡Â»Â email. LuÃƒÂ´n trÃ¡ÂºÂ£ 204 (khÃƒÂ´ng tiÃ¡ÂºÂ¿t lÃ¡Â»â„¢ email tÃ¡Â»â€œn tÃ¡ÂºÂ¡i).</summary>
        [HttpPost("forgot-password")]
        public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
        {
            await _authService.ForgotPasswordAsync(request);
            return NoContent();
        }

        /// <summary>XÃƒÂ¡c minh mÃƒÂ£ Ã„â€˜Ã¡ÂºÂ·t lÃ¡ÂºÂ¡i mÃ¡ÂºÂ­t khÃ¡ÂºÂ©u. TrÃ¡ÂºÂ£ vÃ¡Â»Â resetToken nÃ¡ÂºÂ¿u hÃ¡Â»Â£p lÃ¡Â»â€¡.</summary>
        [HttpPost("verify-reset-code")]
        public async Task<ActionResult<ApiResponse<VerifyResetCodeResponse>>> VerifyResetCode([FromBody] VerifyResetCodeRequest request)
        {
            var result = await _authService.VerifyResetCodeAsync(request);
            return Ok(ApiResponse<VerifyResetCodeResponse>.Ok(result));
        }

        /// <summary>Ã„ÂÃ¡ÂºÂ·t lÃ¡ÂºÂ¡i mÃ¡ÂºÂ­t khÃ¡ÂºÂ©u bÃ¡ÂºÂ±ng resetToken. TrÃ¡ÂºÂ£ 204 nÃ¡ÂºÂ¿u thÃƒÂ nh cÃƒÂ´ng.</summary>
        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
        {
            await _authService.ResetPasswordAsync(request);
            return NoContent();
        }
    }
}
