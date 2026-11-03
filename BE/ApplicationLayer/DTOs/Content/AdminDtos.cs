using System;
using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Content
{
    public class OverviewPending
    {
        public long AiFlags { get; set; }
        public long ChefApplications { get; set; }
        public long ReportedContent { get; set; }
        public long FailedVideos { get; set; }
        public long PendingPosts { get; set; }
    }

    public class OverviewDailyCount
    {
        public string Date { get; set; } = string.Empty;
        public int Count { get; set; }
    }

    public class OverviewContentMix
    {
        public string Kind { get; set; } = string.Empty;
        public long Count { get; set; }
    }

    public class OverviewAction
    {
        public string Id { get; set; } = string.Empty;
        public DateTime At { get; set; }
        public string Actor { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string Target { get; set; } = string.Empty;
    }

    public class OverviewResponse
    {
        public long TotalUsers { get; set; }
        public long NewUsers7d { get; set; }
        public double NewUsersDelta { get; set; }
        public long ActiveUsers24h { get; set; }
        public double ActiveDelta { get; set; }
        public long Posts24h { get; set; }
        public double PostsDelta { get; set; }
        public long AiQueries24h { get; set; }
        public double AiQueriesDelta { get; set; }
        public OverviewPending Pending { get; set; } = new();
        public List<OverviewDailyCount> SignupsDaily { get; set; } = new();
        public List<OverviewContentMix> ContentMix { get; set; } = new();
        public List<OverviewAction> RecentActions { get; set; } = new();
    }

    public class CatalogItemResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Kind { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
        public string Label { get; set; } = string.Empty;
        public bool Active { get; set; }
        public int UsageCount { get; set; }
        public string? CvLabel { get; set; }
    }

    public class CreateCatalogItemRequest
    {
        public string? Kind { get; set; }
        public string? Code { get; set; }
        public string? Label { get; set; }
        public string? CvLabel { get; set; }
    }

    public class PatchCatalogItemRequest
    {
        public string? Label { get; set; }
        public bool? Active { get; set; }
        public string? CvLabel { get; set; }
    }

    public class ModerationDecisionRequest
    {
        public string? FlagId { get; set; }
        public string? Action { get; set; }
        public string? Note { get; set; }
        public bool NotifyAuthor { get; set; }
    }

    public class FlagAuthorResponse
    {
        public string Id { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public string Handle { get; set; } = string.Empty;
        public string? AvatarUrl { get; set; }
        public int PriorWarnings { get; set; }
        public DateTime? JoinedAt { get; set; }
    }

    public class FlagMediaResponse
    {
        public string Url { get; set; } = string.Empty;
        public string Alt { get; set; } = string.Empty;
    }

    public class FlagStatsResponse
    {
        public int Likes { get; set; }
        public int Comments { get; set; }
        public int Reach { get; set; }
    }

    public class FlagPostResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public FlagAuthorResponse Author { get; set; } = new();
        public string Text { get; set; } = string.Empty;
        public List<FlagMediaResponse> Media { get; set; } = new();
        public List<string> IngredientTags { get; set; } = new();
        public DateTime CreatedAt { get; set; }
        public FlagStatsResponse Stats { get; set; } = new();
        public int ReportCount { get; set; }
        public string Visibility { get; set; } = string.Empty;
    }

    public class FlagScoreResponse
    {
        public string Category { get; set; } = string.Empty;
        public double Score { get; set; }
    }

    public class FlagSpanResponse
    {
        public int Start { get; set; }
        public int End { get; set; }
        public string Category { get; set; } = string.Empty;
    }

    public class FlagResponse
    {
        public string Id { get; set; } = string.Empty;
        public string PostId { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string PrimaryCategory { get; set; } = string.Empty;
        public double Confidence { get; set; }
        public double ToxicityScore { get; set; }
        public List<FlagScoreResponse> Scores { get; set; } = new();
        public string Reason { get; set; } = string.Empty;
        public List<FlagSpanResponse> Spans { get; set; } = new();
        public string SuggestedAction { get; set; } = string.Empty;
        public string? PolicyRef { get; set; }
        public string? ModelVersion { get; set; }
        public long LatencyMs { get; set; }
        public string? TraceId { get; set; }
        public DateTime CreatedAt { get; set; }
        public FlagPostResponse? Post { get; set; }
    }

    public class TelemetryDelta
    {
        public double TotalCalls { get; set; }
        public double AvgLatencyMs { get; set; }
        public double FlagRate { get; set; }
        public double ErrorRate { get; set; }
    }

    public class TaskTelemetryResponse
    {
        public string Task { get; set; } = string.Empty;
        public long Calls { get; set; }
        public double AvgLatencyMs { get; set; }
        public double P95LatencyMs { get; set; }
        public double ErrorRate { get; set; }
    }

    public class TelemetryResponse
    {
        public string Range { get; set; } = string.Empty;
        public long TotalCalls { get; set; }
        public double AvgLatencyMs { get; set; }
        public double P95LatencyMs { get; set; }
        public double FlagRate { get; set; }
        public double ErrorRate { get; set; }
        public long TotalTokens { get; set; }
        public TelemetryDelta Delta { get; set; } = new();
        public List<TaskTelemetryResponse> ByTask { get; set; } = new();
    }

    public class AiLogLabelResponse
    {
        public string Verdict { get; set; } = string.Empty;
        public string? Note { get; set; }
        public string By { get; set; } = string.Empty;
        public DateTime At { get; set; }
    }

    public class AiLogResponse
    {
        public string Id { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public string Task { get; set; } = string.Empty;
        public string Model { get; set; } = string.Empty;
        public long LatencyMs { get; set; }
        public int InputTokens { get; set; }
        public int OutputTokens { get; set; }
        public string Status { get; set; } = string.Empty;
        public string Detail { get; set; } = string.Empty;
        public string TraceId { get; set; } = string.Empty;
        public bool Flagged { get; set; }
        public string? RefType { get; set; }
        public string? RefId { get; set; }

        /// <summary>null: GeminiClient hiện không lưu nội dung hỏi đáp vào AiLogs.</summary>
        public string? InputText { get; set; }
        public string? OutputText { get; set; }
        public AiLogLabelResponse? Label { get; set; }
    }

    public class LabelAiLogRequest
    {
        public string? Verdict { get; set; }
        public string? Note { get; set; }
    }

    public class AiModelResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Task { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string ActiveVersion { get; set; } = string.Empty;
        public List<string> AvailableVersions { get; set; } = new();
        public bool Enabled { get; set; }
        public double? Threshold { get; set; }
        public string Fallback { get; set; } = string.Empty;
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }

        /// <summary>false: giá trị này được lưu nhưng tác vụ AI khi chạy chưa đọc nó.</summary>
        public bool RuntimeEnforced { get; set; }
    }

    public class PatchAiModelRequest
    {
        public bool? Enabled { get; set; }
        public double? Threshold { get; set; }
        public string? ActiveVersion { get; set; }
        public string? Note { get; set; }
    }

    public class ModerationCategoryMetric
    {
        public string Category { get; set; } = string.Empty;
        public int Decided { get; set; }
        public double Precision { get; set; }
    }

    public class ModerationMetrics
    {
        public int Decided { get; set; }
        public int Confirmed { get; set; }
        public int Overridden { get; set; }
        public double Precision { get; set; }
        public double OverrideRate { get; set; }
        public long Pending { get; set; }
        public double MedianDecisionMinutes { get; set; }
        public List<ModerationCategoryMetric> ByCategory { get; set; } = new();
    }

    public class LabeledMetric
    {
        public string Task { get; set; } = string.Empty;
        public int Labeled { get; set; }
        public int Correct { get; set; }
        public double? Accuracy { get; set; }
    }

    public class AiMetricsResponse
    {
        public string Range { get; set; } = string.Empty;
        public ModerationMetrics Moderation { get; set; } = new();
        public List<LabeledMetric> Labeled { get; set; } = new();
    }
}
