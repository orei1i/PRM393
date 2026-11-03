using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/ads")]
    [ApiController]
    [AllowAnonymous]
    public class AdsController : ControllerBase
    {
        private readonly IAdService _ads;

        public AdsController(IAdService ads)
        {
            _ads = ads;
        }

        [HttpGet("feed")]
        public async Task<ActionResult<ApiResponse<List<AdFeedItemResponse>>>> Feed(
            [FromQuery] string? placement, [FromQuery] string? city, [FromQuery] double? lat, [FromQuery] double? lng, [FromQuery] int? limit) =>
            Ok(ApiResponse<List<AdFeedItemResponse>>.Ok(await _ads.FeedAsync(placement, city, lat, lng, limit)));

        /// <summary>Hai route đếm này công khai và làm tăng số đã tiêu, nên có giới hạn theo IP.</summary>
        [HttpPost("{id}/impression")]
        [EnableRateLimiting("ads")]
        public async Task<IActionResult> Impression(string id)
        {
            await _ads.RecordImpressionAsync(id);
            return NoContent();
        }

        [HttpPost("{id}/click")]
        [EnableRateLimiting("ads")]
        public async Task<IActionResult> Click(string id)
        {
            await _ads.RecordClickAsync(id);
            return NoContent();
        }
    }

    [Route("api/v1/admin/ads")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminAdsController : ControllerBase
    {
        private readonly IAdService _ads;

        public AdminAdsController(IAdService ads)
        {
            _ads = ads;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<AdCampaignResponse>>>> List([FromQuery] string? status, [FromQuery] string? city, [FromQuery] string? search) =>
            Ok(ApiResponse<List<AdCampaignResponse>>.Ok(await _ads.AdminListAsync(status, city, search)));

        [HttpPost]
        public async Task<ActionResult<ApiResponse<AdCampaignResponse>>> Create([FromBody] AdInputRequest request) =>
            Ok(ApiResponse<AdCampaignResponse>.Ok(await _ads.CreateAsync(User.GetUserId(), request)));

        [HttpPatch("{id}")]
        public async Task<ActionResult<ApiResponse<AdCampaignResponse>>> Update(string id, [FromBody] AdInputRequest request) =>
            Ok(ApiResponse<AdCampaignResponse>.Ok(await _ads.UpdateAsync(User.GetUserId(), id, request)));

        [HttpPost("{id}/pause")]
        public async Task<ActionResult<ApiResponse<AdCampaignResponse>>> Pause(string id) =>
            Ok(ApiResponse<AdCampaignResponse>.Ok(await _ads.SetPausedAsync(User.GetUserId(), id, true)));

        [HttpPost("{id}/resume")]
        public async Task<ActionResult<ApiResponse<AdCampaignResponse>>> Resume(string id) =>
            Ok(ApiResponse<AdCampaignResponse>.Ok(await _ads.SetPausedAsync(User.GetUserId(), id, false)));

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            await _ads.DeleteAsync(User.GetUserId(), id);
            return NoContent();
        }
    }

    [Route("api/v1/videos")]
    [ApiController]
    public class VideosController : ControllerBase
    {
        private readonly IVideoService _videos;

        public VideosController(IVideoService videos)
        {
            _videos = videos;
        }

        [HttpGet("{id}")]
        [AllowAnonymous]
        public async Task<ActionResult<ApiResponse<VideoResponse>>> Get(string id) =>
            Ok(ApiResponse<VideoResponse>.Ok(await _videos.GetAsync(id, User.GetUserIdOrDefault(), User.IsInRole(AppRoles.Admin))));

        [HttpPost("{id}/extraction")]
        [Authorize]
        public async Task<ActionResult<ApiResponse<VideoResponse>>> Retry(string id) =>
            Ok(ApiResponse<VideoResponse>.Ok(await _videos.RetryExtractionAsync(id, User.GetUserId(), User.IsInRole(AppRoles.Admin))));
    }
}
