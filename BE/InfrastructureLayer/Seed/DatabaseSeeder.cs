using System;
using System.Threading.Tasks;
using DomainLayer.Entities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using MongoDB.Driver;

namespace InfrastructureLayer.Seed
{
    public static class DatabaseSeeder
    {
        public static async Task SeedAsync(this IServiceProvider services)
        {
            using var scope = services.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<Database.MongoDbContext>();
            var logger = scope.ServiceProvider.GetService<ILogger<Database.MongoDbContext>>();

            try
            {
                // Seed Ingredients nếu collection rỗng
                var ingredientCount = await context.Ingredients.CountDocumentsAsync(_ => true);
                if (ingredientCount == 0)
                {
                    var ingredients = IngredientSeedData.GetSeeds();
                    await context.Ingredients.InsertManyAsync(ingredients);
                    logger?.LogInformation("Đã seed thành công {Count} nguyên liệu chay vào MongoDB.", ingredients.Count);
                }

                // Seed Recipes nếu collection rỗng
                var recipeCount = await context.Recipes.CountDocumentsAsync(_ => true);
                if (recipeCount == 0)
                {
                    var recipes = RecipeSeedData.GetSeeds();
                    await context.Recipes.InsertManyAsync(recipes);
                    logger?.LogInformation("Đã seed thành công {Count} công thức món ăn chay vào MongoDB.", recipes.Count);
                }
            }
            catch (Exception ex)
            {
                logger?.LogError(ex, "Lỗi khi chạy DatabaseSeeder");
            }
        }
    }
}

