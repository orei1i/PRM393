using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Database;
using MongoDB.Bson;
using MongoDB.Driver;

namespace InfrastructureLayer.Repository
{
    public class KnowledgeRepository : IKnowledgeRepository
    {
        private readonly RagDbContext _context;

        public KnowledgeRepository(RagDbContext context)
        {
            _context = context;
        }

        public bool IsConfigured => _context.IsConfigured;

        public async Task<KnowledgeDoc> CreateDocAsync(KnowledgeDoc doc)
        {
            await _context.Docs.InsertOneAsync(doc);
            return doc;
        }

        public async Task<KnowledgeDoc?> GetDocAsync(string id)
        {
            if (!ObjectId.TryParse(id, out _)) return null;
            return await _context.Docs.Find(d => d.Id == id && !d.IsDeleted).FirstOrDefaultAsync();
        }

        public async Task<KnowledgeDoc?> FindByHashAsync(string contentHash)
        {
            return await _context.Docs.Find(d => d.ContentHash == contentHash && !d.IsDeleted).FirstOrDefaultAsync();
        }

        public async Task<List<KnowledgeDoc>> ListDocsAsync(string? status, string? source, string? search, string? chefId)
        {
            var filter = Builders<KnowledgeDoc>.Filter.Eq(d => d.IsDeleted, false);
            if (!string.IsNullOrWhiteSpace(status)) filter &= Builders<KnowledgeDoc>.Filter.Eq(d => d.Status, status);
            if (!string.IsNullOrWhiteSpace(source)) filter &= Builders<KnowledgeDoc>.Filter.Eq(d => d.Source, source);
            if (!string.IsNullOrWhiteSpace(chefId)) filter &= Builders<KnowledgeDoc>.Filter.Eq(d => d.ChefId, chefId);
            if (!string.IsNullOrWhiteSpace(search))
            {
                filter &= Builders<KnowledgeDoc>.Filter.Regex(d => d.Title, new BsonRegularExpression(Regex.Escape(search.Trim()), "i"));
            }

            var projection = Builders<KnowledgeDoc>.Projection.Exclude(d => d.Content);
            return await _context.Docs.Find(filter).Project<KnowledgeDoc>(projection).SortByDescending(d => d.CreatedAt).ToListAsync();
        }

        public async Task<Dictionary<string, long>> CountByStatusAsync()
        {
            var rows = await _context.Docs.Aggregate()
                .Match(d => !d.IsDeleted)
                .Group(d => d.Status, g => new { Status = g.Key, Count = g.LongCount() })
                .ToListAsync();
            return rows.ToDictionary(r => r.Status, r => r.Count);
        }

        public async Task UpdateDocAsync(KnowledgeDoc doc)
        {
            doc.UpdatedAt = DateTime.UtcNow;
            await _context.Docs.ReplaceOneAsync(d => d.Id == doc.Id, doc);
        }

        public async Task<bool> TryDecideAsync(string id, string fromStatus, string toStatus, string? note, string reviewedBy, DateTime reviewedAt)
        {
            var update = Builders<KnowledgeDoc>.Update
                .Set(d => d.Status, toStatus)
                .Set(d => d.ReviewNote, note)
                .Set(d => d.ReviewedBy, reviewedBy)
                .Set(d => d.ReviewedAt, reviewedAt)
                .Set(d => d.UpdatedAt, reviewedAt);
            var result = await _context.Docs.UpdateOneAsync(d => d.Id == id && d.Status == fromStatus && !d.IsDeleted, update);
            return result.ModifiedCount == 1;
        }

        public async Task ReplaceChunksAsync(string docId, List<KnowledgeChunk> chunks)
        {
            await _context.Chunks.DeleteManyAsync(c => c.DocId == docId);
            if (chunks.Count > 0) await _context.Chunks.InsertManyAsync(chunks);
        }

        public async Task<List<KnowledgeChunk>> GetChunksAsync(string docId, int? limit = null)
        {
            var find = _context.Chunks.Find(c => c.DocId == docId).SortBy(c => c.ChunkIndex);
            return limit.HasValue ? await find.Limit(limit.Value).ToListAsync() : await find.ToListAsync();
        }

        public async Task SaveEmbeddingsAsync(IEnumerable<KnowledgeChunk> chunks)
        {
            var writes = chunks.Select(c => new UpdateOneModel<KnowledgeChunk>(
                Builders<KnowledgeChunk>.Filter.Eq(x => x.Id, c.Id),
                Builders<KnowledgeChunk>.Update.Set(x => x.Embedding, c.Embedding))).ToList<WriteModel<KnowledgeChunk>>();
            if (writes.Count > 0) await _context.Chunks.BulkWriteAsync(writes);
        }

        public async Task DeleteChunksAsync(string docId)
        {
            await _context.Chunks.DeleteManyAsync(c => c.DocId == docId);
        }

        public async Task<List<KnowledgeDoc>> GetApprovedDocsAsync(IEnumerable<string>? ids = null)
        {
            var filter = Builders<KnowledgeDoc>.Filter.Eq(d => d.IsDeleted, false)
                         & Builders<KnowledgeDoc>.Filter.Eq(d => d.Status, KnowledgeDocStatuses.Approved);
            if (ids != null) filter &= Builders<KnowledgeDoc>.Filter.In(d => d.Id, ids);
            var projection = Builders<KnowledgeDoc>.Projection.Exclude(d => d.Content);
            return await _context.Docs.Find(filter).Project<KnowledgeDoc>(projection).ToListAsync();
        }

        public async Task IncrementCitationAsync(string docId)
        {
            await _context.Docs.UpdateOneAsync(d => d.Id == docId, Builders<KnowledgeDoc>.Update.Inc(d => d.CitationCount, 1));
        }

        public async Task<IngestionJob> CreateJobAsync(string docId)
        {
            var job = new IngestionJob { DocId = docId };
            await _context.Jobs.InsertOneAsync(job);
            return job;
        }

        public async Task FinishJobAsync(string jobId, string status, string? error)
        {
            var update = Builders<IngestionJob>.Update
                .Set(j => j.Status, status)
                .Set(j => j.Error, error)
                .Set(j => j.FinishedAt, DateTime.UtcNow);
            await _context.Jobs.UpdateOneAsync(j => j.Id == jobId, update);
        }
    }

    public class ChatStore : IChatStore
    {
        private readonly MongoDbContext _context;

        public ChatStore(MongoDbContext context)
        {
            _context = context;
        }

        public async Task<ChatSession> GetOrCreateSessionAsync(string ownerKey, string clientSessionId, string? userId)
        {
            var filter = Builders<ChatSession>.Filter.Eq(s => s.OwnerKey, ownerKey)
                         & Builders<ChatSession>.Filter.Eq(s => s.ClientSessionId, clientSessionId);
            var update = Builders<ChatSession>.Update
                .SetOnInsert(s => s.UserId, userId)
                .SetOnInsert(s => s.StartedAt, DateTime.UtcNow)
                .SetOnInsert(s => s.CreatedAt, DateTime.UtcNow)
                .SetOnInsert(s => s.IsDeleted, false);
            var options = new FindOneAndUpdateOptions<ChatSession> { IsUpsert = true, ReturnDocument = ReturnDocument.After };

            try
            {
                return await _context.ChatSessions.FindOneAndUpdateAsync(filter, update, options);
            }
            catch (MongoCommandException ex) when (ex.Code == 11000)
            {
                return await _context.ChatSessions.Find(filter).FirstAsync();
            }
        }

        public async Task<ChatSession?> FindSessionAsync(string ownerKey, string clientSessionId)
        {
            return await _context.ChatSessions.Find(s => s.OwnerKey == ownerKey && s.ClientSessionId == clientSessionId).FirstOrDefaultAsync();
        }

        public async Task<bool> TryConsumeGuestTrialAsync(string guestKey, int limit)
        {
            var filter = Builders<GuestTrial>.Filter.Eq(g => g.GuestKey, guestKey)
                         & Builders<GuestTrial>.Filter.Lt(g => g.Used, limit);
            var update = Builders<GuestTrial>.Update.Inc(g => g.Used, 1);

            // Không dùng upsert: hai câu hỏi đầu tiên chạy đua sẽ đụng khoá trùng dù còn lượt.
            while (true)
            {
                var result = await _context.GuestTrials.UpdateOneAsync(filter, update);
                if (result.ModifiedCount == 1) return true;

                var row = await _context.GuestTrials.Find(g => g.GuestKey == guestKey).FirstOrDefaultAsync();
                if (row != null)
                {
                    if (row.Used >= limit) return false;

                    // Yêu cầu khác vừa tạo dòng này sau lần trừ ở trên: vẫn còn lượt, trừ lại.
                    continue;
                }

                try
                {
                    await _context.GuestTrials.InsertOneAsync(new GuestTrial { GuestKey = guestKey, Used = 1 });
                    return true;
                }
                catch (MongoWriteException ex) when (ex.WriteError?.Category == ServerErrorCategory.DuplicateKey)
                {
                    // Yêu cầu khác vừa tạo dòng này: quay lại trừ trên dòng đó.
                }
            }
        }

        public async Task<int> GetGuestTrialUsedAsync(string guestKey)
        {
            var row = await _context.GuestTrials.Find(g => g.GuestKey == guestKey).FirstOrDefaultAsync();
            return row?.Used ?? 0;
        }
    }
}
