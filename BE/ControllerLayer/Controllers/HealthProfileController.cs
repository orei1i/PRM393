using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.HealthProfile;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/health-profile")]
    [ApiController]
    public class HealthProfileController : ControllerBase
    {
        private readonly IHealthProfileService _healthProfileService;

        public HealthProfileController(IHealthProfileService healthProfileService)
        {
            _healthProfileService = healthProfileService;
        }

        /// <summary>Lấy thông tin hồ sơ sức khỏe và năng lượng cá nhân.</summary>
        [HttpGet("me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<HealthProfileResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<HealthProfileResponse>>> GetMyProfile()
        {
            var userId = User.GetUserId();
            var profile = await _healthProfileService.GetMyHealthProfileAsync(userId);
            return Ok(ApiResponse<HealthProfileResponse>.Ok(profile));
        }

        /// <summary>Tạo mới hoặc cập nhật hồ sơ sức khỏe (tính toán lại BMI, BMR, TDEE, Calo mục tiêu).</summary>
        [HttpPut("me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<HealthProfileResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        public async Task<ActionResult<ApiResponse<HealthProfileResponse>>> UpdateMyProfile([FromBody] UpdateHealthProfileRequest request)
        {
            var userId = User.GetUserId();
            var updated = await _healthProfileService.UpdateMyHealthProfileAsync(userId, request);
            return Ok(ApiResponse<HealthProfileResponse>.Ok(updated, "Cập nhật hồ sơ sức khỏe thành công."));
        }

        /// <summary>Lấy lịch sử biến thiên cân nặng theo thời gian để vẽ biểu đồ.</summary>
        [HttpGet("me/metrics")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<HealthMetricLogResponse>>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        public async Task<ActionResult<ApiResponse<IEnumerable<HealthMetricLogResponse>>>> GetMetrics([FromQuery] int limit = 30)
        {
            var userId = User.GetUserId();
            var history = await _healthProfileService.GetMetricsHistoryAsync(userId, limit);
            return Ok(ApiResponse<IEnumerable<HealthMetricLogResponse>>.Ok(history));
        }
    }
}

