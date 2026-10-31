using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/admin/posts")]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminPostsController : ControllerBase
    {
        private readonly IPostService _postService;

        public AdminPostsController(IPostService postService)
        {
            _postService = postService;
        }

        /// <summary>Lấy danh sách bài viết dành cho Admin kiểm duyệt (lọc theo status: Pending, Published, Rejected).</summary>
        [HttpGet]
        [ProducesResponseType(typeof(ApiResponse<FeedPageResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<FeedPageResponse>>> GetAdminPosts(
            [FromQuery] string? status,
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 10)
        {
            var result = await _postService.GetAdminPostsAsync(status, page, pageSize);
            return Ok(ApiResponse<FeedPageResponse>.Ok(result));
        }

        /// <summary>Kiểm duyệt bài viết (Web Admin endpoint: decision: "Approve" | "Reject").</summary>
        [HttpPost("{id}/review")]
        [ProducesResponseType(typeof(ApiResponse<PostResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<PostResponse>>> ReviewPost(string id, [FromBody] AdminReviewPostRequest request)
        {
            var result = await _postService.ModeratePostAsync(id, request.Decision, request.Reason);
            return Ok(ApiResponse<PostResponse>.Ok(result, "Kiểm duyệt bài viết thành công."));
        }

        /// <summary>Thực hiện hành động kiểm duyệt (Web Admin endpoint: action: "unhide" | "restore" | "hide" | "delete").</summary>
        [HttpPost("{id}/actions")]
        [ProducesResponseType(typeof(ApiResponse<PostResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<PostResponse>>> ActionPost(string id, [FromBody] AdminActionPostRequest request)
        {
            var result = await _postService.ModeratePostAsync(id, request.Action, request.Reason);
            return Ok(ApiResponse<PostResponse>.Ok(result, "Xử lý hành động bài viết thành công."));
        }

        /// <summary>Cập nhật trạng thái bài viết bởi Admin.</summary>
        [HttpPatch("{id}/status")]
        [ProducesResponseType(typeof(ApiResponse<PostResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<PostResponse>>> UpdatePostStatus(string id, [FromBody] AdminStatusPostRequest request)
        {
            var result = await _postService.ModeratePostAsync(id, request.Status);
            return Ok(ApiResponse<PostResponse>.Ok(result, "Cập nhật trạng thái bài viết thành công."));
        }
    }
}

