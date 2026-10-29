using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/pantry")]
    [Route("api/v1/users/me/ingredients")]
    public class PantryController : ControllerBase
    {
        private readonly IPantryService _pantryService;

        public PantryController(IPantryService pantryService)
        {
            _pantryService = pantryService;
        }

        /// <summary>Lấy danh sách nguyên liệu trong tủ lạnh của người dùng.</summary>
        [HttpGet]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<PantryItemResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<PantryItemResponse>>>> GetPantry([FromQuery] int? expiringInDays)
        {
            var userId = User.GetUserId();
            var items = await _pantryService.GetPantryItemsAsync(userId, expiringInDays);
            return Ok(ApiResponse<IEnumerable<PantryItemResponse>>.Ok(items));
        }

        /// <summary>Thêm nguyên liệu vào tủ lạnh (hỗ trợ cả dạng đơn lẻ hoặc danh sách items: [...]).</summary>
        [HttpPost]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<PantryItemResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<PantryItemResponse>>>> AddPantryItems([FromBody] JsonElement body)
        {
            var userId = User.GetUserId();

            // Kiểm tra xem body có chứa property "items" (dạng batch của Flutter) hay là 1 item đơn lẻ
            if (body.ValueKind == JsonValueKind.Object && body.TryGetProperty("items", out var itemsElement) && itemsElement.ValueKind == JsonValueKind.Array)
            {
                var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var batchRequest = JsonSerializer.Deserialize<AddPantryItemsBatchRequest>(body.GetRawText(), options);
                var items = await _pantryService.AddPantryItemsBatchAsync(userId, batchRequest?.Items ?? new List<AddPantryItemRequest>());
                return Ok(ApiResponse<IEnumerable<PantryItemResponse>>.Ok(items, "Thêm nguyên liệu thành công."));
            }
            else
            {
                var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var singleRequest = JsonSerializer.Deserialize<AddPantryItemRequest>(body.GetRawText(), options);
                if (singleRequest == null || string.IsNullOrWhiteSpace(singleRequest.Ingredient))
                {
                    return BadRequest(ApiResponse<object>.Fail("Tên nguyên liệu không được để trống.", 400));
                }
                var item = await _pantryService.AddPantryItemAsync(userId, singleRequest);
                return Ok(ApiResponse<IEnumerable<PantryItemResponse>>.Ok(new[] { item }, "Thêm nguyên liệu thành công."));
            }
        }

        /// <summary>Thêm nhiều nguyên liệu cùng lúc (sau khi quét ảnh tủ lạnh).</summary>
        [HttpPost("bulk")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<PantryItemResponse>>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<IEnumerable<PantryItemResponse>>>> AddPantryItemsBulk([FromBody] AddPantryItemsBatchRequest request)
        {
            var userId = User.GetUserId();
            var items = await _pantryService.AddPantryItemsBatchAsync(userId, request.Items);
            return Ok(ApiResponse<IEnumerable<PantryItemResponse>>.Ok(items, "Thêm danh sách nguyên liệu thành công."));
        }

        /// <summary>Cập nhật số lượng, đơn vị, hạn dùng của nguyên liệu trong tủ.</summary>
        [HttpPut("{id}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<PantryItemResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<PantryItemResponse>>> UpdatePantryItem(string id, [FromBody] UpdatePantryItemRequest request)
        {
            var userId = User.GetUserId();
            var updated = await _pantryService.UpdatePantryItemAsync(userId, id, request);
            return Ok(ApiResponse<PantryItemResponse>.Ok(updated, "Cập nhật nguyên liệu thành công."));
        }

        /// <summary>Xóa 1 nguyên liệu khỏi tủ lạnh.</summary>
        [HttpDelete("{id}")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<object>>> DeletePantryItem(string id)
        {
            var userId = User.GetUserId();
            var success = await _pantryService.DeletePantryItemAsync(userId, id);
            if (!success)
            {
                return NotFound(ApiResponse<object>.NotFound($"Không tìm thấy nguyên liệu với id: {id}"));
            }
            return Ok(ApiResponse<object?>.Ok(null, "Đã xóa nguyên liệu khỏi tủ lạnh."));
        }

        /// <summary>Xóa toàn bộ nguyên liệu trong tủ lạnh.</summary>
        [HttpDelete]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<object>>> ClearPantry()
        {
            var userId = User.GetUserId();
            await _pantryService.ClearPantryAsync(userId);
            return Ok(ApiResponse<object?>.Ok(null, "Đã làm trống tủ lạnh."));
        }
    }
}
