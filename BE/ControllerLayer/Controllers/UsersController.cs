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

        /// <summary>Lấy danh sách tất cả users. (Chỉ Admin)</summary>
        [HttpGet]
        [Authorize(Roles = AppRoles.Admin)]
        public async Task<ActionResult<ApiResponse<IEnumerable<UserResponse>>>> GetUsers()
        {
            var users = await _userService.GetAllUsersAsync();
            return Ok(ApiResponse<IEnumerable<UserResponse>>.Ok(users));
        }

        /// <summary>Lấy thông tin hồ sơ của chính người dùng đang đăng nhập.</summary>
        /// <response code="200">Lấy thông tin thành công.</response>
        /// <response code="401">Chưa đăng nhập hoặc token không hợp lệ.</response>
        /// <response code="404">Không tìm thấy tài khoản người dùng.</response>
        /// <response code="423">Tài khoản đã bị tạm khóa hoặc cấm.</response>
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

        /// <summary>Lấy thông tin user theo Id.</summary>
        [HttpGet("{id}")]
        [Authorize(Roles = AppRoles.AdminOrMember)]
        public async Task<ActionResult<ApiResponse<UserResponse>>> GetUserById(string id)
        {
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
            var updated = await _userService.UpdateUserAsync(id, request);
            return Ok(ApiResponse<UserResponse>.Ok(updated, "Cập nhật thành công."));
        }

        /// <summary>Xóa mềm user. (Chỉ Admin)</summary>
        [HttpDelete("{id}")]
        [Authorize(Roles = AppRoles.Admin)]
        public async Task<ActionResult<ApiResponse<object>>> DeleteUser(string id)
        {
            var result = await _userService.DeleteUserAsync(id);
            if (!result)
                return NotFound(ApiResponse<object>.NotFound($"Không tìm thấy user với id: {id}"));

            return Ok(ApiResponse<object?>.Ok(null, "Xóa user thành công."));
        }

        private string GetCurrentUserId()
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)
                         ?? User.FindFirstValue(JwtRegisteredClaimNames.Sub)
                         ?? User.FindFirst("sub")?.Value;

            if (string.IsNullOrWhiteSpace(userId))
                throw new UnauthorizedException("Phiên đăng nhập không hợp lệ hoặc thiếu thông tin định danh.");

            return userId;
        }
    }
}