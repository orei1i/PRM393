using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>Bài viết và bình luận của chính người đang đăng nhập.</summary>
    [ApiController]
    [Route("api/v1/users/me")]
    [Authorize]
    public class MyContentController : ControllerBase
    {
        private readonly IPostService _postService;
        private readonly ICommentService _commentService;

        public MyContentController(IPostService postService, ICommentService commentService)
        {
            _postService = postService;
            _commentService = commentService;
        }

        /// <summary>Bài của tôi, mọi trạng thái, có rejectionReason. Phân trang bằng cursor như bảng tin.</summary>
        [HttpGet("posts")]
        public async Task<ActionResult<ApiResponse<FeedPageResponse>>> MyPosts(
            [FromQuery] string? status = null,
            [FromQuery] string? cursor = null,
            [FromQuery] int? limit = null)
        {
            var result = await _postService.GetMyPostsAsync(User.GetUserId(), status, cursor, limit);
            return Ok(ApiResponse<FeedPageResponse>.Ok(result));
        }

        /// <summary>Bài đã lưu, mới lưu trước. Bài đã xoá hoặc đang ẩn không hiện.</summary>
        [HttpGet("saved-posts")]
        public async Task<ActionResult<ApiResponse<IEnumerable<PostResponse>>>> SavedPosts()
        {
            var result = await _postService.GetSavedPostsAsync(User.GetUserId());
            return Ok(ApiResponse<IEnumerable<PostResponse>>.Ok(result));
        }

        /// <summary>Bình luận và phản hồi của tôi, mới nhất trước.</summary>
        [HttpGet("comments")]
        public async Task<ActionResult<ApiResponse<IEnumerable<MyCommentResponse>>>> MyComments()
        {
            var result = await _commentService.GetMyCommentsAsync(User.GetUserId());
            return Ok(ApiResponse<IEnumerable<MyCommentResponse>>.Ok(result));
        }
    }
}
