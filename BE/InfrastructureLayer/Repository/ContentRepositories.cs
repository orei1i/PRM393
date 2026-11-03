using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Database;
using MongoDB.Bson;
using MongoDB.Driver;

namespace InfrastructureLayer.Repository
{
    internal static class MongoErrors
    {
        public static bool IsDuplicateKey(Exception ex) => ex switch
        {
            MongoWriteException write => write.WriteError?.Category == ServerErrorCategory.DuplicateKey,
            MongoCommandException command => command.Code == 11000,
            _ => false
        };
    }

    public static class ContentCollections
    {
        public static IMongoCollection<ChefProfile> ChefProfiles(this MongoDbContext db) => db.Database.GetCollection<ChefProfile>("ChefProfiles");
        public static IMongoCollection<ChefApplication> ChefApplications(this MongoDbContext db) => db.Database.GetCollection<ChefApplication>("ChefApplications");
        public static IMongoCollection<Restaurant> Restaurants(this MongoDbContext db) => db.Database.GetCollection<Restaurant>("Restaurants");
        public static IMongoCollection<RestaurantReview> RestaurantReviews(this MongoDbContext db) => db.Database.GetCollection<RestaurantReview>("RestaurantReviews");
        public static IMongoCollection<AdCampaign> AdCampaigns(this MongoDbContext db) => db.Database.GetCollection<AdCampaign>("AdCampaigns");
        public static IMongoCollection<VideoExtraction> VideoExtractions(this MongoDbContext db) => db.Database.GetCollection<VideoExtraction>("VideoExtractions");
        public static IMongoCollection<CatalogItem> CatalogItems(this MongoDbContext db) => db.Database.GetCollection<CatalogItem>("CatalogItems");
        public static IMongoCollection<ModerationFlag> ModerationFlags(this MongoDbContext db) => db.Database.GetCollection<ModerationFlag>("ModerationFlags");
        public static IMongoCollection<AdminAuditLog> AdminAuditLogs(this MongoDbContext db) => db.Database.GetCollection<AdminAuditLog>("AdminAuditLogs");
        public static IMongoCollection<AiLogLabel> AiLogLabels(this MongoDbContext db) => db.Database.GetCollection<AiLogLabel>("AiLogLabels");
        public static IMongoCollection<AiModelConfig> AiModelConfigs(this MongoDbContext db) => db.Database.GetCollection<AiModelConfig>("AiModelConfigs");
    }

    public class ChefRepository : IChefRepository
    {
        private readonly MongoDbContext _db;

        public ChefRepository(MongoDbContext db)
        {
            _db = db;
        }

        public async Task<bool> TryInsertApplicationAsync(ChefApplication application)
        {
            await _db.EnsureContentIndexesOnceAsync();
            try
            {
                await _db.ChefApplications().InsertOneAsync(application);
                return true;
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                return false;
            }
        }

        public async Task<ChefApplication?> TryDecideApplicationAsync(string id, string status, string? note, string reviewer, DateTime at)
        {
            var filter = Builders<ChefApplication>.Filter.Where(a => a.Id == id && !a.IsDeleted && a.Status == ChefApplicationStatuses.Pending);
            var update = Builders<ChefApplication>.Update
                .Set(a => a.Status, status)
                .Set(a => a.ReviewNote, note)
                .Set(a => a.ReviewedBy, reviewer)
                .Set(a => a.ReviewedAt, at)
                .Set(a => a.UpdatedAt, at);
            return await _db.ChefApplications().FindOneAndUpdateAsync(filter, update,
                new FindOneAndUpdateOptions<ChefApplication> { ReturnDocument = ReturnDocument.After });
        }

        public Task RevertToPendingAsync(string id) => _db.ChefApplications().UpdateOneAsync(
            a => a.Id == id,
            Builders<ChefApplication>.Update
                .Set(a => a.Status, ChefApplicationStatuses.Pending)
                .Set(a => a.ReviewNote, null)
                .Set(a => a.ReviewedBy, null)
                .Set(a => a.ReviewedAt, null));

        public async Task CreateProfileIfMissingAsync(ChefProfile profile)
        {
            await _db.EnsureContentIndexesOnceAsync();
            try
            {
                await _db.ChefProfiles().InsertOneAsync(profile);
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                // Đã có hồ sơ từ trước: giữ nguyên giá và mô tả.
            }
        }

        public async Task<ChefProfile> UpsertProfileAsync(ChefProfile values, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            var update = Builders<ChefProfile>.Update
                .Set(p => p.Specialty, values.Specialty)
                .Set(p => p.Bio, values.Bio)
                .Set(p => p.PricePerDay, values.PricePerDay)
                .Set(p => p.FeedbackPricePerDay, values.FeedbackPricePerDay)
                .Set(p => p.MinPlanDays, values.MinPlanDays)
                .Set(p => p.MaxPlanDays, values.MaxPlanDays)
                .Set(p => p.AcceptingBookings, values.AcceptingBookings)
                .Set(p => p.UpdatedAt, at)
                .SetOnInsert(p => p.CreatedAt, at)
                .SetOnInsert(p => p.IsDeleted, false);
            var options = new FindOneAndUpdateOptions<ChefProfile> { IsUpsert = true, ReturnDocument = ReturnDocument.After };
            var filter = Builders<ChefProfile>.Filter.Eq(p => p.UserId, values.UserId);
            try
            {
                return await _db.ChefProfiles().FindOneAndUpdateAsync(filter, update, options);
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                // Hai lần lưu đồng thời cùng chèn: lần này đã có dòng để sửa.
                return await _db.ChefProfiles().FindOneAndUpdateAsync(filter, update, options);
            }
        }

        public Task GrantChefRoleAsync(string userId, DateTime at) => _db.Users.UpdateOneAsync(
            u => u.Id == userId && u.Role != "Admin",
            Builders<User>.Update.Set(u => u.Role, "Chef").Set(u => u.UpdatedAt, at));

        public async Task<Dictionary<string, ChefStats>> GetStatsAsync(IReadOnlyCollection<string> chefUserIds)
        {
            var result = new Dictionary<string, ChefStats>();
            if (chefUserIds.Count == 0) return result;

            var rows = await _db.Bookings
                .Find(Builders<ChefBooking>.Filter.In(b => b.ChefId, chefUserIds))
                .Project(Builders<ChefBooking>.Projection.Include(b => b.ChefId).Include(b => b.Status).Include("Days.Feedback.Rating"))
                .ToListAsync();

            foreach (var group in rows.GroupBy(r => r["ChefId"].AsString))
            {
                var ratings = new List<int>();
                var completed = 0;
                foreach (var row in group)
                {
                    if (row.GetValue("Status", BsonNull.Value).ToString() == BookingStatuses.Completed) completed++;
                    if (!row.TryGetValue("Days", out var days) || !days.IsBsonArray) continue;
                    foreach (var day in days.AsBsonArray)
                    {
                        if (day.IsBsonDocument
                            && day.AsBsonDocument.TryGetValue("Feedback", out var feedback) && feedback.IsBsonDocument
                            && feedback.AsBsonDocument.TryGetValue("Rating", out var rating) && rating.IsInt32)
                        {
                            ratings.Add(rating.AsInt32);
                        }
                    }
                }
                result[group.Key] = new ChefStats(ratings.Count == 0 ? 0 : Math.Round(ratings.Average(), 1), ratings.Count, completed);
            }
            return result;
        }
    }

    public class RestaurantRepository : IRestaurantRepository
    {
        private readonly MongoDbContext _db;

        public RestaurantRepository(MongoDbContext db)
        {
            _db = db;
        }

        public async Task<bool> TryInsertAsync(Restaurant restaurant)
        {
            await _db.EnsureContentIndexesOnceAsync();
            try
            {
                await _db.Restaurants().InsertOneAsync(restaurant);
                return true;
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                return false;
            }
        }

        public async Task<(Restaurant? Row, bool Duplicate)> DecideAsync(string id, string status, string? reason, string? dedupeKey, string reviewer, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            var update = Builders<Restaurant>.Update
                .Set(r => r.Status, status)
                .Set(r => r.RejectionReason, reason)
                .Set(r => r.ReviewedAt, at)
                .Set(r => r.ReviewedBy, reviewer)
                .Set(r => r.UpdatedAt, at);
            // Chỉ mục sparse vẫn tính giá trị null là một giá trị, nên phải bỏ hẳn trường.
            update = dedupeKey == null ? update.Unset(r => r.DedupeKey) : update.Set(r => r.DedupeKey, dedupeKey);
            if (status == RestaurantStatuses.Rejected) update = update.Set(r => r.IsVeganCertified, false);

            try
            {
                var row = await _db.Restaurants().FindOneAndUpdateAsync<Restaurant>(r => r.Id == id && !r.IsDeleted, update,
                    new FindOneAndUpdateOptions<Restaurant> { ReturnDocument = ReturnDocument.After });
                return (row, false);
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                return (null, true);
            }
        }

        public async Task<Restaurant?> SetCertifiedIfApprovedAsync(string id, bool value, DateTime at) =>
            await _db.Restaurants().FindOneAndUpdateAsync<Restaurant>(
                r => r.Id == id && !r.IsDeleted && r.Status == RestaurantStatuses.Approved,
                Builders<Restaurant>.Update.Set(r => r.IsVeganCertified, value).Set(r => r.UpdatedAt, at),
                new FindOneAndUpdateOptions<Restaurant> { ReturnDocument = ReturnDocument.After });

        public async Task<bool> SoftDeleteAsync(string id, DateTime at)
        {
            var result = await _db.Restaurants().UpdateOneAsync(r => r.Id == id && !r.IsDeleted,
                Builders<Restaurant>.Update.Set(r => r.IsDeleted, true).Set(r => r.DeletedAt, at).Set(r => r.UpdatedAt, at).Unset(r => r.DedupeKey));
            if (result.ModifiedCount == 0) return false;
            await _db.RestaurantReviews().UpdateManyAsync(v => v.RestaurantId == id && !v.IsDeleted,
                Builders<RestaurantReview>.Update.Set(v => v.IsDeleted, true).Set(v => v.DeletedAt, at));
            return true;
        }

        public async Task<RestaurantReview> UpsertReviewAsync(string restaurantId, string userId, int rating, string comment, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            var reviews = _db.RestaurantReviews();
            async Task<RestaurantReview?> UpdateExistingAsync() => await reviews.FindOneAndUpdateAsync<RestaurantReview>(
                v => v.RestaurantId == restaurantId && v.UserId == userId && !v.IsDeleted,
                Builders<RestaurantReview>.Update.Set(v => v.Rating, rating).Set(v => v.Comment, comment).Set(v => v.UpdatedAt, at),
                new FindOneAndUpdateOptions<RestaurantReview> { ReturnDocument = ReturnDocument.After });

            var existing = await UpdateExistingAsync();
            if (existing != null) return existing;

            var review = new RestaurantReview
            {
                Id = ObjectId.GenerateNewId().ToString(),
                RestaurantId = restaurantId,
                UserId = userId,
                Rating = rating,
                Comment = comment,
                CreatedAt = at
            };
            try
            {
                await reviews.InsertOneAsync(review);
                return review;
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                // Bấm đúp: lần kia đã chèn trước.
                return await UpdateExistingAsync() ?? review;
            }
        }

        public async Task<bool> SoftDeleteReviewAsync(string id, DateTime at)
        {
            var result = await _db.RestaurantReviews().UpdateOneAsync(v => v.Id == id && !v.IsDeleted,
                Builders<RestaurantReview>.Update.Set(v => v.IsDeleted, true).Set(v => v.DeletedAt, at));
            return result.ModifiedCount > 0;
        }
    }

    public class AdRepository : IAdRepository
    {
        private readonly MongoDbContext _db;

        public AdRepository(MongoDbContext db)
        {
            _db = db;
        }

        private static FilterDefinition<AdCampaign> RunningAt(string id, DateTime now)
        {
            var f = Builders<AdCampaign>.Filter;
            return f.And(
                f.Eq(a => a.Id, id),
                f.Eq(a => a.IsDeleted, false),
                f.Eq(a => a.IsPaused, false),
                f.Lte(a => a.StartAt, now),
                f.Gte(a => a.EndAt, now),
                new BsonDocument("$expr", new BsonDocument("$lt", new BsonArray { "$Spent", "$Budget" })));
        }

        public async Task<bool> RecordImpressionAsync(string id, long cost, DateTime now)
        {
            // Pipeline để số đã tiêu và lượt hiển thị đổi cùng một lần ghi, không vượt ngân sách kể cả khi gửi đồng thời.
            var pipeline = new BsonDocument[]
            {
                new("$set", new BsonDocument
                {
                    { "Impressions", new BsonDocument("$add", new BsonArray { "$Impressions", 1L }) },
                    { "Spent", new BsonDocument("$min", new BsonArray { "$Budget", new BsonDocument("$add", new BsonArray { "$Spent", cost }) }) }
                })
            };
            var result = await _db.AdCampaigns().UpdateOneAsync(RunningAt(id, now), Builders<AdCampaign>.Update.Pipeline(pipeline));
            return result.ModifiedCount > 0;
        }

        public async Task<bool> RecordClickAsync(string id, DateTime now)
        {
            var result = await _db.AdCampaigns().UpdateOneAsync(RunningAt(id, now), Builders<AdCampaign>.Update.Inc(a => a.Clicks, 1L));
            return result.ModifiedCount > 0;
        }

        public async Task<AdCampaign?> UpdateFieldsAsync(AdCampaign values, DateTime at)
        {
            var f = Builders<AdCampaign>.Filter;
            var update = Builders<AdCampaign>.Update
                .Set(a => a.RestaurantId, values.RestaurantId)
                .Set(a => a.Placement, values.Placement)
                .Set(a => a.Headline, values.Headline)
                .Set(a => a.Message, values.Message)
                .Set(a => a.CtaType, values.CtaType)
                .Set(a => a.TargetCity, values.TargetCity)
                .Set(a => a.StartAt, values.StartAt)
                .Set(a => a.EndAt, values.EndAt)
                .Set(a => a.Budget, values.Budget)
                .Set(a => a.UpdatedAt, at);
            // Không ghi lại cả document: các bộ đếm đang tăng song song từ app.
            return await _db.AdCampaigns().FindOneAndUpdateAsync(
                f.And(f.Eq(a => a.Id, values.Id), f.Eq(a => a.IsDeleted, false), f.Lte(a => a.Spent, values.Budget)),
                update,
                new FindOneAndUpdateOptions<AdCampaign> { ReturnDocument = ReturnDocument.After });
        }

        public async Task<AdCampaign?> SetPausedAsync(string id, bool paused, DateTime at) =>
            await _db.AdCampaigns().FindOneAndUpdateAsync<AdCampaign>(a => a.Id == id && !a.IsDeleted,
                Builders<AdCampaign>.Update.Set(a => a.IsPaused, paused).Set(a => a.UpdatedAt, at),
                new FindOneAndUpdateOptions<AdCampaign> { ReturnDocument = ReturnDocument.After });
    }

    public class VideoExtractionRepository : IVideoExtractionRepository
    {
        private readonly MongoDbContext _db;

        public VideoExtractionRepository(MongoDbContext db)
        {
            _db = db;
        }

        public async Task<VideoExtraction> QueueAsync(string postId, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            var rows = _db.VideoExtractions();
            var requeued = await rows.FindOneAndUpdateAsync<VideoExtraction>(
                v => v.PostId == postId && v.Status == VideoAiStatuses.Failed,
                Builders<VideoExtraction>.Update.Set(v => v.Status, VideoAiStatuses.Queued).Set(v => v.FailureReason, null).Set(v => v.UpdatedAt, at),
                new FindOneAndUpdateOptions<VideoExtraction> { ReturnDocument = ReturnDocument.After });
            if (requeued != null) return requeued;

            var current = await rows.Find(v => v.PostId == postId).FirstOrDefaultAsync();
            if (current != null) return current;

            var created = new VideoExtraction { Id = ObjectId.GenerateNewId().ToString(), PostId = postId, Status = VideoAiStatuses.Queued, CreatedAt = at, UpdatedAt = at };
            try
            {
                await rows.InsertOneAsync(created);
                return created;
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                return await rows.Find(v => v.PostId == postId).FirstAsync();
            }
        }

        public async Task<VideoExtraction?> ClaimNextAsync(DateTime now, DateTime staleBefore)
        {
            var f = Builders<VideoExtraction>.Filter;
            var filter = f.Or(
                f.Eq(v => v.Status, VideoAiStatuses.Queued),
                f.And(f.Eq(v => v.Status, VideoAiStatuses.Extracting), f.Lt(v => v.UpdatedAt, staleBefore)));
            return await _db.VideoExtractions().FindOneAndUpdateAsync(filter,
                Builders<VideoExtraction>.Update.Set(v => v.Status, VideoAiStatuses.Extracting).Set(v => v.UpdatedAt, now).Inc(v => v.Attempts, 1),
                new FindOneAndUpdateOptions<VideoExtraction> { ReturnDocument = ReturnDocument.After, Sort = Builders<VideoExtraction>.Sort.Ascending(v => v.UpdatedAt) });
        }

        public Task CompleteAsync(VideoExtraction result, DateTime at) => _db.VideoExtractions().UpdateOneAsync(
            v => v.Id == result.Id,
            Builders<VideoExtraction>.Update
                .Set(v => v.Status, VideoAiStatuses.Ready)
                .Set(v => v.Summary, result.Summary)
                .Set(v => v.Servings, result.Servings)
                .Set(v => v.TotalMinutes, result.TotalMinutes)
                .Set(v => v.KcalPerServing, result.KcalPerServing)
                .Set(v => v.Ingredients, result.Ingredients)
                .Set(v => v.Steps, result.Steps)
                .Set(v => v.Transcript, result.Transcript)
                .Set(v => v.FailureReason, null)
                .Set(v => v.UpdatedAt, at));

        public Task FailAsync(string id, string reason, DateTime at) => _db.VideoExtractions().UpdateOneAsync(
            v => v.Id == id,
            Builders<VideoExtraction>.Update.Set(v => v.Status, VideoAiStatuses.Failed).Set(v => v.FailureReason, reason).Set(v => v.UpdatedAt, at));
    }

    public class AdminContentRepository : IAdminContentRepository
    {
        private readonly MongoDbContext _db;

        public AdminContentRepository(MongoDbContext db)
        {
            _db = db;
        }

        public async Task<bool> TryInsertCatalogItemAsync(CatalogItem item)
        {
            await _db.EnsureContentIndexesOnceAsync();
            try
            {
                await _db.CatalogItems().InsertOneAsync(item);
                return true;
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                return false;
            }
        }

        public async Task EnsureCatalogItemAsync(string kind, string code, string label, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            try
            {
                await _db.CatalogItems().UpdateOneAsync(
                    c => c.Kind == kind && c.Code == code,
                    Builders<CatalogItem>.Update
                        .SetOnInsert(c => c.Label, label)
                        .SetOnInsert(c => c.Active, true)
                        .SetOnInsert(c => c.CreatedAt, at)
                        .SetOnInsert(c => c.IsDeleted, false),
                    new UpdateOptions { IsUpsert = true });
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                // Một yêu cầu khác vừa tạo xong.
            }
        }

        public async Task<ModerationFlag?> TryDecideFlagAsync(string id, string action, string note, string decidedBy, DateTime at) =>
            await _db.ModerationFlags().FindOneAndUpdateAsync<ModerationFlag>(
                x => x.Id == id && !x.IsDeleted && x.Status != "resolved",
                Builders<ModerationFlag>.Update
                    .Set(x => x.Status, "resolved")
                    .Set(x => x.Action, action)
                    .Set(x => x.DecisionNote, note)
                    .Set(x => x.DecidedBy, decidedBy)
                    .Set(x => x.DecidedAt, at)
                    .Set(x => x.UpdatedAt, at),
                new FindOneAndUpdateOptions<ModerationFlag> { ReturnDocument = ReturnDocument.After });

        public async Task EnsureAiModelAsync(AiModelConfig defaults, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            try
            {
                await _db.AiModelConfigs().UpdateOneAsync(
                    m => m.Task == defaults.Task,
                    Builders<AiModelConfig>.Update
                        .SetOnInsert(m => m.Name, defaults.Name)
                        .SetOnInsert(m => m.ActiveVersion, defaults.ActiveVersion)
                        .SetOnInsert(m => m.AvailableVersions, defaults.AvailableVersions)
                        .SetOnInsert(m => m.Enabled, defaults.Enabled)
                        .SetOnInsert(m => m.Threshold, defaults.Threshold)
                        .SetOnInsert(m => m.Fallback, defaults.Fallback)
                        .SetOnInsert(m => m.CreatedAt, at)
                        .SetOnInsert(m => m.UpdatedAt, at)
                        .SetOnInsert(m => m.IsDeleted, false),
                    new UpdateOptions { IsUpsert = true });
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                // Một yêu cầu khác vừa tạo xong.
            }
        }

        public async Task<AiLogLabel> UpsertLogLabelAsync(string logId, string verdict, string? note, string by, DateTime at)
        {
            await _db.EnsureContentIndexesOnceAsync();
            var update = Builders<AiLogLabel>.Update
                .Set(l => l.Verdict, verdict)
                .Set(l => l.Note, note)
                .Set(l => l.By, by)
                .Set(l => l.At, at)
                .SetOnInsert(l => l.CreatedAt, at)
                .SetOnInsert(l => l.IsDeleted, false);
            var options = new FindOneAndUpdateOptions<AiLogLabel> { IsUpsert = true, ReturnDocument = ReturnDocument.After };
            var filter = Builders<AiLogLabel>.Filter.Eq(l => l.LogId, logId);
            try
            {
                return await _db.AiLogLabels().FindOneAndUpdateAsync(filter, update, options);
            }
            catch (Exception ex) when (MongoErrors.IsDuplicateKey(ex))
            {
                return await _db.AiLogLabels().FindOneAndUpdateAsync(filter, update, options);
            }
        }
    }
}
