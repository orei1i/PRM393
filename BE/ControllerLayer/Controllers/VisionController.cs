using System.Security.Claims;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Vision;
using ApplicationLayer.Interfaces;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/[controller]")]
    [Route("api/v1/vision")]
    [Route("vision")]
    public class VisionController : ControllerBase
    {
        private readonly IVisionService _visionService;

        public VisionController(IVisionService visionService)
        {
            _visionService = visionService;
        }

        /// <summary>
        /// Quét ảnh tủ lạnh hoặc thực phẩm để nhận diện các nguyên liệu, phân loại thuần chay và tọa độ bounding box.
        /// </summary>
        /// <param name="image">Ảnh JPEG/PNG/WEBP, dung lượng tối đa 10 MB</param>
        /// <returns>Danh sách thực phẩm kèm thông tin thuần chay và phương án thay thế</returns>
        [HttpPost("scan")]
        [Consumes("multipart/form-data")]
        [ProducesResponseType(typeof(ApiResponse<ScanResultDto>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<ScanResultDto>), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ApiResponse<ScanResultDto>), StatusCodes.Status413PayloadTooLarge)]
        [ProducesResponseType(typeof(ApiResponse<ScanResultDto>), StatusCodes.Status429TooManyRequests)]
        public async Task<IActionResult> ScanFridgeImage(IFormFile image)
        {
            var currentUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            var result = await _visionService.ScanFridgeImageAsync(image, currentUserId, HttpContext.RequestAborted);
            return Ok(ApiResponse<ScanResultDto>.Ok(result, "Quét nhận diện thực phẩm thành công."));
        }
    }
}

