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

    public class UpdateCommentRequest
    {
        [Required(ErrorMessage = "Nội dung bình luận là bắt buộc.")]
        [MaxLength(500, ErrorMessage = "Bình luận không được vượt quá 500 ký tự.")]
        public string Content { get; set; } = string.Empty;
    }

    public class MyCommentResponse
    {
        public string Id { get; set; } = string.Empty;
        public string PostId { get; set; } = string.Empty;
        public string PostTitle { get; set; } = string.Empty;
        public string? ParentId { get; set; }
        public string Content { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class AdminCommentReplyToDto
    {
        public string Id { get; set; } = string.Empty;
        public string AuthorName { get; set; } = string.Empty;
    }

    public class AdminCommentAuthorDto
    {
        public string Id { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
    }

    public class AdminCommentResponse
    {
        public string Id { get; set; } = string.Empty;
        public string PostId { get; set; } = string.Empty;
        public string PostTitle { get; set; } = string.Empty;
        public string? ParentId { get; set; }
        public AdminCommentReplyToDto? ReplyTo { get; set; }
        public int ReplyCount { get; set; }
        public AdminCommentAuthorDto Author { get; set; } = new();
        public string Content { get; set; } = string.Empty;
        public string Status { get; set; } = "Visible";
        public int ReportCount { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class AdminDeleteCommentRequest
    {
        [MaxLength(500, ErrorMessage = "Lý do không được vượt quá 500 ký tự.")]
        public string? Reason { get; set; }
    }

    public class AdminCommentActionRequest
    {
        [Required(ErrorMessage = "Hành động là bắt buộc.")]
        [RegularExpression("^(hide|unhide)$", ErrorMessage = "Action chỉ nhận 'hide' hoặc 'unhide'.")]
        public string Action { get; set; } = string.Empty;
    }

    public class SaveResponse
    {
        public bool Saved { get; set; }
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
