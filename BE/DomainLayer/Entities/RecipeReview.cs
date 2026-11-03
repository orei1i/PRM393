using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>Đánh giá công thức: mỗi người một dòng trên một công thức.</summary>
    public class RecipeReview : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string RecipeId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public int Rating { get; set; }

        public string? Content { get; set; }
    }

    /// <summary>Ghi chú riêng của một người trên một công thức.</summary>
    public class RecipeNote : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string RecipeId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public string Content { get; set; } = string.Empty;
    }
}
