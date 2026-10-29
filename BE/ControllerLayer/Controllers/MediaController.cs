using System.Threading.Tasks;
using ApplicationLayer.DTOs.Media;
using ApplicationLayer.Interfaces;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/[controller]")]
    [ApiController]
    public class MediaController : ControllerBase
    {
        private readonly IMediaService _mediaService;

        public MediaController(IMediaService mediaService)
        {
            _mediaService = mediaService;
        }

        /// <summary>Tải ảnh lên Cloudinary (tối đa 10 MB, JPG/PNG/WEBP/HEIC).</summary>
        /// <response code="200">Tải ảnh lên thành công.</response>
        /// <response code="400">Thiếu tệp hoặc tệp rỗng.</response>
        /// <response code="401">Chưa đăng nhập.</response>
        /// <response code="413">Ảnh vượt quá dung lượng 10 MB.</response>
        /// <response code="415">Định dạng ảnh không được hỗ trợ.</response>
        [HttpPost("images")]
        [Authorize]
        [ProducesResponseType(typeof(ApiResponse<UploadedImageResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status413PayloadTooLarge)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status415UnsupportedMediaType)]
        public async Task<ActionResult<ApiResponse<UploadedImageResponse>>> UploadImage(IFormFile file)
        {
            var userId = User.GetUserId();
            var result = await _mediaService.UploadImageAsync(file, userId);
            return Ok(ApiResponse<UploadedImageResponse>.Ok(result, "Tải ảnh lên thành công."));
        }

        /// <summary>Tải video lên Cloudinary (tối đa 100 MB, MP4/MOV/WEBM).</summary>
        /// <response code="200">Tải video lên thành công.</response>
        /// <response code="400">Thiếu tệp hoặc tệp rỗng.</response>
        /// <response code="401">Chưa đăng nhập.</response>
        /// <response code="413">Video vượt quá dung lượng 100 MB.</response>
        /// <response code="415">Định dạng video không được hỗ trợ.</response>
        [HttpPost("videos")]
        [Authorize]
        [RequestSizeLimit(104857600)] // 100 MB
        [RequestFormLimits(MultipartBodyLengthLimit = 104857600)]
        [ProducesResponseType(typeof(ApiResponse<UploadedVideoResponse>), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status401Unauthorized)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status413PayloadTooLarge)]
        [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status415UnsupportedMediaType)]
        public async Task<ActionResult<ApiResponse<UploadedVideoResponse>>> UploadVideo(IFormFile file)
        {
            var userId = User.GetUserId();
            var result = await _mediaService.UploadVideoAsync(file, userId);
            return Ok(ApiResponse<UploadedVideoResponse>.Ok(result, "Tải video lên thành công."));
        }
    }
}
