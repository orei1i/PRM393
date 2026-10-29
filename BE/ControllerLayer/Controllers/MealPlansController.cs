using System;
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
    [Route("api/v1/meal-plans")]
    [Authorize]
    public class MealPlansController : ControllerBase
    {
        private readonly IMealPlanService _mealPlanService;

        public MealPlansController(IMealPlanService mealPlanService)
        {
            _mealPlanService = mealPlanService;
        }

        /// <summary>Lấy thực đơn tuần hiện tại của người dùng.</summary>
        [HttpGet("current")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<MealPlanResponse>>> GetCurrent()
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.GetCurrentMealPlanAsync(userId);
            return Ok(ApiResponse<MealPlanResponse>.Ok(result));
        }

        /// <summary>Lấy chi tiết một thực đơn theo ID.</summary>
        [HttpGet("{id}")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<MealPlanResponse>>> GetById(string id)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.GetMealPlanByIdAsync(userId, id);
            return Ok(ApiResponse<MealPlanResponse>.Ok(result));
        }

        /// <summary>Tạo mới thực đơn tuần (empty: true tạo tuần với các ô bữa trống để tự lên món).</summary>
        [HttpPost]
        [ProducesResponseType(typeof(ApiResponse<MealPlanResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<MealPlanResponse>>> Create([FromBody] CreateMealPlanRequest request)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.CreateMealPlanAsync(userId, request);
            return Ok(ApiResponse<MealPlanResponse>.Ok(result, "Tạo thực đơn thành công."));
        }

        /// <summary>Tự động sinh thực đơn 7 ngày khớp lượng calo mục tiêu và tuyệt đối loại trừ chất dị ứng.</summary>
        [HttpPost("generate")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
        public async Task<ActionResult<ApiResponse<MealPlanResponse>>> Generate([FromBody] GenerateMealPlanRequest request)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.GenerateMealPlanAsync(userId, request);
            return Ok(ApiResponse<MealPlanResponse>.Ok(result, "Tự động sinh thực đơn thành công."));
        }

        /// <summary>Tự động xếp thực đơn ưu tiên nguyên liệu đang có sẵn trong tủ lạnh (Pantry).</summary>
        [HttpPost("from-ingredients")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<MealPlanResponse>>> GenerateFromPantry([FromBody] GenerateMealPlanRequest request)
        {
            var userId = User.GetUserId();
            request.UsePantry = true;
            var result = await _mealPlanService.GenerateMealPlanAsync(userId, request);
            return Ok(ApiResponse<MealPlanResponse>.Ok(result, "Xếp thực đơn từ nguyên liệu trong tủ thành công."));
        }

        /// <summary>Đổi món ăn trong một ô bữa của thực đơn.</summary>
        [HttpPatch("{id}/meals")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanDayResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<MealPlanDayResponse>>> SwapMeal(string id, [FromBody] SwapMealRequestDto request)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.SwapMealAsync(userId, id, request);
            return Ok(ApiResponse<MealPlanDayResponse>.Ok(result, "Đổi món thành công."));
        }

        /// <summary>Thêm / Gán một món vào ô bữa của thực đơn tuần hiện tại.</summary>
        [HttpPost("current/meals")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanDayResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<MealPlanDayResponse>>> AddMealToCurrent([FromBody] AddMealRequestDto request)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.AddMealToCurrentPlanAsync(userId, request);
            return Ok(ApiResponse<MealPlanDayResponse>.Ok(result, "Cập nhật món ăn thành công."));
        }

        /// <summary>Gán hàng loạt món vào thực đơn tuần hiện tại (dùng khi áp dụng kế hoạch mẫu hoặc thực đơn chuyên gia).</summary>
        [HttpPost("current/meals/batch")]
        [ProducesResponseType(typeof(ApiResponse<AddMealsResultDto>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<AddMealsResultDto>>> AddMealsBatch([FromBody] AddMealsBatchRequestDto request)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.AddMealsBatchToCurrentPlanAsync(userId, request.Meals);
            return Ok(ApiResponse<AddMealsResultDto>.Ok(result, "Áp dụng danh sách món vào thực đơn thành công."));
        }

        /// <summary>Bỏ một món ăn khỏi ô bữa trong thực đơn.</summary>
        [HttpDelete("{id}/meals")]
        [ProducesResponseType(typeof(ApiResponse<MealPlanDayResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<MealPlanDayResponse>>> RemoveMeal(
            string id,
            [FromQuery] string date,
            [FromQuery] string slot)
        {
            var userId = User.GetUserId();
            var result = await _mealPlanService.RemoveMealAsync(userId, id, date, slot);
            return Ok(ApiResponse<MealPlanDayResponse>.Ok(result, "Đã bỏ món khỏi thực đơn."));
        }

        /// <summary>Lấy gợi ý 3-5 món thay thế phù hợp với loại bữa và lượng calo, không chứa dị ứng.</summary>
        [HttpGet("{id}/swap-suggestions")]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<RecipeResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<RecipeResponse>>>> GetSwapSuggestions(
            string id,
            [FromQuery] string date,
            [FromQuery] string slot,
            [FromQuery] int limit = 3)
        {
            var userId = User.GetUserId();
            var results = await _mealPlanService.GetSwapSuggestionsAsync(userId, id, date, slot, limit);
            return Ok(ApiResponse<IEnumerable<RecipeResponse>>.Ok(results));
        }
    }
}

