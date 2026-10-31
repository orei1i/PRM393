using System.Threading.Tasks;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/comments")]
    [ApiController]
    public class CommentsController : ControllerBase
    {
        private readonly ICommentService _commentService;

        public CommentsController(ICommentService commentService)
        {
            _commentService = commentService;
        }

        /// <summary>Xóa bình luận (Chỉ chủ bình luận hoặc Quản trị viên).</summary>
        [HttpDelete("{id}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status403Forbidden)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<object>>> DeleteComment(string id)
        {
            var currentUserId = User.GetUserId();
            var role = User.GetRole();
            var success = await _commentService.DeleteCommentAsync(id, currentUserId, role);
            if (!success)
            {
                return NotFound(ApiResponse<object>.NotFound($"Không tìm thấy bình luận với id: {id}"));
            }

            return Ok(ApiResponse<object?>.Ok(null, "Xóa bình luận thành công."));
        }

        /// <summary>Lấy danh sách các phản hồi của bình luận.</summary>
        [HttpGet("{id}/replies")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<System.Collections.Generic.IEnumerable<ApplicationLayer.DTOs.Posts.CommentResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<System.Collections.Generic.IEnumerable<ApplicationLayer.DTOs.Posts.CommentResponse>>>> GetReplies(string id)
        {
            var result = await _commentService.GetCommentRepliesAsync(id);
            return Ok(ApiResponse<System.Collections.Generic.IEnumerable<ApplicationLayer.DTOs.Posts.CommentResponse>>.Ok(result));
        }
    }
}
