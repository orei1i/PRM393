using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class MediaAsset : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string OwnerId { get; set; } = string.Empty;

        public string PublicId { get; set; } = string.Empty;

        public string Url { get; set; } = string.Empty;

        public string MediaType { get; set; } = "Image"; // "Image" | "Video"

        public long SizeBytes { get; set; }

        public int? DurationSeconds { get; set; }

        public int? Width { get; set; }

        public int? Height { get; set; }
    }
}
