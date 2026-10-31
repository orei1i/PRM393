using System;
using System.Threading.Tasks;
using DomainLayer.Entities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using MongoDB.Driver;

namespace InfrastructureLayer.Database
{
    public static class MongoDbIndexExtensions
    {
        public static async Task EnsureIndexesAsync(this IServiceProvider services)
        {
            using var scope = services.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<MongoDbContext>();
            var logger = scope.ServiceProvider.GetService<ILogger<MongoDbContext>>();

            try
            {
                using var pingCts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(2));
                await context.Database.RunCommandAsync((Command<MongoDB.Bson.BsonDocument>)"{ping:1}", cancellationToken: pingCts.Token);
            }
            catch
            {
                logger?.LogWarning("MongoDB không phản hồi ping trong 2s. Bỏ qua khởi tạo chỉ mục.");
                return;
            }

            try
            {
                // 1. MediaAssets
                var mediaPublicIdIndex = new CreateIndexModel<MediaAsset>(
                    Builders<MediaAsset>.IndexKeys.Ascending(m => m.PublicId),
                    new CreateIndexOptions { Unique = true, Sparse = true });
                var mediaOwnerIndex = new CreateIndexModel<MediaAsset>(
                    Builders<MediaAsset>.IndexKeys.Ascending(m => m.OwnerId).Descending(m => m.CreatedAt));
                await context.MediaAssets.Indexes.CreateManyAsync(new[] { mediaPublicIdIndex, mediaOwnerIndex });

                // 2. Posts
                var postStatusIndex = new CreateIndexModel<Post>(
                    Builders<Post>.IndexKeys.Ascending(p => p.Status).Descending(p => p.CreatedAt));
                var postUserIndex = new CreateIndexModel<Post>(
                    Builders<Post>.IndexKeys.Ascending(p => p.UserId).Descending(p => p.CreatedAt));
                await context.Posts.Indexes.CreateManyAsync(new[] { postStatusIndex, postUserIndex });

                // 3. Comments
                var commentPostIndex = new CreateIndexModel<Comment>(
                    Builders<Comment>.IndexKeys.Ascending(c => c.PostId).Descending(c => c.CreatedAt));
                await context.Comments.Indexes.CreateOneAsync(commentPostIndex);

                // 4. PostLikes (Unique per user and post)
                var likeIndex = new CreateIndexModel<PostLike>(
                    Builders<PostLike>.IndexKeys.Ascending(l => l.PostId).Ascending(l => l.UserId),
                    new CreateIndexOptions { Unique = true });
                await context.PostLikes.Indexes.CreateOneAsync(likeIndex);

                // 5. PostReports (Unique per user and post)
                var reportIndex = new CreateIndexModel<PostReport>(
                    Builders<PostReport>.IndexKeys.Ascending(r => r.PostId).Ascending(r => r.UserId),
                    new CreateIndexOptions { Unique = true });
                await context.PostReports.Indexes.CreateOneAsync(reportIndex);

                // 6. HealthProfiles (Unique per user)
                var healthProfileUserIndex = new CreateIndexModel<HealthProfile>(
                    Builders<HealthProfile>.IndexKeys.Ascending(h => h.UserId),
                    new CreateIndexOptions { Unique = true });
                await context.HealthProfiles.Indexes.CreateOneAsync(healthProfileUserIndex);

                // 7. HealthMetricLogs
                var healthMetricIndex = new CreateIndexModel<HealthMetricLog>(
                    Builders<HealthMetricLog>.IndexKeys.Ascending(m => m.UserId).Descending(m => m.LoggedAt));
                await context.HealthMetricLogs.Indexes.CreateOneAsync(healthMetricIndex);

                // 8. Ingredients (Unique on NormalizedName)
                var ingredientNameIndex = new CreateIndexModel<Ingredient>(
                    Builders<Ingredient>.IndexKeys.Ascending(i => i.NormalizedName),
                    new CreateIndexOptions { Unique = true });
                await context.Ingredients.Indexes.CreateOneAsync(ingredientNameIndex);

                // 9. PantryItems: Backfill, deduplicate and create unique index on (UserId, NormalizedName)
                try
                {
                    var pantryCol = context.PantryItems;
                    var allPantryItems = await pantryCol.Find(p => !p.IsDeleted).ToListAsync();

                    // Step A: Backfill NormalizedName for items missing it
                    foreach (var pItem in allPantryItems)
                    {
                        var norm = DomainLayer.Helpers.AllergyMatcher.RemoveDiacritics(pItem.Ingredient ?? string.Empty).ToLowerInvariant();
                        if (string.IsNullOrEmpty(pItem.NormalizedName) || pItem.NormalizedName != norm)
                        {
                            pItem.NormalizedName = norm;
                            await pantryCol.UpdateOneAsync(
                                Builders<PantryItem>.Filter.Eq(x => x.Id, pItem.Id),
                                Builders<PantryItem>.Update.Set(x => x.NormalizedName, norm));
                        }
                    }

                    // Step B: Deduplicate active items by (UserId, NormalizedName)
                    var grouped = allPantryItems
                        .Where(p => !string.IsNullOrEmpty(p.UserId) && !string.IsNullOrEmpty(p.NormalizedName))
                        .GroupBy(p => new { p.UserId, p.NormalizedName });

                    foreach (var group in grouped)
                    {
                        var list = group.OrderByDescending(p => p.UpdatedAt ?? p.CreatedAt).ToList();
                        if (list.Count > 1)
                        {
                            for (int i = 1; i < list.Count; i++)
                            {
                                await pantryCol.UpdateOneAsync(
                                    Builders<PantryItem>.Filter.Eq(x => x.Id, list[i].Id),
                                    Builders<PantryItem>.Update.Set(x => x.IsDeleted, true).Set(x => x.DeletedAt, DateTime.UtcNow));
                            }
                        }
                    }

                    // Step C: Create partial unique index on { UserId: 1, NormalizedName: 1 }
                    var pantryUserNormalizedIndex = new CreateIndexModel<PantryItem>(
                        Builders<PantryItem>.IndexKeys.Ascending(p => p.UserId).Ascending(p => p.NormalizedName),
                        new CreateIndexOptions<PantryItem>
                        {
                            Unique = true,
                            PartialFilterExpression = Builders<PantryItem>.Filter.Eq(p => p.IsDeleted, false)
                        });
                    await pantryCol.Indexes.CreateOneAsync(pantryUserNormalizedIndex);
                }
                catch (Exception ex)
                {
                    logger?.LogWarning(ex, "Lỗi khi xử lý migration/chỉ mục duy nhất cho PantryItems");
                }
                var pantryUserExpiryIndex = new CreateIndexModel<PantryItem>(
                    Builders<PantryItem>.IndexKeys.Ascending(p => p.UserId).Ascending(p => p.ExpiryDate));
                await context.PantryItems.Indexes.CreateOneAsync(pantryUserExpiryIndex);

                // 10. Recipes
                var recipeFilterIndex = new CreateIndexModel<Recipe>(
                    Builders<Recipe>.IndexKeys.Ascending(r => r.IsVegan).Ascending(r => r.CreatedBy));
                await context.Recipes.Indexes.CreateOneAsync(recipeFilterIndex);

                // 11. MealPlans (Unique on userId + startDate)
                var mealPlanUserWeekIndex = new CreateIndexModel<MealPlan>(
                    Builders<MealPlan>.IndexKeys.Ascending(m => m.UserId).Ascending(m => m.StartDate),
                    new CreateIndexOptions { Unique = true });
                await context.MealPlans.Indexes.CreateOneAsync(mealPlanUserWeekIndex);

                // 12. AiLogs
                var aiLogTaskIndex = new CreateIndexModel<AiLog>(
                    Builders<AiLog>.IndexKeys.Ascending(a => a.TaskType).Descending(a => a.CreatedAt));
                var aiLogScanIndex = new CreateIndexModel<AiLog>(
                    Builders<AiLog>.IndexKeys.Ascending(a => a.ScanId),
                    new CreateIndexOptions { Sparse = true });
                await context.AiLogs.Indexes.CreateManyAsync(new[] { aiLogTaskIndex, aiLogScanIndex });

                logger?.LogInformation("Đã khởi tạo thành công tất cả chỉ mục MongoDB.");
            }
            catch (Exception ex)
            {
                logger?.LogError(ex, "Lỗi khi khởi tạo chỉ mục MongoDB");
            }
        }
    }
}

