using DomainLayer.Entities;
using Microsoft.Extensions.Configuration;
using MongoDB.Driver;

namespace InfrastructureLayer.Database
{
    /// <summary>
    /// DB RAG riêng. Không có tên mặc định: thiếu RagDatabaseName, hoặc trùng DB chính,
    /// thì RAG tắt và API trả 503, chứ không tự ghi vào một DB đoán tên.
    /// </summary>
    public class RagDbContext
    {
        private readonly IMongoDatabase? _database;

        public RagDbContext(IConfiguration configuration)
        {
            var name = configuration["RagDatabaseName"];
            var mainName = configuration["DatabaseName"];
            if (string.IsNullOrWhiteSpace(name) || string.Equals(name, mainName, System.StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var client = new MongoClient(configuration.GetConnectionString("MongoConnection"));
            _database = client.GetDatabase(name);
        }

        public bool IsConfigured => _database != null;

        private IMongoDatabase Db => _database ?? throw new System.InvalidOperationException("RagDatabaseName chưa được cấu hình.");

        public IMongoCollection<KnowledgeDoc> Docs => Db.GetCollection<KnowledgeDoc>("knowledge_docs");
        public IMongoCollection<KnowledgeChunk> Chunks => Db.GetCollection<KnowledgeChunk>("knowledge_chunks");
        public IMongoCollection<IngestionJob> Jobs => Db.GetCollection<IngestionJob>("ingestion_jobs");
    }
}
