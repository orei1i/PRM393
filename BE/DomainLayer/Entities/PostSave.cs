using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    /// <summary>Bài viết người dùng đã lưu. Bỏ lưu là xoá mềm, nên mỗi cặp bài và người chỉ có một dòng.</summary>
    public class PostSave : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string PostId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;
    }
}
