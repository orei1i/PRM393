using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Posts
{
    public class CommentResponse
    {
        public string Id { get; set; } = string.Empty;
        public string PostId { get; set; } = string.Empty;
        public string? ParentId { get; set; }
        public AuthorSummaryDto Author { get; set; } = new();
        public string Content { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int ReplyCount { get; set; }
        public List<CommentResponse> Replies { get; set; } = new();
    }

    public class CreateCommentRequest
    {
        [Required(ErrorMessage = "Nội dung bình luận là bắt buộc.")]
        [MaxLength(500, ErrorMessage = "Bình luận không được vượt quá 500 ký tự.")]
        public string Content { get; set; } = string.Empty;

        public string? ParentId { get; set; }
    }

    public class LikeResponse
    {
        public bool Liked { get; set; }
        public int LikeCount { get; set; }
    }

    public class ReportPostRequest
    {
        [Required(ErrorMessage = "Lý do báo cáo là bắt buộc.")]
        [MaxLength(500, ErrorMessage = "Lý do không được vượt quá 500 ký tự.")]
        public string Reason { get; set; } = string.Empty;
    }
}
