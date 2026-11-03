using System;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>Kết quả trích xuất công thức từ một bài viết có video. Mỗi bài một dòng.</summary>
    public class VideoExtraction : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string PostId { get; set; } = string.Empty;

        /// <summary>queued | transcribing | extracting | ready | failed</summary>
        public string Status { get; set; } = VideoAiStatuses.Queued;

        public string? Summary { get; set; }
        public int? Servings { get; set; }
        public int? TotalMinutes { get; set; }
        public int? KcalPerServing { get; set; }
        public List<VideoIngredient> Ingredients { get; set; } = new();
        public List<VideoStep> Steps { get; set; } = new();
        public List<VideoTranscriptLine> Transcript { get; set; } = new();
        public string? FailureReason { get; set; }
        public int Attempts { get; set; }
    }

    public class VideoIngredient
    {
        public string Name { get; set; } = string.Empty;
        public string Quantity { get; set; } = string.Empty;
        public int? AtSecond { get; set; }
        public bool Uncertain { get; set; }
    }

    public class VideoStep
    {
        public int Index { get; set; }
        public string Text { get; set; } = string.Empty;
        public int? AtSecond { get; set; }
    }

    public class VideoTranscriptLine
    {
        public int AtSecond { get; set; }
        public string Text { get; set; } = string.Empty;
    }

    public static class VideoAiStatuses
    {
        public const string Queued = "queued";
        public const string Transcribing = "transcribing";
        public const string Extracting = "extracting";
        public const string Ready = "ready";
        public const string Failed = "failed";
    }
}
