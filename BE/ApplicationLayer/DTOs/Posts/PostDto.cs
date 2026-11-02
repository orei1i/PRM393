using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Posts
{
    public class AuthorSummaryDto
    {
        public string Id { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public bool IsVerifiedChef { get; set; } = false;
    }

    public class VideoSummaryDto
    {
        public string Id { get; set; } = string.Empty;
        public int? DurationSeconds { get; set; }
        public string AiStatus { get; set; } = "ready";
    }

    public class PostResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Type { get; set; } = "discussion";
        public AuthorSummaryDto Author { get; set; } = new();
        public string Title { get; set; } = string.Empty;
        public string Body { get; set; } = string.Empty;
        public List<string> Tags { get; set; } = new();
        public string? CoverSeed { get; set; }
        public int LikeCount { get; set; }
        public int CommentCount { get; set; }
        public int ReportCount { get; set; }
        public string? RejectionReason { get; set; }
        public bool LikedByMe { get; set; }
        public bool SavedByMe { get; set; }
        public bool IsPinned { get; set; }
        public DateTime CreatedAt { get; set; }
        public string Status { get; set; } = "Published";
        public string MediaType { get; set; } = "Text";
        public string? MediaUrl { get; set; }
        public VideoSummaryDto? Video { get; set; }
        public object? Restaurant { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class CreatePostRequest
    {
        [RegularExpression("^(recipe|discussion)$", ErrorMessage = "Type chỉ chấp nhận 'recipe' hoặc 'discussion'.")]
        public string Type { get; set; } = "discussion"; // "recipe" | "discussion"

        [Required(ErrorMessage = "Tiêu đề bài viết là bắt buộc.")]
        [StringLength(120, MinimumLength = 1, ErrorMessage = "Tiêu đề không được vượt quá 120 ký tự.")]
        public string Title { get; set; } = string.Empty;

        [Required(ErrorMessage = "Nội dung bài viết là bắt buộc.")]
        [MaxLength(3000, ErrorMessage = "Nội dung không được vượt quá 3000 ký tự.")]
        public string Body { get; set; } = string.Empty;

        public List<string>? Tags { get; set; }

        [RegularExpression("^(Text|Image|Video)$", ErrorMessage = "MediaType chỉ chấp nhận 'Text', 'Image', hoặc 'Video'.")]
        public string? MediaType { get; set; } = "Text"; // "Text" | "Image" | "Video"

        public string? MediaUrl { get; set; }

        public string? RestaurantId { get; set; }
    }

    public class FeedPageResponse
    {
        public List<PostResponse> Items { get; set; } = new();
        public string? NextCursor { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public long TotalItems { get; set; }
        public int TotalPages { get; set; }
    }

    public class AdminReviewPostRequest
    {
        [Required(ErrorMessage = "Quyết định kiểm duyệt là bắt buộc.")]
        [RegularExpression("^(Approve|Reject)$", ErrorMessage = "Decision chỉ nhận 'Approve' hoặc 'Reject'.")]
        public string Decision { get; set; } = string.Empty; // "Approve" | "Reject"
        public string? Reason { get; set; }
    }

    public class AdminActionPostRequest
    {
        [Required(ErrorMessage = "Hành động quản trị là bắt buộc.")]
        [RegularExpression("^(hide|unhide|pin|unpin|delete)$", ErrorMessage = "Action chỉ nhận 'hide', 'unhide', 'pin', 'unpin', hoặc 'delete'.")]
        public string Action { get; set; } = string.Empty; // "hide" | "unhide" | "pin" | "unpin" | "delete"
        public string? Reason { get; set; }
    }

    public class AdminStatusPostRequest
    {
        [Required(ErrorMessage = "Trạng thái là bắt buộc.")]
        [RegularExpression("^(Published|Pending|Rejected|Hidden)$", ErrorMessage = "Status chỉ nhận 'Published', 'Pending', 'Rejected', hoặc 'Hidden'.")]
        public string Status { get; set; } = string.Empty; // "Published" | "Pending" | "Rejected" | "Hidden"
    }
}
