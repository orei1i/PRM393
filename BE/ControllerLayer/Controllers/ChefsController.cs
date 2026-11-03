using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>Danh bạ chuyên gia, khách cũng đọc được.</summary>
    [Route("api/v1/chefs")]
    [ApiController]
    [AllowAnonymous]
    public class ChefsController : ControllerBase
    {
        private readonly IChefService _chefs;

        public ChefsController(IChefService chefs)
        {
            _chefs = chefs;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<ChefResponse>>>> List([FromQuery] string? q, [FromQuery] string? specialty) =>
            Ok(ApiResponse<List<ChefResponse>>.Ok(await _chefs.ListAsync(q, specialty)));

        [HttpGet("{id}")]
        public async Task<ActionResult<ApiResponse<ChefResponse>>> Get(string id) =>
            Ok(ApiResponse<ChefResponse>.Ok(await _chefs.GetAsync(id)));
    }

    /// <summary>Hồ sơ của chính chuyên gia. Sai vai trò trả 403 not_chef như các route /chefs/me khác.</summary>
    [Route("api/v1/chefs/me/profile")]
    [ApiController]
    [Authorize]
    public class ChefProfileController : ControllerBase
    {
        private readonly IChefService _chefs;

        public ChefProfileController(IChefService chefs)
        {
            _chefs = chefs;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<ChefProfileResponse>>> Get() =>
            Ok(ApiResponse<ChefProfileResponse>.Ok(await _chefs.GetMyProfileAsync(ChefGuard.RequireChef(User))));

        [HttpPut]
        public async Task<ActionResult<ApiResponse<ChefProfileResponse>>> Save([FromBody] SaveChefProfileRequest request) =>
            Ok(ApiResponse<ChefProfileResponse>.Ok(await _chefs.SaveMyProfileAsync(ChefGuard.RequireChef(User), request)));
    }

    [Route("api/v1/chef-applications")]
    [ApiController]
    [Authorize]
    public class ChefApplicationsController : ControllerBase
    {
        private readonly IChefService _chefs;

        public ChefApplicationsController(IChefService chefs)
        {
            _chefs = chefs;
        }

        [HttpPost]
        public async Task<ActionResult<ApiResponse<ChefApplicationResponse>>> Submit([FromBody] SubmitChefApplicationRequest request)
        {
            var application = await _chefs.SubmitApplicationAsync(User.GetUserId(), request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<ChefApplicationResponse>.Created(application));
        }

        [HttpGet("me")]
        public async Task<ActionResult<ApiResponse<ChefApplicationStatusResponse>>> Mine() =>
            Ok(ApiResponse<ChefApplicationStatusResponse>.Ok(await _chefs.GetMyApplicationAsync(User.GetUserId())));
    }

    [Route("api/v1/admin/chef-applications")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminChefApplicationsController : ControllerBase
    {
        private readonly IChefService _chefs;

        public AdminChefApplicationsController(IChefService chefs)
        {
            _chefs = chefs;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<ChefApplicationResponse>>>> List([FromQuery] string? status) =>
            Ok(ApiResponse<List<ChefApplicationResponse>>.Ok(await _chefs.ListApplicationsAsync(status)));

        [HttpGet("counts")]
        public async Task<ActionResult<ApiResponse<Dictionary<string, long>>>> Counts() =>
            Ok(ApiResponse<Dictionary<string, long>>.Ok(await _chefs.CountApplicationsAsync()));

        [HttpPost("{id}/review")]
        public async Task<ActionResult<ApiResponse<ChefApplicationResponse>>> Review(string id, [FromBody] ReviewChefApplicationRequest request) =>
            Ok(ApiResponse<ChefApplicationResponse>.Ok(await _chefs.ReviewApplicationAsync(User.GetUserId(), id, request)));
    }
}
