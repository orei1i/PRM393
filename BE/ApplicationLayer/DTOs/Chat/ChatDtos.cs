using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Chat
{
    public class GuestTrialResponse
    {
        public int Limit { get; set; }
        public int Used { get; set; }
        public int Remaining { get; set; }
    }

    public class ChatContextOptions
    {
        public bool IncludeMealPlan { get; set; }
        public bool IncludeHealthProfile { get; set; }
    }

    public class ChatMessageRequest
    {
        [Required(ErrorMessage = "Câu hỏi là bắt buộc.")]
        [StringLength(2000, MinimumLength = 1, ErrorMessage = "Câu hỏi tối đa 2000 ký tự.")]
        public string Message { get; set; } = string.Empty;

        [Range(0, int.MaxValue, ErrorMessage = "resumeFrom không hợp lệ.")]
        public int ResumeFrom { get; set; }

        public ChatContextOptions? Context { get; set; }
    }

    /// <summary>Người gọi: lấy từ JWT hoặc header X-Guest-Token, không bao giờ từ body.</summary>
    public class ChatCaller
    {
        public string? UserId { get; set; }
        public string? GuestToken { get; set; }
        public bool IsGuest => string.IsNullOrEmpty(UserId);
    }

    public class ChatCitationDto
    {
        public int Index { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Publisher { get; set; } = string.Empty;
        public string SourceType { get; set; } = "scientific";
        public string Passage { get; set; } = string.Empty;
        public string? Url { get; set; }
        public DateTime? PublishedAt { get; set; }
        public bool Verified { get; set; }
    }

    public class ChatHistoryMessage
    {
        public string Id { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public List<ChatCitationDto> Citations { get; set; } = new();
    }

    /// <summary>Một sự kiện SSE: tên sự kiện và object được serialize vào dòng data.</summary>
    public readonly record struct ChatSseEvent(string Name, object Data);
}
