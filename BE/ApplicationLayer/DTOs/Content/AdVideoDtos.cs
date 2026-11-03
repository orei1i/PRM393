using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using ApplicationLayer.DTOs.Posts;

namespace ApplicationLayer.DTOs.Content
{
    public class AdRestaurantResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Address { get; set; } = string.Empty;
        public bool IsVeganCertified { get; set; }
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }

        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public double? AverageRating { get; set; }

        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public int? ReviewCount { get; set; }
    }

    public class AdFeedItemResponse
    {
        public string Id { get; set; } = string.Empty;
        public string RestaurantId { get; set; } = string.Empty;
        public string Placement { get; set; } = string.Empty;
        public AdRestaurantResponse Restaurant { get; set; } = new();
        public string Headline { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string CtaType { get; set; } = string.Empty;
        public string CtaLabel { get; set; } = string.Empty;
        public string? TargetCity { get; set; }
        public DateTime StartAt { get; set; }
        public DateTime EndAt { get; set; }
        public double? DistanceKm { get; set; }
    }

    public class AdCampaignResponse
    {
        public string Id { get; set; } = string.Empty;
        public string RestaurantId { get; set; } = string.Empty;
        public AdRestaurantResponse Restaurant { get; set; } = new();
        public string Placement { get; set; } = string.Empty;
        public string Headline { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string CtaType { get; set; } = string.Empty;
        public string? TargetCity { get; set; }
        public DateTime StartAt { get; set; }
        public DateTime EndAt { get; set; }
        public bool IsPaused { get; set; }
        public string Status { get; set; } = string.Empty;
        public long Budget { get; set; }
        public long Spent { get; set; }
        public long Impressions { get; set; }
        public long Clicks { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
    }

    /// <summary>POST và PATCH dùng chung. PATCH phân biệt "không gửi" với "gửi null" ở targetCity (null là toàn quốc).</summary>
    public class AdInputRequest
    {
        private string? _targetCity;

        public string? RestaurantId { get; set; }
        public string? Placement { get; set; }
        public string? Headline { get; set; }
        public string? Message { get; set; }
        public string? CtaType { get; set; }

        public string? TargetCity
        {
            get => _targetCity;
            set
            {
                _targetCity = value;
                HasTargetCity = true;
            }
        }

        [JsonIgnore]
        public bool HasTargetCity { get; private set; }

        public DateTime? StartAt { get; set; }
        public DateTime? EndAt { get; set; }
        public long? Budget { get; set; }
    }

    public class VideoResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public AuthorSummaryDto Author { get; set; } = new();
        public string CoverSeed { get; set; } = string.Empty;
        public string? VideoUrl { get; set; }
        public int? DurationSeconds { get; set; }
        public string AiStatus { get; set; } = string.Empty;
        public string? Summary { get; set; }
        public int? Servings { get; set; }
        public int? TotalMinutes { get; set; }
        public int? KcalPerServing { get; set; }
        public List<VideoIngredientDto> Ingredients { get; set; } = new();
        public List<VideoStepDto> Steps { get; set; } = new();
        public List<VideoTranscriptDto> Transcript { get; set; } = new();
        public string? FailureReason { get; set; }
    }

    public class VideoIngredientDto
    {
        public string Name { get; set; } = string.Empty;
        public string Quantity { get; set; } = string.Empty;
        public int? AtSecond { get; set; }
        public bool Uncertain { get; set; }
    }

    public class VideoStepDto
    {
        public int Index { get; set; }
        public string Text { get; set; } = string.Empty;
        public int? AtSecond { get; set; }
    }

    public class VideoTranscriptDto
    {
        public int AtSecond { get; set; }
        public string Text { get; set; } = string.Empty;
    }

    /// <summary>Đầu ra Gemini khi trích xuất công thức từ video.</summary>
    public class VideoExtractionResult
    {
        public string? Summary { get; set; }
        public int? Servings { get; set; }
        public int? TotalMinutes { get; set; }
        public int? KcalPerServing { get; set; }
        public List<VideoIngredientDto>? Ingredients { get; set; }
        public List<VideoStepDto>? Steps { get; set; }
        public List<VideoTranscriptDto>? Transcript { get; set; }
    }
}
