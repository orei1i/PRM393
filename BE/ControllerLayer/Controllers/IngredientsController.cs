using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.Interfaces;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/ingredients")]
    [Route("api/v1/catalog/ingredients")]
    public class IngredientsController : ControllerBase
    {
        private readonly IPantryService _pantryService;

        public IngredientsController(IPantryService pantryService)
        {
            _pantryService = pantryService;
        }

        /// <summary>Tìm kiếm danh mục nguyên liệu theo tên hoặc tên gọi khác (không phân biệt dấu).</summary>
        [HttpGet]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<IngredientResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<IngredientResponse>>>> Search([FromQuery] string? q, [FromQuery] bool veganOnly = true)
        {
            var results = await _pantryService.SearchIngredientsAsync(q, veganOnly);
            return Ok(ApiResponse<IEnumerable<IngredientResponse>>.Ok(results));
        }

        /// <summary>Lấy chi tiết thông tin dinh dưỡng của 1 nguyên liệu.</summary>
        [HttpGet("{id}")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<IngredientResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<IngredientResponse>>> GetById(string id)
        {
            var result = await _pantryService.GetIngredientByIdAsync(id);
            return Ok(ApiResponse<IngredientResponse>.Ok(result));
        }
    }
}

