using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    /// <summary>
    /// /recipes là danh mục công khai; /users/me/recipes là "Công thức của tôi".
    /// Công thức do thành viên tạo là riêng tư: người khác và khách nhận 404.
    /// </summary>
    [ApiController]
    public class RecipesController : ControllerBase
    {
        private readonly IMealPlanService _mealPlanService;
        private readonly IRecipeService _recipeService;

        public RecipesController(IMealPlanService mealPlanService, IRecipeService recipeService)
        {
            _mealPlanService = mealPlanService;
            _recipeService = recipeService;
        }

        /// <summary>Danh mục công thức của hệ thống, ai cũng đọc được. Trả { items, nextCursor }.</summary>
        [HttpGet("api/v1/recipes")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<RecipeCatalogPageResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<RecipeCatalogPageResponse>>> GetCatalog(
            [FromQuery] string? q = null,
            [FromQuery] bool veganOnly = true,
            [FromQuery] int? limit = null,
            [FromQuery] string? cursor = null)
        {
            var result = await _recipeService.GetCatalogAsync(q, veganOnly, limit, cursor);
            return Ok(ApiResponse<RecipeCatalogPageResponse>.Ok(result));
        }

        /// <summary>Công thức do chính người dùng tự tạo ("Công thức của tôi").</summary>
        [HttpGet("api/v1/users/me/recipes")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<RecipeResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<RecipeResponse>>>> GetMyRecipes()
        {
            var results = await _mealPlanService.GetMyRecipesAsync(User.GetUserId());
            return Ok(ApiResponse<IEnumerable<RecipeResponse>>.Ok(results));
        }

        /// <summary>Chi tiết công thức. Khách đọc được công thức của hệ thống.</summary>
        [HttpGet("api/v1/recipes/{id}")]
        [HttpGet("api/v1/users/me/recipes/{id}")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<RecipeResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<RecipeResponse>>> GetById(string id)
        {
            var result = await _recipeService.GetByIdAsync(User.GetUserIdOrDefault(), id);
            return Ok(ApiResponse<RecipeResponse>.Ok(result));
        }

        /// <summary>Tạo mới một công thức của riêng tôi.</summary>
        [HttpPost("api/v1/recipes")]
        [HttpPost("api/v1/users/me/recipes")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<RecipeResponse>), StatusCodes.Status201Created)]
        public async Task<ActionResult<ApiResponse<RecipeResponse>>> CreateMyRecipe([FromBody] CreateRecipeRequest request)
        {
            var created = await _mealPlanService.CreateMyRecipeAsync(User.GetUserId(), request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<RecipeResponse>.Created(created, "Tạo công thức thành công."));
        }

        /// <summary>Sửa công thức của tôi. Công thức của người khác và của hệ thống: 404.</summary>
        [HttpPut("api/v1/recipes/{id}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<RecipeResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<RecipeResponse>>> UpdateMine(string id, [FromBody] CreateRecipeRequest request)
        {
            var updated = await _recipeService.UpdateMineAsync(User.GetUserId(), id, request);
            return Ok(ApiResponse<RecipeResponse>.Ok(updated, "Đã cập nhật công thức."));
        }

        /// <summary>Xoá mềm công thức của tôi. Công thức của người khác và của hệ thống: 404.</summary>
        [HttpDelete("api/v1/recipes/{id}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<object>>> DeleteMine(string id)
        {
            await _recipeService.DeleteMineAsync(User.GetUserId(), id);
            return Ok(ApiResponse<object?>.Ok(null, "Đã xoá công thức."));
        }

        /// <summary>"Lưu thành công thức của tôi": bản riêng tư từ một công thức đã có.</summary>
        [HttpPost("api/v1/recipes/{id}/variants")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<RecipeResponse>), StatusCodes.Status201Created)]
        public async Task<ActionResult<ApiResponse<RecipeResponse>>> CreateVariant(string id, [FromBody] CreateRecipeVariantRequest request)
        {
            var created = await _recipeService.CreateVariantAsync(User.GetUserId(), id, request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<RecipeResponse>.Created(created, "Đã lưu công thức."));
        }

        /// <summary>Đánh giá của công thức công khai, mới nhất trước; có token thì thêm myReview.</summary>
        [HttpGet("api/v1/recipes/{id}/reviews")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<RecipeReviewsPageResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<RecipeReviewsPageResponse>>> GetReviews(
            string id,
            [FromQuery] string? cursor = null,
            [FromQuery] int? limit = null)
        {
            var result = await _recipeService.GetReviewsAsync(User.GetUserIdOrDefault(), id, cursor, limit);
            return Ok(ApiResponse<RecipeReviewsPageResponse>.Ok(result));
        }

        /// <summary>Tạo hoặc thay đánh giá của tôi (mỗi người một đánh giá trên một công thức).</summary>
        [HttpPut("api/v1/recipes/{id}/reviews/me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<ReviewWriteResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<ReviewWriteResponse>>> UpsertMyReview(string id, [FromBody] UpsertRecipeReviewRequest request)
        {
            var result = await _recipeService.UpsertMyReviewAsync(User.GetUserId(), id, request);
            return Ok(ApiResponse<ReviewWriteResponse>.Ok(result, "Đã lưu đánh giá."));
        }

        /// <summary>Xoá đánh giá của tôi, trả tổng mới (không dùng 204).</summary>
        [HttpDelete("api/v1/recipes/{id}/reviews/me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<RatingTotalsResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<RatingTotalsResponse>>> DeleteMyReview(string id)
        {
            var result = await _recipeService.DeleteMyReviewAsync(User.GetUserId(), id);
            return Ok(ApiResponse<RatingTotalsResponse>.Ok(result, "Đã xoá đánh giá."));
        }

        /// <summary>Ghi chú riêng của tôi. 404 nghĩa là chưa có ghi chú.</summary>
        [HttpGet("api/v1/recipes/{id}/notes/me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<RecipeNoteResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<RecipeNoteResponse>>> GetMyNote(string id)
        {
            var result = await _recipeService.GetMyNoteAsync(User.GetUserId(), id);
            return Ok(ApiResponse<RecipeNoteResponse>.Ok(result));
        }

        /// <summary>Lưu ghi chú; nội dung rỗng là xoá và trả data null.</summary>
        [HttpPut("api/v1/recipes/{id}/notes/me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<RecipeNoteResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<RecipeNoteResponse?>>> SaveMyNote(string id, [FromBody] SaveRecipeNoteRequest request)
        {
            var result = await _recipeService.SaveMyNoteAsync(User.GetUserId(), id, request);
            return Ok(ApiResponse<RecipeNoteResponse?>.Ok(result));
        }

        /// <summary>Xoá ghi chú của tôi.</summary>
        [HttpDelete("api/v1/recipes/{id}/notes/me")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<object>>> DeleteMyNote(string id)
        {
            await _recipeService.DeleteMyNoteAsync(User.GetUserId(), id);
            return Ok(ApiResponse<object?>.Ok(null, "Đã xoá ghi chú."));
        }

        /// <summary>Bài viết nhắc tới công thức này.</summary>
        [HttpGet("api/v1/recipes/{id}/related-posts")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<PostResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<PostResponse>>>> GetRelatedPosts(string id)
        {
            var result = await _recipeService.GetRelatedPostsAsync(User.GetUserIdOrDefault(), id);
            return Ok(ApiResponse<IEnumerable<PostResponse>>.Ok(result));
        }
    }
}
