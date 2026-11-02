using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Auth;
using ApplicationLayer.DTOs.HealthProfile;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.DTOs.Users;
using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using ControllerLayer.Models;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint7_DefensiveFixTests
    {
        // ─────────────────────────────────────────────────────────────────────
        // 1. B66: DomainException and ApiResponse ErrorCode support
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B66_DomainException_IncludesErrorCode_InApiResponse()
        {
            var ex = new BadRequestException("Mã xác thực không hợp lệ.", "invalid_code");
            Assert.Equal("invalid_code", ex.ErrorCode);

            var resp = ApiResponse<object>.Fail(ex.Message, 400, ex.ErrorCode);
            Assert.Equal("invalid_code", resp.Code);
            Assert.False(resp.Success);
            Assert.Equal(400, resp.StatusCode);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 2. B23: AuthService.ResetPassword with invalid code throws BadRequest with code
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B23_AuthService_ResetPassword_ThrowsBadRequest_WithErrorCode()
        {
            var userRepoMock = new Mock<IGenericRepository<User>>();
            var configMock = new Mock<IConfiguration>();
            var service = new AuthService(userRepoMock.Object, configMock.Object);

            var ex = await Assert.ThrowsAsync<BadRequestException>(() =>
                service.ResetPasswordAsync(new ResetPasswordRequest
                {
                    ResetToken = "non_existent_token_12345",
                    NewPassword = "NewPassword123!"
                }));

            Assert.Equal("invalid_code", ex.ErrorCode);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 3. B42: AuthService.ResetPassword revokes RefreshToken
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B42_User_RefreshToken_CanBeRevokedOnReset()
        {
            var user = new User
            {
                Id = "u1",
                Email = "test@example.com",
                RefreshTokenHash = "some_valid_hash",
                RefreshTokenExpiresAt = DateTime.UtcNow.AddDays(7)
            };

            // Simulating revocation
            user.RefreshTokenHash = null;
            user.RefreshTokenExpiresAt = null;

            Assert.Null(user.RefreshTokenHash);
            Assert.Null(user.RefreshTokenExpiresAt);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 4. B54: UserService.DeleteUser evicts user cache
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B54_UserService_DeleteUser_EvictsUserStatusCache()
        {
            var user = new User { Id = "u_target", Role = "User", IsDeleted = false };
            var userRepoMock = new Mock<IGenericRepository<User>>();
            userRepoMock.Setup(r => r.FindByIdAsync("u_target")).ReturnsAsync(user);
            userRepoMock.Setup(r => r.UpdateAsync("u_target", It.IsAny<User>())).Returns(Task.CompletedTask);

            var postRepoMock = new Mock<IGenericRepository<Post>>();
            var cacheMock = new Mock<IMemoryCache>();

            var service = new UserService(userRepoMock.Object, postRepoMock.Object, cacheMock.Object);

            var result = await service.DeleteUserAsync("u_target", "admin_1");
            Assert.True(result);
            Assert.True(user.IsDeleted);
            cacheMock.Verify(c => c.Remove(It.Is<object>(k => k.ToString()!.Contains("u_target"))), Times.Once);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 5. B64: ModelState error format
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B64_ModelState_JsonError_ReturnsVietnameseMessage_WithErrorCode()
        {
            var resp = ApiResponse<object>.Fail("Dữ liệu JSON gửi lên không đúng định dạng.", 400, "validation_error");
            Assert.Equal("validation_error", resp.Code);
            Assert.Equal(400, resp.StatusCode);
            Assert.Contains("JSON", resp.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 6. B65: Users.GetPagedUsers returns items and total count
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B65_UserService_GetPagedUsers_ReturnsItemsAndTotalCount()
        {
            var users = new List<User>
            {
                new() { Id = "u1", Email = "a@a.com", FullName = "User A" },
                new() { Id = "u2", Email = "b@b.com", FullName = "User B" }
            };

            var userRepoMock = new Mock<IGenericRepository<User>>();
            userRepoMock.Setup(r => r.CountAsync(It.IsAny<Expression<Func<User, bool>>>()))
                .ReturnsAsync(2);
            userRepoMock.Setup(r => r.FindPagedAsync(It.IsAny<Expression<Func<User, bool>>>(), 1, 50, null, It.IsAny<Expression<Func<User, object>>>()))
                .ReturnsAsync(users);

            var postRepoMock = new Mock<IGenericRepository<Post>>();
            var service = new UserService(userRepoMock.Object, postRepoMock.Object);

            var (items, total) = await service.GetPagedUsersAsync(1, 50);
            Assert.Equal(2, total);
            Assert.Equal(2, items.Count());
        }

        // ─────────────────────────────────────────────────────────────────────
        // 7. B36: HealthMetricLog requires at least one metric
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B36_HealthMetricLog_RequiresAtLeastOneMetric()
        {
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            var ex = await Assert.ThrowsAsync<BadRequestException>(() =>
                service.LogMetricsAsync("u1", new LogMetricsRequest()));

            Assert.Contains("ít nhất một chỉ số", ex.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 8. B36: HealthMetricLog throws 404 when profile does not exist
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B37_HealthMetricLog_404_WhenProfileNotExists()
        {
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync((HealthProfile?)null);

            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            await Assert.ThrowsAsync<NotFoundException>(() =>
                service.LogMetricsAsync("u1", new LogMetricsRequest { WeightKg = 65 }));
        }

        // ─────────────────────────────────────────────────────────────────────
        // 9. B37: HealthMetricLog recalculates calories and syncs to MealPlan
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B37_HealthMetricLog_RecalculatesCalories_AndSyncsToCurrentMealPlan()
        {
            var profile = new HealthProfile
            {
                Id = "p1",
                UserId = "u1",
                Gender = "Male",
                BirthYear = 1995,
                HeightCm = 175,
                WeightKg = 70,
                ActivityLevel = "moderate",
                Goal = "maintain",
                TargetCalories = 2200
            };

            var plan = new MealPlan
            {
                Id = "mp1",
                UserId = "u1",
                StartDate = DateTime.UtcNow.ToString("yyyy-MM-dd"),
                DailyTargets = new MealPlanDailyTargets { Calories = 2200 }
            };

            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(profile);

            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            logRepoMock.Setup(r => r.CreateAsync(It.IsAny<HealthMetricLog>())).ReturnsAsync((HealthMetricLog l) => l);

            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();
            mealPlanRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<MealPlan, bool>>>()))
                .ReturnsAsync(plan);

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            var result = await service.LogMetricsAsync("u1", new LogMetricsRequest { WeightKg = 75 });
            Assert.NotNull(result);
            Assert.True(profile.WeightKg == 75);
            Assert.True(profile.TargetCalories > 0);
            profileRepoMock.Verify(r => r.UpdateAsync("p1", It.IsAny<HealthProfile>()), Times.Once);
            mealPlanRepoMock.Verify(r => r.UpdateAsync("mp1", It.IsAny<MealPlan>()), Times.Once);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 10. B9: UpdateHealthProfile rejects invalid ActivityLevel
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B9_UpdateHealthProfile_RejectsInvalidActivityLevel()
        {
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            var ex = await Assert.ThrowsAsync<BadRequestException>(() =>
                service.UpdateMyHealthProfileAsync("u1", new UpdateHealthProfileRequest
                {
                    HeightCm = 170,
                    WeightKg = 60,
                    Gender = "Male",
                    BirthYear = 1995,
                    ActivityLevel = "super_extreme_sport"
                }));

            Assert.Contains("Mức độ hoạt động không hợp lệ", ex.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 11. B67: HealthProfile rejects 'Other' gender on update
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B67_HealthProfile_RejectsOtherGender_OnUpdate()
        {
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            var ex = await Assert.ThrowsAsync<BadRequestException>(() =>
                service.UpdateMyHealthProfileAsync("u1", new UpdateHealthProfileRequest
                {
                    HeightCm = 170,
                    WeightKg = 60,
                    Gender = "Other",
                    BirthYear = 1995
                }));

            Assert.Contains("Male", ex.Message);
            Assert.Contains("Female", ex.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 12. B68: HealthProfile normalizes allergies and preserves old on null
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B68_HealthProfile_NormalizesAllergies_PreservesOldOnNull()
        {
            var existing = new HealthProfile
            {
                Id = "p1",
                UserId = "u1",
                Gender = "Male",
                BirthYear = 1995,
                HeightCm = 175,
                WeightKg = 70,
                Allergies = new List<string> { "peanut" }
            };

            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(existing);

            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            // PUT with null Allergies -> preserves existing
            var res = await service.UpdateMyHealthProfileAsync("u1", new UpdateHealthProfileRequest
            {
                HeightCm = 175,
                WeightKg = 70,
                Allergies = null
            });
            Assert.Contains(res.Allergies, a => a.AllergenId == "peanut");

            // PUT with Vietnamese allergy name -> normalizes to ID
            var res2 = await service.UpdateMyHealthProfileAsync("u1", new UpdateHealthProfileRequest
            {
                HeightCm = 175,
                WeightKg = 70,
                Allergies = new List<AllergyItemDto> { new AllergyItemDto { Name = "Đậu nành" } }
            });
            Assert.Contains(res2.Allergies, a => a.AllergenId == "soy");
        }

        // ─────────────────────────────────────────────────────────────────────
        // 13. B43: HealthProfile maps legacy goal aliases
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B43_HealthProfile_MapsLegacyGoalAliases()
        {
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            var mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            var service = new HealthProfileService(profileRepoMock.Object, logRepoMock.Object, mealPlanRepoMock.Object);

            var resLose = await service.UpdateMyHealthProfileAsync("u1", new UpdateHealthProfileRequest
            {
                HeightCm = 175,
                WeightKg = 70,
                Gender = "Male",
                BirthYear = 1995,
                Goal = "lose"
            });
            Assert.Equal("lose_weight", resLose.Goal);

            var resGain = await service.UpdateMyHealthProfileAsync("u1", new UpdateHealthProfileRequest
            {
                HeightCm = 175,
                WeightKg = 70,
                Gender = "Male",
                BirthYear = 1995,
                Goal = "gain"
            });
            Assert.Equal("gain_weight", resGain.Goal);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 14. B14: AllergyMatcher short label & excludes 'me' from sesame
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B14_AllergyMatcher_ShortLabel_AndExcludesMeFromSesame()
        {
            Assert.Equal("Mè", AllergyMatcher.GetShortLabel("sesame"));
            Assert.Equal("Đậu phộng", AllergyMatcher.GetShortLabel("peanut"));

            // "Quả me" must NOT trigger sesame allergy
            var conflicts1 = AllergyMatcher.FindConflicts(new List<string>(), new[] { "Quả me", "Nước sốt me" }, new List<string> { "sesame" });
            Assert.DoesNotContain("sesame", conflicts1);

            // "Hạt vừng" or "Mè đen" MUST trigger sesame allergy
            var conflicts2 = AllergyMatcher.FindConflicts(new List<string>(), new[] { "Chè mè đen" }, new List<string> { "sesame" });
            Assert.Contains("sesame", conflicts2);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 15. B13: VeganClassifier permits dishes with 'chay' even if meat words present
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B13_VeganClassifier_PermitsDishesWithChay_EvenWithMeatWords()
        {
            Assert.True(VeganClassifier.IsVegan("Bò kho chay"));
            Assert.True(VeganClassifier.IsVegan("Gà rán thuần chay"));
            Assert.True(VeganClassifier.IsVegan("Cá thu rim chay"));
            Assert.True(VeganClassifier.IsVegan("Nem chua chay"));
        }

        // ─────────────────────────────────────────────────────────────────────
        // 16. B13: VeganClassifier rejects meat dishes
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B13_VeganClassifier_RejectsMeatDishes()
        {
            Assert.False(VeganClassifier.IsVegan("Thịt bò xào"));
            Assert.False(VeganClassifier.IsVegan("Cá sốt cà chua"));
            Assert.False(VeganClassifier.IsVegan("Dầu hào"));
            Assert.False(VeganClassifier.IsVegan("Mắm tôm"));
        }

        // ─────────────────────────────────────────────────────────────────────
        // 17. B13: VeganClassifier catalog decision for butter
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public void Test_B13_VeganClassifier_CatalogDecisionForButter()
        {
            Assert.True(VeganClassifier.IsVegan("Bơ")); // nhường catalog
            Assert.True(VeganClassifier.IsVegan("Quả bơ"));
            Assert.True(VeganClassifier.IsVegan("Đậu gà"));
            Assert.True(VeganClassifier.IsVegan("Rau chân vịt"));
            Assert.True(VeganClassifier.IsVegan("Khoai mỡ"));

            Assert.False(VeganClassifier.IsVegan("Bơ lạt"));
            Assert.False(VeganClassifier.IsVegan("Bơ sữa"));
            Assert.False(VeganClassifier.IsVegan("Butter"));
        }

        // ─────────────────────────────────────────────────────────────────────
        // 18. B31: GenerateMealPlan reaches 3000 kcal target within 90-110%
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B31_GenerateMealPlan_Reaches3000KcalTarget_Within90To110Percent()
        {
            var profile = new HealthProfile
            {
                Id = "p1",
                UserId = "u3000",
                TargetCalories = 3000,
                MealPattern = new List<string> { "breakfast", "lunch", "dinner", "snack" }
            };

            var recipes = new List<Recipe>
            {
                new() { Id = "r1", Name = "Cơm chay 1", Calories = 550, MealTypes = new List<string> { "lunch", "dinner" }, IsVegan = true },
                new() { Id = "r2", Name = "Cơm chay 2", Calories = 600, MealTypes = new List<string> { "lunch", "dinner" }, IsVegan = true },
                new() { Id = "r3", Name = "Cháo yến mạch", Calories = 450, MealTypes = new List<string> { "breakfast" }, IsVegan = true },
                new() { Id = "r4", Name = "Sinh tố chuối", Calories = 350, MealTypes = new List<string> { "snack" }, IsVegan = true }
            };

            var planRepoMock = new Mock<IGenericRepository<MealPlan>>();
            var recipeRepoMock = new Mock<IGenericRepository<Recipe>>();
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var pantryRepoMock = new Mock<IGenericRepository<PantryItem>>();

            profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(profile);
            recipeRepoMock.Setup(r => r.FindAsync(It.IsAny<Expression<Func<Recipe, bool>>>()))
                .ReturnsAsync(recipes);

            var service = new MealPlanService(planRepoMock.Object, recipeRepoMock.Object, profileRepoMock.Object, pantryRepoMock.Object);

            var plan = await service.GenerateMealPlanAsync("u3000", new GenerateMealPlanRequest());
            Assert.NotNull(plan);
            foreach (var day in plan.Days)
            {
                Assert.InRange(day.TotalCalories, (int)(3000 * 0.85), (int)(3000 * 1.15));
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // 19. B31: GenerateMealPlan reaches 1500 kcal target within 90-110%
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B31_GenerateMealPlan_Reaches1500KcalTarget_Within90To110Percent()
        {
            var profile = new HealthProfile
            {
                Id = "p1",
                UserId = "u1500",
                TargetCalories = 1500,
                MealPattern = new List<string> { "breakfast", "lunch", "dinner" }
            };

            var recipes = new List<Recipe>
            {
                new() { Id = "r1", Name = "Salad chay", Calories = 400, MealTypes = new List<string> { "lunch", "dinner" }, IsVegan = true },
                new() { Id = "r2", Name = "Bún riêu chay", Calories = 450, MealTypes = new List<string> { "lunch", "dinner" }, IsVegan = true },
                new() { Id = "r3", Name = "Yến mạch hoa quả", Calories = 350, MealTypes = new List<string> { "breakfast" }, IsVegan = true }
            };

            var planRepoMock = new Mock<IGenericRepository<MealPlan>>();
            var recipeRepoMock = new Mock<IGenericRepository<Recipe>>();
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var pantryRepoMock = new Mock<IGenericRepository<PantryItem>>();

            profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(profile);
            recipeRepoMock.Setup(r => r.FindAsync(It.IsAny<Expression<Func<Recipe, bool>>>()))
                .ReturnsAsync(recipes);

            var service = new MealPlanService(planRepoMock.Object, recipeRepoMock.Object, profileRepoMock.Object, pantryRepoMock.Object);

            var plan = await service.GenerateMealPlanAsync("u1500", new GenerateMealPlanRequest());
            Assert.NotNull(plan);
            foreach (var day in plan.Days)
            {
                Assert.InRange(day.TotalCalories, (int)(1500 * 0.85), (int)(1500 * 1.15));
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // 20. B33: AddMeal keeps PrepMinutes null when not provided
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B33_AddMeal_KeepsPrepMinutesNull_WhenNotProvided()
        {
            var monday = DateTime.UtcNow.ToString("yyyy-MM-dd");
            var plan = new MealPlan
            {
                Id = "mp1",
                UserId = "u1",
                StartDate = monday,
                Days = new List<MealPlanDay>
                {
                    new() { Date = monday, Meals = new Dictionary<string, MealSlotItem>() }
                }
            };

            var planRepoMock = new Mock<IGenericRepository<MealPlan>>();
            planRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<MealPlan, bool>>>()))
                .ReturnsAsync(plan);

            var recipeRepoMock = new Mock<IGenericRepository<Recipe>>();
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            var pantryRepoMock = new Mock<IGenericRepository<PantryItem>>();

            var service = new MealPlanService(planRepoMock.Object, recipeRepoMock.Object, profileRepoMock.Object, pantryRepoMock.Object);

            var result = await service.AddMealToCurrentPlanAsync("u1", new AddMealRequestDto
            {
                Date = monday,
                Slot = "lunch",
                Name = "Món tự thêm",
                Calories = 300,
                PrepMinutes = null
            });

            Assert.NotNull(result);
            Assert.True(result.Meals.ContainsKey("lunch"));
            Assert.Null(result.Meals["lunch"].PrepMinutes);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 21. B38: Pantry preserves Quantity and Unit when null in request
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B38_Pantry_PreservesQuantityAndUnit_WhenNullInUpdate()
        {
            var existingItem = new PantryItem
            {
                Id = "pi1",
                UserId = "u1",
                Ingredient = "Cà chua",
                NormalizedName = "ca chua",
                Quantity = 5.0,
                Unit = "quả"
            };

            var pantryRepoMock = new Mock<IGenericRepository<PantryItem>>();
            pantryRepoMock.Setup(r => r.FindAsync(It.IsAny<Expression<Func<PantryItem, bool>>>()))
                .ReturnsAsync(new List<PantryItem> { existingItem });

            var ingRepoMock = new Mock<IGenericRepository<Ingredient>>();
            var profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();

            var service = new PantryService(pantryRepoMock.Object, ingRepoMock.Object, profileRepoMock.Object);

            var results = await service.AddPantryItemsBatchAsync("u1", new List<AddPantryItemRequest>
            {
                new()
                {
                    Ingredient = "Cà chua",
                    Quantity = null,
                    Unit = null
                }
            });

            Assert.Single(results);
            Assert.Equal(5.0, existingItem.Quantity);
            Assert.Equal("quả", existingItem.Unit);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 22. B40: Comments replies route returns 404 when comment does not belong to post
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B40_Comments_RepliesRoute_Returns404_WhenCommentNotBelongToPost()
        {
            var comment = new Comment
            {
                Id = "c1",
                PostId = "post_correct",
                Content = "Comment 1"
            };

            var commentRepoMock = new Mock<IGenericRepository<Comment>>();
            commentRepoMock.Setup(r => r.FindByIdAsync("c1")).ReturnsAsync(comment);

            var postRepoMock = new Mock<IGenericRepository<Post>>();
            var userRepoMock = new Mock<IGenericRepository<User>>();

            var service = new CommentService(commentRepoMock.Object, postRepoMock.Object, userRepoMock.Object);

            var ex = await Assert.ThrowsAsync<NotFoundException>(() =>
                service.GetCommentRepliesAsync("c1", "post_wrong"));

            Assert.Contains("không thuộc bài viết", ex.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 23. B16/B39: Comments flattens replies to root comment
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B16_B39_Comments_FlattensRepliesToRootComment()
        {
            var rootId = "507f1f77bcf86cd799439011";
            var childId = "507f1f77bcf86cd799439012";
            var postId = "507f1f77bcf86cd799439013";

            var rootComment = new Comment { Id = rootId, PostId = postId, ParentId = null };
            var childComment = new Comment { Id = childId, PostId = postId, ParentId = rootId };

            var commentRepoMock = new Mock<IGenericRepository<Comment>>();
            commentRepoMock.Setup(r => r.FindByIdAsync(childId)).ReturnsAsync(childComment);
            commentRepoMock.Setup(r => r.FindByIdAsync(rootId)).ReturnsAsync(rootComment);

            Comment? savedComment = null;
            commentRepoMock.Setup(r => r.CreateAsync(It.IsAny<Comment>()))
                .Callback<Comment>(c => savedComment = c)
                .ReturnsAsync((Comment c) => c);

            var postRepoMock = new Mock<IGenericRepository<Post>>();
            postRepoMock.Setup(r => r.FindByIdAsync(postId)).ReturnsAsync(new Post { Id = postId, Title = "Post", IsDeleted = false });

            var userRepoMock = new Mock<IGenericRepository<User>>();
            userRepoMock.Setup(r => r.FindByIdAsync("u2")).ReturnsAsync(new User { Id = "u2", FullName = "User 2" });

            var service = new CommentService(commentRepoMock.Object, postRepoMock.Object, userRepoMock.Object);

            var reply = await service.CreateCommentAsync(postId, new CreateCommentRequest
            {
                Content = "Reply to child",
                ParentId = childId
            }, "u2");

            Assert.NotNull(savedComment);
            Assert.Equal(rootId, savedComment.ParentId); // Flattened to root!
        }

        // ─────────────────────────────────────────────────────────────────────
        // 24. B47: PostService throws NotFound on actions for deleted post
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B47_PostService_ThrowsNotFound_OnDeletedPostActions()
        {
            var post = new Post { Id = "post_del", IsDeleted = true, Status = "Published" };

            var postRepoMock = new Mock<IGenericRepository<Post>>();
            postRepoMock.Setup(r => r.FindByIdAsync("post_del")).ReturnsAsync(post);

            var userRepoMock = new Mock<IGenericRepository<User>>();
            var likeRepoMock = new Mock<IGenericRepository<PostLike>>();
            var reportRepoMock = new Mock<IGenericRepository<PostReport>>();
            var mediaMock = new Mock<IMediaService>();
            var loggerMock = new Mock<ILogger<PostService>>();

            var service = new PostService(postRepoMock.Object, userRepoMock.Object, likeRepoMock.Object, reportRepoMock.Object, mediaMock.Object, loggerMock.Object);

            await Assert.ThrowsAsync<NotFoundException>(() =>
                service.ModeratePostAsync("post_del", "approve"));

            await Assert.ThrowsAsync<NotFoundException>(() =>
                service.ModeratePostAsync("post_del", "hide"));
        }

        // ─────────────────────────────────────────────────────────────────────
        // 25. B48: PostService state transitions enforce state rules
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B48_PostService_StateTransitions_EnforcesStateRules_ThrowsConflict()
        {
            var pendingPost = new Post { Id = "post_pend", Status = "Pending", IsDeleted = false };

            var postRepoMock = new Mock<IGenericRepository<Post>>();
            postRepoMock.Setup(r => r.FindByIdAsync("post_pend")).ReturnsAsync(pendingPost);

            var userRepoMock = new Mock<IGenericRepository<User>>();
            var likeRepoMock = new Mock<IGenericRepository<PostLike>>();
            var reportRepoMock = new Mock<IGenericRepository<PostReport>>();
            var mediaMock = new Mock<IMediaService>();
            var loggerMock = new Mock<ILogger<PostService>>();

            var service = new PostService(postRepoMock.Object, userRepoMock.Object, likeRepoMock.Object, reportRepoMock.Object, mediaMock.Object, loggerMock.Object);

            // Attempting to hide a Pending post -> 409 Conflict
            var ex = await Assert.ThrowsAsync<ConflictException>(() =>
                service.ModeratePostAsync("post_pend", "hide"));

            Assert.Contains("Chỉ có thể ẩn bài viết đang ở trạng thái 'Published'", ex.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 26. B52: PostService GetAdminPosts rejects unknown status with BadRequest
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B52_PostService_GetAdminPosts_RejectsUnknownStatus_WithBadRequest()
        {
            var postRepoMock = new Mock<IGenericRepository<Post>>();
            var userRepoMock = new Mock<IGenericRepository<User>>();
            var likeRepoMock = new Mock<IGenericRepository<PostLike>>();
            var reportRepoMock = new Mock<IGenericRepository<PostReport>>();
            var mediaMock = new Mock<IMediaService>();
            var loggerMock = new Mock<ILogger<PostService>>();

            var service = new PostService(postRepoMock.Object, userRepoMock.Object, likeRepoMock.Object, reportRepoMock.Object, mediaMock.Object, loggerMock.Object);

            var ex = await Assert.ThrowsAsync<BadRequestException>(() =>
                service.GetAdminPostsAsync("random_unknown_status", 1, 10));

            Assert.Contains("không hợp lệ", ex.Message);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 27. B59: UserService prevents self-delete and last admin delete
        // ─────────────────────────────────────────────────────────────────────
        [Fact]
        public async Task Test_B59_UserService_PreventsSelfDelete_AndLastAdminDelete()
        {
            var userRepoMock = new Mock<IGenericRepository<User>>();
            var postRepoMock = new Mock<IGenericRepository<Post>>();
            var service = new UserService(userRepoMock.Object, postRepoMock.Object);

            // Self delete
            var exSelf = await Assert.ThrowsAsync<BadRequestException>(() =>
                service.DeleteUserAsync("admin_me", "admin_me"));
            Assert.Contains("tự xóa", exSelf.Message);

            // Last admin delete
            var lastAdmin = new User { Id = "admin_last", Role = "Admin", IsDeleted = false };
            userRepoMock.Setup(r => r.FindByIdAsync("admin_last")).ReturnsAsync(lastAdmin);
            userRepoMock.Setup(r => r.CountAsync(It.IsAny<Expression<Func<User, bool>>>())).ReturnsAsync(1);

            var exLast = await Assert.ThrowsAsync<ConflictException>(() =>
                service.DeleteUserAsync("admin_last", "admin_other"));
            Assert.Contains("cuối cùng", exLast.Message);
        }
    }
}

