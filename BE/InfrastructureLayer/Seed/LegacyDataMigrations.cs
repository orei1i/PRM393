using System.Threading.Tasks;
using DomainLayer.Entities;
using InfrastructureLayer.Database;
using MongoDB.Driver;

namespace InfrastructureLayer.Seed
{
    /// <summary>Sửa dữ liệu ghi từ bản cũ. Chạy lúc khởi động, chạy lại nhiều lần vẫn ra một kết quả.</summary>
    public static class LegacyDataMigrations
    {
        /// <summary>B43: mục tiêu cũ lose, gain, weight_loss đổi sang tên hiện dùng, trên hồ sơ và thực đơn.</summary>
        public static async Task<long> MigrateGoalsAsync(MongoDbContext context)
        {
            var changed = 0L;
            foreach (var (oldGoal, newGoal) in new[] { ("lose", "lose_weight"), ("weight_loss", "lose_weight"), ("gain", "gain_weight") })
            {
                var profiles = await context.HealthProfiles.UpdateManyAsync(
                    p => p.Goal == oldGoal,
                    Builders<HealthProfile>.Update.Set(p => p.Goal, newGoal));
                var plans = await context.MealPlans.UpdateManyAsync(
                    p => p.Goal == oldGoal,
                    Builders<MealPlan>.Update.Set(p => p.Goal, newGoal));
                changed += profiles.ModifiedCount + plans.ModifiedCount;
            }
            return changed;
        }
    }
}
