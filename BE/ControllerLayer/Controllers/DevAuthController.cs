using ApplicationLayer.Interfaces;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>
    /// Lối riêng cho khi phát triển, vì chưa có email thật: đọc mã đặt lại mật khẩu vừa tạo.
    /// Chỉ hoạt động khi chạy Development và bật Auth:DevResetCodes; ngoài ra luôn 404 như route không tồn tại.
    /// </summary>
    [ApiController]
    [Route("api/v1/dev/auth")]
    [AllowAnonymous]
    [ApiExplorerSettings(IgnoreApi = true)]
    public class DevAuthController : ControllerBase
    {
        private readonly IPasswordResetNotifier _notifier;

        public DevAuthController(IPasswordResetNotifier notifier)
        {
            _notifier = notifier;
        }

        [HttpGet("reset-code")]
        public ActionResult<ApiResponse<object>> ResetCode([FromQuery] string? email)
        {
            if (_notifier is not DevResetCodeOutbox outbox || string.IsNullOrWhiteSpace(email))
            {
                return NotFound(ApiResponse<object>.NotFound("Đường dẫn hoặc tài nguyên không tồn tại."));
            }

            var code = outbox.Peek(email.Trim().ToLowerInvariant());
            if (code == null)
            {
                return NotFound(ApiResponse<object>.NotFound("Đường dẫn hoặc tài nguyên không tồn tại."));
            }

            return Ok(ApiResponse<object>.Ok(new { code }));
        }
    }
}
