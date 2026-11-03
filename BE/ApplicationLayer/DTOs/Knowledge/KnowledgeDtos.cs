using System;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Knowledge
{
    public class KnowledgeDocResponse
    {
        public string Id { get; set; } = string.Empty;
        public string? ChefId { get; set; }
        public string? ChefName { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Source { get; set; } = string.Empty;
        public string FileUrl { get; set; } = string.Empty;
        public string? Publisher { get; set; }
        public DateTime? PublishedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public string Status { get; set; } = string.Empty;
        public int ChunkCount { get; set; }
        public int CitationCount { get; set; }
        public string? ReviewNote { get; set; }
        public string? ReviewedBy { get; set; }
        public DateTime? ReviewedAt { get; set; }
        public string IngestStatus { get; set; } = string.Empty;
        public string? IngestError { get; set; }
    }

    public class KnowledgeChunkResponse
    {
        public string Id { get; set; } = string.Empty;
        public string DocId { get; set; } = string.Empty;
        public int ChunkIndex { get; set; }
        public string Content { get; set; } = string.Empty;
    }

    /// <summary>
    /// Nội dung gửi trực tiếp dưới dạng văn bản. FileUrl chỉ là liên kết nguồn để hiển thị:
    /// server không tự tải URL do client đưa (tránh SSRF).
    /// </summary>
    public class CreateKnowledgeDocRequest
    {
        [Required(ErrorMessage = "Tiêu đề tài liệu là bắt buộc.")]
        [StringLength(200, MinimumLength = 3, ErrorMessage = "Tiêu đề phải từ 3 đến 200 ký tự.")]
        public string Title { get; set; } = string.Empty;

        [Required(ErrorMessage = "Nội dung tài liệu là bắt buộc.")]
        public string Content { get; set; } = string.Empty;

        [MaxLength(500, ErrorMessage = "Liên kết nguồn tối đa 500 ký tự.")]
        public string? FileUrl { get; set; }

        [MaxLength(200, ErrorMessage = "Nhà xuất bản tối đa 200 ký tự.")]
        public string? Publisher { get; set; }

        public DateTime? PublishedAt { get; set; }
    }

    public class ReviewKnowledgeDocRequest
    {
        [Required(ErrorMessage = "Quyết định duyệt là bắt buộc.")]
        [RegularExpression("^(Approve|Reject)$", ErrorMessage = "Decision chỉ nhận 'Approve' hoặc 'Reject'.")]
        public string Decision { get; set; } = string.Empty;

        [MaxLength(1000, ErrorMessage = "Ghi chú tối đa 1000 ký tự.")]
        public string? Note { get; set; }
    }

    public class UpdateKnowledgeContentRequest
    {
        [Required(ErrorMessage = "Nội dung tài liệu là bắt buộc.")]
        public string Content { get; set; } = string.Empty;
    }
}
