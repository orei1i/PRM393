using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using ApplicationLayer.DTOs.Users;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Models;
using DomainLayer.Exceptions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/[controller]")]
    [ApiController]
    public class UsersController : ControllerBase
    {
        private readonly IUserService _userService;

        public UsersController(IUserService userService)
        {
            _userService = userService;
        }

        /// <summary>Láº¥y danh sÃ¡ch táº¥t cáº£ users. (Chá»‰ Admin)</summary>
        [HttpGet]
        [Authorize(Roles = AppRoles.Admin)]
        public async Task<ActionResult<ApiResponse<IEnumerable<UserResponse>>>> GetUsers()
        {
            var users = await _userService.GetAllUsersAsync();
            return Ok(ApiResponse<IEnumerable<UserResponse>>.Ok(users));
        }

        /// <summary>Láº¥y thÃ´ng tin há»“ sÆ¡ cá»§a chÃ­nh ngÆ°á»i dÃ¹ng Ä‘ang Ä‘Äƒng nháº­p.</summary>
        /// <response code="200">Láº¥y thÃ´ng tin thÃ nh cÃ´ng.</response>
        /// <response code="401">ChÆ°a Ä‘Äƒng nháº­p hoáº·c token khÃ´ng há»£p lá»‡.</response>
        /// <response code="404">KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n ngÆ°á»i dÃ¹ng.</response>
        /// <response code="423">TÃ i khoáº£n Ä‘Ã£ bá»‹ táº¡m khÃ³a hoáº·c cáº¥m.</response>
        [HttpGet("me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<UserProfileResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status423Locked)]
        public async Task<ActionResult<ApiResponse<UserProfileResponse>>> GetMe()
        {
            var userId = GetCurrentUserId();
            var profile = await _userService.GetCurrentUserProfileAsync(userId);
            return Ok(ApiResponse<UserProfileResponse>.Ok(profile));
        }

        /// <summary>Láº¥y thÃ´ng tin user theo Id.</summary>
        [HttpGet("{id}")]
        [Authorize(Roles = AppRoles.AdminOrMember)]
        public async Task<ActionResult<ApiResponse<UserResponse>>> GetUserById(string id)
        {
            var currentUserId = GetCurrentUserId();
            var isAdmin = User.IsInRole(AppRoles.Admin);
            if (!isAdmin && currentUserId != id)
            {
                throw new ForbiddenException("Bạn không có quyền truy cập thông tin của người dùng khác.");
            }

            var user = await _userService.GetUserByIdAsync(id);
            if (user == null)
                return NotFound(ApiResponse<UserResponse>.NotFound($"Không tìm thấy user với id: {id}"));

            return Ok(ApiResponse<UserResponse>.Ok(user));
        }

        /// <summary>Cập nhật thông tin cá nhân.</summary>
        [HttpPut("{id}")]
        [Authorize(Roles = AppRoles.AdminOrMember)]
        public async Task<ActionResult<ApiResponse<UserResponse>>> UpdateUser(string id, [FromBody] UpdateUserRequest request)
        {
            var currentUserId = GetCurrentUserId();
            var isAdmin = User.IsInRole(AppRoles.Admin);
            if (!isAdmin && currentUserId != id)
            {
                throw new ForbiddenException("Bạn không có quyền cập nhật thông tin của người dùng khác.");
            }

            var updated = await _userService.UpdateUserAsync(id, request);
            return Ok(ApiResponse<UserResponse>.Ok(updated, "Cập nhật thành công."));
        }

        /// <summary>XÃ³a má»m user. (Chá»‰ Admin)</summary>
        [HttpDelete("{id}")]
        [Authorize(Roles = AppRoles.Admin)]
        public async Task<ActionResult<ApiResponse<object>>> DeleteUser(string id)
        {
            var result = await _userService.DeleteUserAsync(id);
            if (!result)
                return NotFound(ApiResponse<object>.NotFound($"KhÃ´ng tÃ¬m tháº¥y user vá»›i id: {id}"));

            return Ok(ApiResponse<object?>.Ok(null, "XÃ³a user thÃ nh cÃ´ng."));
        }

        private string GetCurrentUserId()
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)
                         ?? User.FindFirstValue(JwtRegisteredClaimNames.Sub)
                         ?? User.FindFirst("sub")?.Value;

            if (string.IsNullOrWhiteSpace(userId))
                throw new UnauthorizedException("PhiÃªn Ä‘Äƒng nháº­p khÃ´ng há»£p lá»‡ hoáº·c thiáº¿u thÃ´ng tin Ä‘á»‹nh danh.");

            return userId;
        }
    }
}