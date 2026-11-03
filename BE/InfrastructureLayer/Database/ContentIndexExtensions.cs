using System;
using System.Collections.Concurrent;
using System.Threading.Tasks;
using DomainLayer.Entities;
using InfrastructureLayer.Repository;
using Microsoft.Extensions.Logging;
using MongoDB.Driver;

namespace InfrastructureLayer.Database
{
    /// <summary>Chỉ mục của chuyên gia, quán ăn, quảng cáo, video và trang quản trị.</summary>
    public static class ContentIndexExtensions
    {
        private static readonly ConcurrentDictionary<string, Lazy<Task<bool>>> Ensured = new();

        /// <summary>
        /// Gọi trước lần ghi đầu tiên của mỗi tiến trình. Chống trùng dựa vào chỉ mục unique, mà bước khởi động có thể bỏ qua
        /// khi Mongo phản hồi chậm; chỉ mục đã có thì lệnh tạo không làm gì. Lần nào lỗi thì lần ghi sau thử lại.
        /// </summary>
        public static async Task EnsureContentIndexesOnceAsync(this MongoDbContext db)
        {
            var key = db.Database.DatabaseNamespace.DatabaseName;
            var pending = Ensured.GetOrAdd(key, _ => new Lazy<Task<bool>>(() => db.EnsureContentIndexesAsync(null)));
            if (!await pending.Value) Ensured.TryRemove(key, out _);
        }

        /// <returns>true khi mọi chỉ mục đều đã có.</returns>
        public static async Task<bool> EnsureContentIndexesAsync(this MongoDbContext db, ILogger? logger)
        {
            var ok = true;
            ok &= await Safe(async () =>
            {
                await db.ChefProfiles().Indexes.CreateOneAsync(new CreateIndexModel<ChefProfile>(
                    Builders<ChefProfile>.IndexKeys.Ascending(p => p.UserId), new CreateIndexOptions { Unique = true }));
                await db.ChefApplications().Indexes.CreateManyAsync(new[]
                {
                    new CreateIndexModel<ChefApplication>(
                        Builders<ChefApplication>.IndexKeys.Ascending(a => a.UserId),
                        new CreateIndexOptions<ChefApplication>
                        {
                            Unique = true,
                            PartialFilterExpression = Builders<ChefApplication>.Filter.Eq(a => a.Status, ChefApplicationStatuses.Pending)
                        }),
                    new CreateIndexModel<ChefApplication>(
                        Builders<ChefApplication>.IndexKeys.Ascending(a => a.Status).Descending(a => a.CreatedAt))
                });
            }, "ChefProfiles, ChefApplications", logger);

            ok &= await Safe(async () =>
            {
                await db.Restaurants().Indexes.CreateManyAsync(new[]
                {
                    new CreateIndexModel<Restaurant>(Builders<Restaurant>.IndexKeys.Ascending(r => r.Status)),
                    new CreateIndexModel<Restaurant>(Builders<Restaurant>.IndexKeys.Ascending(r => r.CreatedBy)),
                    new CreateIndexModel<Restaurant>(Builders<Restaurant>.IndexKeys.Ascending(r => r.DedupeKey),
                        new CreateIndexOptions { Unique = true, Sparse = true })
                });
                await db.RestaurantReviews().Indexes.CreateOneAsync(new CreateIndexModel<RestaurantReview>(
                    Builders<RestaurantReview>.IndexKeys.Ascending(v => v.RestaurantId).Ascending(v => v.UserId),
                    new CreateIndexOptions<RestaurantReview>
                    {
                        Unique = true,
                        PartialFilterExpression = Builders<RestaurantReview>.Filter.Eq(v => v.IsDeleted, false)
                    }));
            }, "Restaurants, RestaurantReviews", logger);

            ok &= await Safe(() => db.AdCampaigns().Indexes.CreateOneAsync(new CreateIndexModel<AdCampaign>(
                Builders<AdCampaign>.IndexKeys.Ascending(a => a.Placement).Ascending(a => a.EndAt))), "AdCampaigns", logger);

            ok &= await Safe(async () =>
            {
                await db.VideoExtractions().Indexes.CreateManyAsync(new[]
                {
                    new CreateIndexModel<VideoExtraction>(Builders<VideoExtraction>.IndexKeys.Ascending(v => v.PostId), new CreateIndexOptions { Unique = true }),
                    new CreateIndexModel<VideoExtraction>(Builders<VideoExtraction>.IndexKeys.Ascending(v => v.Status).Ascending(v => v.UpdatedAt))
                });
            }, "VideoExtractions", logger);

            ok &= await Safe(async () =>
            {
                await db.CatalogItems().Indexes.CreateOneAsync(new CreateIndexModel<CatalogItem>(
                    Builders<CatalogItem>.IndexKeys.Ascending(c => c.Kind).Ascending(c => c.Code),
                    new CreateIndexOptions<CatalogItem>
                    {
                        Unique = true,
                        PartialFilterExpression = Builders<CatalogItem>.Filter.Eq(c => c.IsDeleted, false)
                    }));
                await db.ModerationFlags().Indexes.CreateOneAsync(new CreateIndexModel<ModerationFlag>(
                    Builders<ModerationFlag>.IndexKeys.Ascending(x => x.Status).Descending(x => x.CreatedAt)));
                await db.AdminAuditLogs().Indexes.CreateOneAsync(new CreateIndexModel<AdminAuditLog>(
                    Builders<AdminAuditLog>.IndexKeys.Descending(x => x.CreatedAt)));
                await db.AiLogLabels().Indexes.CreateOneAsync(new CreateIndexModel<AiLogLabel>(
                    Builders<AiLogLabel>.IndexKeys.Ascending(l => l.LogId), new CreateIndexOptions { Unique = true }));
                await db.AiModelConfigs().Indexes.CreateOneAsync(new CreateIndexModel<AiModelConfig>(
                    Builders<AiModelConfig>.IndexKeys.Ascending(m => m.Task), new CreateIndexOptions { Unique = true }));
            }, "Catalog, moderation, AI admin", logger);
            return ok;
        }

        private static async Task<bool> Safe(Func<Task> action, string name, ILogger? logger)
        {
            try
            {
                await action();
                return true;
            }
            catch (Exception ex)
            {
                logger?.LogWarning("Lỗi khi tạo chỉ mục {IndexName} ({ErrorType}). Tiếp tục tạo các chỉ mục khác.", name, ex.GetType().Name);
                return false;
            }
        }
    }
}
