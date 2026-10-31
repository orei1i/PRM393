using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/posts")]
    [ApiController]
    public class PostsController : ControllerBase
    {
        private readonly IPostService _postService;
        private readonly ICommentService _commentService;

        public PostsController(IPostService postService, ICommentService commentService)
        {
            _postService = postService;
            _commentService = commentService;
        }

        /// <summary>Lấy danh sách bảng tin cộng đồng (phân trang, chỉ hiện bài Published).</summary>
        [HttpGet]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<FeedPageResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<FeedPageResponse>>> GetFeed(
            [FromQuery] string? cursor = null,
            [FromQuery] int? limit = null,
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 10,
            [FromQuery] string? type = null,
            [FromQuery] string? mediaType = null)
        {
            var currentUserId = User.GetUserIdOrDefault();
            var result = await _postService.GetFeedAsync(page, pageSize, type, mediaType, currentUserId, cursor, limit);
            return Ok(ApiResponse<FeedPageResponse>.Ok(result));
        }

        /// <summary>Lấy chi tiết một bài viết theo ID.</summary>
        [HttpGet("{id}")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<PostResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<PostResponse>>> GetPostById(string id)
        {
            var currentUserId = User.GetUserIdOrDefault();
            var result = await _postService.GetPostByIdAsync(id, currentUserId);
            return Ok(ApiResponse<PostResponse>.Ok(result));
        }

        /// <summary>Tạo bài viết mới (kèm ảnh hoặc video).</summary>
        [HttpPost]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<PostResponse>), StatusCodes.Status201Created)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        public async Task<ActionResult<ApiResponse<PostResponse>>> CreatePost([FromBody] CreatePostRequest request)
        {
            var currentUserId = User.GetUserId();
            var result = await _postService.CreatePostAsync(request, currentUserId);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<PostResponse>.Created(result, "Đăng bài viết thành công."));
        }

        /// <summary>Xóa bài viết (Chỉ chủ bài viết hoặc Quản trị viên).</summary>
        [HttpDelete("{id}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status403Forbidden)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<object>>> DeletePost(string id)
        {
            var currentUserId = User.GetUserId();
            var role = User.GetRole();
            var success = await _postService.DeletePostAsync(id, currentUserId, role);
            if (!success)
            {
                return NotFound(ApiResponse<object>.NotFound($"Không tìm thấy bài viết với id: {id}"));
            }

            return Ok(ApiResponse<object?>.Ok(null, "Xóa bài viết thành công."));
        }

        /// <summary>Thích hoặc bỏ thích bài viết (Toggle Like).</summary>
        [HttpPost("{id}/like")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<LikeResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<LikeResponse>>> ToggleLike(string id)
        {
            var currentUserId = User.GetUserId();
            var result = await _postService.ToggleLikeAsync(id, currentUserId);
            return Ok(ApiResponse<LikeResponse>.Ok(result, result.Liked ? "Đã thích bài viết." : "Đã bỏ thích bài viết."));
        }

        /// <summary>Báo cáo bài viết vi phạm (Đủ 3 báo cáo bài viết tự động ẩn khỏi feed).</summary>
        [HttpPost("{id}/reports")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
        public async Task<ActionResult<ApiResponse<object>>> ReportPost(string id, [FromBody] ReportPostRequest request)
        {
            var currentUserId = User.GetUserId();
            await _postService.ReportPostAsync(id, currentUserId, request);
            return Ok(ApiResponse<object?>.Ok(null, "Báo cáo bài viết thành công. Cảm ơn bạn đã hỗ trợ cộng đồng."));
        }

        /// <summary>Lấy danh sách bình luận của bài viết (phân trang, mới nhất trước, kèm 2 phản hồi đầu tiên).</summary>
        [HttpGet("{id}/comments")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<CommentResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<CommentResponse>>>> GetComments(
            string id,
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 10)
        {
            var result = await _commentService.GetPostCommentsAsync(id, page, pageSize);
            return Ok(ApiResponse<IEnumerable<CommentResponse>>.Ok(result));
        }

        /// <summary>Thêm bình luận mới hoặc phản hồi cho bài viết.</summary>
        [HttpPost("{id}/comments")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<CommentResponse>), StatusCodes.Status201Created)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<CommentResponse>>> CreateComment(string id, [FromBody] CreateCommentRequest request)
        {
            var currentUserId = User.GetUserId();
            var result = await _commentService.CreateCommentAsync(id, request, currentUserId);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<CommentResponse>.Created(result, "Gửi bình luận thành công."));
        }

        /// <summary>Lấy danh sách phản hồi của một bình luận trong bài viết.</summary>
        [HttpGet("{id}/comments/{commentId}/replies")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<CommentResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<CommentResponse>>>> GetCommentReplies(string id, string commentId)
        {
            var result = await _commentService.GetCommentRepliesAsync(commentId);
            return Ok(ApiResponse<IEnumerable<CommentResponse>>.Ok(result));
        }
    }
}
