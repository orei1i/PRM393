using System;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class HealthMetricLog : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public double WeightKg { get; set; }

        public double HeightCm { get; set; }

        public double Bmi { get; set; }

        public double? WaistCm { get; set; }

        public double? BodyFatPct { get; set; }

        public DateTime LoggedAt { get; set; } = DateTime.UtcNow;
    }
}
