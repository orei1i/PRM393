using System;
using System.Threading.Tasks;
using DomainLayer.Entities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Hosting;
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
                using var pingCts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(2));
                await context.Database.RunCommandAsync((Command<MongoDB.Bson.BsonDocument>)"{ping:1}", cancellationToken: pingCts.Token);
            }
            catch
            {
                logger?.LogWarning("MongoDB không phản hồi ping trong 2s. Bỏ qua seed dữ liệu.");
                return;
            }

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

                // B5: Seed tài khoản mẫu (chỉ chạy trong môi trường Development)
                var env = scope.ServiceProvider.GetService<Microsoft.AspNetCore.Hosting.IWebHostEnvironment>();
                if (env != null && env.IsDevelopment())
                {
                    var userCount = await context.Users.CountDocumentsAsync(_ => true);
                    if (userCount == 0)
                    {
                        var defaultHash = BCrypt.Net.BCrypt.HashPassword("Password123!");
                        var devUsers = new List<User>
                        {
                            new User
                            {
                                Email = "admin@veganlife.vn",
                                FullName = "Admin VeganLife",
                                Phone = "0900000001",
                                Role = "Admin",
                                PasswordHash = defaultHash,
                                Status = DomainLayer.Enums.GeneralEnum.UserStatusEnum.Active,
                                AuthType = DomainLayer.Enums.GeneralEnum.AuthTypeEnum.System,
                                CreatedAt = DateTime.UtcNow
                            },
                            new User
                            {
                                Email = "chef.hoang@veganlife.vn",
                                FullName = "Chef Hoàng",
                                Phone = "0900000002",
                                Role = "Chef",
                                PasswordHash = defaultHash,
                                Status = DomainLayer.Enums.GeneralEnum.UserStatusEnum.Active,
                                AuthType = DomainLayer.Enums.GeneralEnum.AuthTypeEnum.System,
                                CreatedAt = DateTime.UtcNow
                            },
                            new User
                            {
                                Email = "minhanh.nguyen@gmail.com",
                                FullName = "Minh Anh Nguyễn",
                                Phone = "0900000003",
                                Role = "User",
                                PasswordHash = defaultHash,
                                Status = DomainLayer.Enums.GeneralEnum.UserStatusEnum.Active,
                                AuthType = DomainLayer.Enums.GeneralEnum.AuthTypeEnum.System,
                                CreatedAt = DateTime.UtcNow
                            }
                        };
                        await context.Users.InsertManyAsync(devUsers);
                        logger?.LogInformation("Đã seed thành công 3 tài khoản dev mẫu vào MongoDB.");
                    }
                }
            }
            catch (Exception ex)
            {
                logger?.LogError(ex, "Lỗi khi chạy DatabaseSeeder");
            }
        }
    }
}

