using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Knowledge;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using DomainLayer.Exceptions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [ApiController]
    [Route("api/v1/admin/knowledge-docs")]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminKnowledgeDocsController : ControllerBase
    {
        private const long MaxUploadBytes = 31_457_280; // 30 MB

        private readonly IKnowledgeService _knowledge;

        public AdminKnowledgeDocsController(IKnowledgeService knowledge)
        {
            _knowledge = knowledge;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<KnowledgeDocResponse>>>> List(
            [FromQuery] string? status, [FromQuery] string? source, [FromQuery] string? search)
        {
            return Ok(ApiResponse<List<KnowledgeDocResponse>>.Ok(await _knowledge.ListAsync(status, source, search)));
        }

        [HttpGet("counts")]
        public async Task<ActionResult<ApiResponse<Dictionary<string, long>>>> Counts()
        {
            return Ok(ApiResponse<Dictionary<string, long>>.Ok(await _knowledge.CountsAsync()));
        }

        /// <summary>Tải tài liệu WHO: duyệt ngay khi tạo chỉ mục thành công, lỗi thì để Pending kèm ingestError.</summary>
        [HttpPost]
        [RequestSizeLimit(10_485_760)]
        [ProducesResponseType(typeof(ApiResponse<KnowledgeDocResponse>), StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<KnowledgeDocResponse>>> Create([FromBody] CreateKnowledgeDocRequest request)
        {
            var doc = await _knowledge.CreateAdminDocAsync(request, User.GetUserId(), HttpContext.RequestAborted);
            return Ok(ApiResponse<KnowledgeDocResponse>.Ok(doc));
        }

        /// <summary>Tải tệp PDF, .txt hoặc .md. Luồng giống POST ở trên, chữ được đọc ở server.</summary>
        [HttpPost("upload")]
        [Consumes("multipart/form-data")]
        [RequestSizeLimit(MaxUploadBytes + 1_048_576)]
        [RequestFormLimits(MultipartBodyLengthLimit = MaxUploadBytes + 1_048_576)]
        public async Task<ActionResult<ApiResponse<KnowledgeDocResponse>>> Upload(
            IFormFile file,
            [FromForm] string title,
            [FromForm] string? fileUrl,
            [FromForm] string? publisher,
            [FromForm] DateTime? publishedAt)
        {
            if (file == null || file.Length == 0) throw new BadRequestException("Chưa chọn tệp hoặc tệp rỗng.", "empty_document");
            if (file.Length > MaxUploadBytes) throw new PayloadTooLargeException("Tệp quá lớn: tối đa 30 MB.");

            var request = new CreateKnowledgeDocRequest
            {
                Title = title,
                Content = await ReadTextAsync(file),
                FileUrl = fileUrl,
                Publisher = publisher,
                PublishedAt = publishedAt
            };
            var doc = await _knowledge.CreateAdminDocAsync(request, User.GetUserId(), HttpContext.RequestAborted);
            return Ok(ApiResponse<KnowledgeDocResponse>.Ok(doc));
        }

        /// <summary>Xét theo nội dung tệp, không tin phần đuôi tên hay Content-Type client gửi.</summary>
        private async Task<string> ReadTextAsync(IFormFile file)
        {
            await using var buffered = new MemoryStream();
            await file.CopyToAsync(buffered, HttpContext.RequestAborted);
            var bytes = buffered.ToArray();

            if (bytes.AsSpan().StartsWith("%PDF-"u8))
            {
                buffered.Position = 0;
                return _knowledge.ExtractPdfText(buffered);
            }

            if (!file.FileName.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)
                && !file.FileName.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
            {
                throw new UnsupportedMediaTypeException("Chỉ nhận tệp PDF, .txt hoặc .md.");
            }

            try
            {
                return new UTF8Encoding(false, true).GetString(bytes);
            }
            catch (DecoderFallbackException)
            {
                throw new UnsupportedMediaTypeException("Tệp văn bản phải dùng mã hoá UTF-8.");
            }
        }

        [HttpPost("{id}/review")]
        public async Task<ActionResult<ApiResponse<KnowledgeDocResponse>>> Review(string id, [FromBody] ReviewKnowledgeDocRequest request)
        {
            var doc = await _knowledge.ReviewAsync(id, request, User.GetUserId(), HttpContext.RequestAborted);
            return Ok(ApiResponse<KnowledgeDocResponse>.Ok(doc));
        }

        /// <summary>Cập nhật nội dung. Tài liệu đã duyệt được tạo lại chỉ mục, lỗi AI thì bản cũ giữ nguyên.</summary>
        [HttpPut("{id}/content")]
        public async Task<ActionResult<ApiResponse<KnowledgeDocResponse>>> UpdateContent(string id, [FromBody] UpdateKnowledgeContentRequest request)
        {
            var doc = await _knowledge.UpdateContentAsync(id, request, User.GetUserId(), HttpContext.RequestAborted);
            return Ok(ApiResponse<KnowledgeDocResponse>.Ok(doc));
        }

        [HttpDelete("{id}")]
        public async Task<ActionResult<ApiResponse<object>>> Delete(string id)
        {
            await _knowledge.DeleteAsync(id);
            return Ok(ApiResponse<object>.Ok(new { }, "Đã xoá tài liệu."));
        }

        [HttpGet("{id}/chunks")]
        public async Task<ActionResult<ApiResponse<List<KnowledgeChunkResponse>>>> Chunks(string id, [FromQuery] int limit = 5)
        {
            return Ok(ApiResponse<List<KnowledgeChunkResponse>>.Ok(await _knowledge.GetChunksAsync(id, limit)));
        }
    }

    /// <summary>Chuyên gia gửi tài liệu, chỉ thấy tài liệu của mình. Tài liệu chờ admin duyệt mới được AI dùng.</summary>
    [ApiController]
    [Route("api/v1/chefs/me/knowledge-docs")]
    [Authorize(Roles = AppRoles.Chef)]
    [RequestSizeLimit(10_485_760)]
    public class ChefKnowledgeDocsController : ControllerBase
    {
        private readonly IKnowledgeService _knowledge;

        public ChefKnowledgeDocsController(IKnowledgeService knowledge)
        {
            _knowledge = knowledge;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<KnowledgeDocResponse>>>> ListMine()
        {
            return Ok(ApiResponse<List<KnowledgeDocResponse>>.Ok(await _knowledge.ListMineAsync(User.GetUserId())));
        }

        [HttpPost]
        public async Task<ActionResult<ApiResponse<KnowledgeDocResponse>>> Submit([FromBody] CreateKnowledgeDocRequest request)
        {
            return Ok(ApiResponse<KnowledgeDocResponse>.Ok(await _knowledge.SubmitChefDocAsync(request, User.GetUserId())));
        }
    }
}
