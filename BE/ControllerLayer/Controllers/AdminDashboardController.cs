using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/admin")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminDashboardController : ControllerBase
    {
        private readonly IAdminDashboardService _dashboard;
        private readonly IModerationService _moderation;
        private readonly IAdminAiService _ai;

        public AdminDashboardController(IAdminDashboardService dashboard, IModerationService moderation, IAdminAiService ai)
        {
            _dashboard = dashboard;
            _moderation = moderation;
            _ai = ai;
        }

        [HttpGet("overview")]
        public async Task<ActionResult<ApiResponse<OverviewResponse>>> Overview() =>
            Ok(ApiResponse<OverviewResponse>.Ok(await _dashboard.GetOverviewAsync()));

        /* ---------------------------------------------------------------- danh mục */

        [HttpGet("catalog")]
        public async Task<ActionResult<ApiResponse<List<CatalogItemResponse>>>> ListCatalog([FromQuery] string? kind) =>
            Ok(ApiResponse<List<CatalogItemResponse>>.Ok(await _dashboard.ListCatalogAsync(kind)));

        [HttpPost("catalog")]
        public async Task<ActionResult<ApiResponse<CatalogItemResponse>>> CreateCatalog([FromBody] CreateCatalogItemRequest request) =>
            Ok(ApiResponse<CatalogItemResponse>.Ok(await _dashboard.CreateCatalogItemAsync(User.GetUserId(), request)));

        [HttpPatch("catalog/{id}")]
        public async Task<ActionResult<ApiResponse<CatalogItemResponse>>> PatchCatalog(string id, [FromBody] PatchCatalogItemRequest request) =>
            Ok(ApiResponse<CatalogItemResponse>.Ok(await _dashboard.PatchCatalogItemAsync(User.GetUserId(), id, request)));

        [HttpDelete("catalog/{id}")]
        public async Task<ActionResult<ApiResponse<object>>> DeleteCatalog(string id)
        {
            await _dashboard.DeleteCatalogItemAsync(User.GetUserId(), id);
            return Ok(ApiResponse<object>.Ok(new { }, "Đã xoá mục."));
        }

        /* ---------------------------------------------------------------- cờ kiểm duyệt */

        [HttpGet("moderation/flags")]
        public async Task<ActionResult<ApiResponse<List<FlagResponse>>>> Flags([FromQuery] string? status, [FromQuery] string? category, [FromQuery] string? search) =>
            Ok(ApiResponse<List<FlagResponse>>.Ok(await _moderation.ListFlagsAsync(status, category, search)));

        [HttpGet("moderation/flags/counts")]
        public async Task<ActionResult<ApiResponse<Dictionary<string, long>>>> FlagCounts() =>
            Ok(ApiResponse<Dictionary<string, long>>.Ok(await _moderation.CountFlagsAsync()));

        [HttpPost("moderation/flags/{id}/decision")]
        public async Task<ActionResult<ApiResponse<object>>> Decide(string id, [FromBody] ModerationDecisionRequest request)
        {
            await _moderation.DecideAsync(User.GetUserId(), id, request);
            return Ok(ApiResponse<object>.Ok(new { }, "Đã lưu quyết định."));
        }

        /* ---------------------------------------------------------------- AI */

        [HttpGet("ai/telemetry/summary")]
        public async Task<ActionResult<ApiResponse<TelemetryResponse>>> Telemetry([FromQuery] string? range) =>
            Ok(ApiResponse<TelemetryResponse>.Ok(await _ai.GetTelemetryAsync(range)));

        [HttpGet("ai/logs")]
        public async Task<ActionResult<ApiResponse<List<AiLogResponse>>>> Logs([FromQuery] string? task, [FromQuery] int? limit) =>
            Ok(ApiResponse<List<AiLogResponse>>.Ok(await _ai.ListLogsAsync(task, limit)));

        [HttpGet("ai/logs/{id}")]
        public async Task<ActionResult<ApiResponse<AiLogResponse>>> Log(string id) =>
            Ok(ApiResponse<AiLogResponse>.Ok(await _ai.GetLogAsync(id)));

        [HttpPost("ai/logs/{id}/label")]
        public async Task<ActionResult<ApiResponse<AiLogResponse>>> Label(string id, [FromBody] LabelAiLogRequest request) =>
            Ok(ApiResponse<AiLogResponse>.Ok(await _ai.LabelLogAsync(User.GetUserId(), id, request)));

        [HttpGet("ai/models")]
        public async Task<ActionResult<ApiResponse<List<AiModelResponse>>>> Models() =>
            Ok(ApiResponse<List<AiModelResponse>>.Ok(await _ai.ListModelsAsync()));

        [HttpPatch("ai/models/{id}")]
        public async Task<ActionResult<ApiResponse<AiModelResponse>>> PatchModel(string id, [FromBody] PatchAiModelRequest request) =>
            Ok(ApiResponse<AiModelResponse>.Ok(await _ai.PatchModelAsync(User.GetUserId(), id, request)));

        [HttpGet("ai/metrics")]
        public async Task<ActionResult<ApiResponse<AiMetricsResponse>>> Metrics([FromQuery] string? range) =>
            Ok(ApiResponse<AiMetricsResponse>.Ok(await _ai.GetMetricsAsync(range)));
    }
}
