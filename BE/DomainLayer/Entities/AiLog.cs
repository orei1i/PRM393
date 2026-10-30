using System;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class AiLog : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        [BsonIgnoreIfNull]
        public string? UserId { get; set; }

        /// <summary>
        /// "Vision", "VideoRecipe", "Chat", "MealPlanAdjust", "MealPlanGenerate"
        /// </summary>
        public string TaskType { get; set; } = "Vision";

        public string Model { get; set; } = "gemini-2.0-flash";

        [BsonIgnoreIfNull]
        public string? ScanId { get; set; }

        public int PromptTokens { get; set; }

        public int CandidatesTokens { get; set; }

        public long LatencyMs { get; set; }

        public bool Success { get; set; } = true;

        [BsonIgnoreIfNull]
        public string? ErrorMessage { get; set; }
    }
}

