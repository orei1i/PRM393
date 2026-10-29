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
        public int DurationSeconds { get; set; }
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
        public string Type { get; set; } = "discussion"; // "recipe" | "discussion"

        [Required(ErrorMessage = "Tiêu đề bài viết là bắt buộc.")]
        [MaxLength(200, ErrorMessage = "Tiêu đề không được vượt quá 200 ký tự.")]
        public string Title { get; set; } = string.Empty;

        [Required(ErrorMessage = "Nội dung bài viết là bắt buộc.")]
        [MaxLength(3000, ErrorMessage = "Nội dung không được vượt quá 3000 ký tự.")]
        public string Body { get; set; } = string.Empty;

        public List<string>? Tags { get; set; }

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
}
