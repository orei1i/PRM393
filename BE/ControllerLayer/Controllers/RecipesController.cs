using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/recipes")]
    [Route("api/v1/users/me/recipes")]
    [Authorize]
    public class RecipesController : ControllerBase
    {
        private readonly IMealPlanService _mealPlanService;

        public RecipesController(IMealPlanService mealPlanService)
        {
            _mealPlanService = mealPlanService;
        }

        /// <summary>Lấy danh sách các công thức do chính người dùng tự tạo ("Món của tôi").</summary>
        [HttpGet]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<RecipeResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<RecipeResponse>>>> GetMyRecipes()
        {
            var userId = User.GetUserId();
            var results = await _mealPlanService.GetMyRecipesAsync(userId);
            return Ok(ApiResponse<IEnumerable<RecipeResponse>>.Ok(results));
        }

        /// <summary>Lấy chi tiết một công thức theo ID.</summary>
        [HttpGet("{id}")]
        [ProducesResponseType(typeof(ApiResponse<RecipeResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<RecipeResponse>>> GetById(string id)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.GetRecipeByIdAsync(userId, id);
            return Ok(ApiResponse<RecipeResponse>.Ok(result));
        }

        /// <summary>Tạo mới một công thức món ăn của riêng tôi.</summary>
        [HttpPost]
        [ProducesResponseType(typeof(ApiResponse<RecipeResponse>), StatusCodes.Status201Created)]
        public async Task<ActionResult<ApiResponse<RecipeResponse>>> CreateMyRecipe([FromBody] CreateRecipeRequest request)
        {
            var userId = User.GetUserId();
            var created = await _mealPlanService.CreateMyRecipeAsync(userId, request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<RecipeResponse>.Created(created, "Tạo công thức thành công."));
        }
    }
}
