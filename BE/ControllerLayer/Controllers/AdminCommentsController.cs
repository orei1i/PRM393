using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/admin/comments")]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminCommentsController : ControllerBase
    {
        private readonly ICommentService _commentService;

        public AdminCommentsController(ICommentService commentService)
        {
            _commentService = commentService;
        }

        /// <summary>Danh sách bình luận cho kiểm duyệt: view=all|reported|hidden, tối đa 200 dòng mới nhất.</summary>
        [HttpGet]
        public async Task<ActionResult<ApiResponse<IEnumerable<AdminCommentResponse>>>> List(
            [FromQuery] string? view = null,
            [FromQuery] string? search = null,
            [FromQuery] string? authorId = null,
            [FromQuery] string? postId = null)
        {
            var result = await _commentService.GetAdminCommentsAsync(view, search, authorId, postId);
            return Ok(ApiResponse<IEnumerable<AdminCommentResponse>>.Ok(result));
        }

        /// <summary>Xoá bình luận, lý do được lưu để báo cho tác giả.</summary>
        [HttpDelete("{id}")]
        public async Task<ActionResult<ApiResponse<object>>> Delete(
            string id,
            [FromBody(EmptyBodyBehavior = EmptyBodyBehavior.Allow)] AdminDeleteCommentRequest? request)
        {
            var deleted = await _commentService.AdminDeleteCommentAsync(id, request?.Reason);
            if (!deleted)
            {
                return NotFound(ApiResponse<object>.NotFound("Không tìm thấy bình luận."));
            }
            return Ok(ApiResponse<object?>.Ok(null, "Đã xoá bình luận."));
        }

        /// <summary>Ẩn hoặc bỏ ẩn bình luận.</summary>
        [HttpPost("{id}/actions")]
        public async Task<ActionResult<ApiResponse<AdminCommentResponse>>> Act(string id, [FromBody] AdminCommentActionRequest request)
        {
            var result = await _commentService.AdminActOnCommentAsync(id, request.Action);
            return Ok(ApiResponse<AdminCommentResponse>.Ok(result, "Đã cập nhật bình luận."));
        }
    }
}
