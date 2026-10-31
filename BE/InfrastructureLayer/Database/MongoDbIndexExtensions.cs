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

                // 9. PantryItems
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

