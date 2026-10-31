using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.Services;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint2_MealPlanUnitTests
    {
        private readonly Mock<IGenericRepository<MealPlan>> _mealPlanRepoMock;
        private readonly Mock<IGenericRepository<Recipe>> _recipeRepoMock;
        private readonly Mock<IGenericRepository<HealthProfile>> _profileRepoMock;
        private readonly Mock<IGenericRepository<PantryItem>> _pantryRepoMock;
        private readonly MealPlanService _mealPlanService;

        public Sprint2_MealPlanUnitTests()
        {
            _mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();
            _recipeRepoMock = new Mock<IGenericRepository<Recipe>>();
            _profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            _pantryRepoMock = new Mock<IGenericRepository<PantryItem>>();

            _mealPlanService = new MealPlanService(
                _mealPlanRepoMock.Object,
                _recipeRepoMock.Object,
                _profileRepoMock.Object,
                _pantryRepoMock.Object);
        }

        [Fact]
        public async Task B31_GenerateMealPlan_PortionClamped_Max2Repeats_TotalCaloriesWithin90To110Percent()
        {
            var userId = "user123";
            var targetCalories = 2000;
            var profile = new HealthProfile
            {
                UserId = userId,
                TargetCalories = targetCalories,
                Goal = "maintain",
                MealPattern = new List<string> { "breakfast", "lunch", "dinner" },
                Allergies = new List<string>()
            };

            _profileRepoMock
                .Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(profile);

            // Mock an abundant pool of recipes
            var recipePool = new List<Recipe>();
            for (int i = 1; i <= 15; i++)
            {
                recipePool.Add(new Recipe
                {
                    Id = $"recipe_{i}",
                    Name = $"Món chay {i}",
                    Calories = 500 + (i % 5) * 50, // 500 - 700 kcal
                    MealTypes = new List<string> { "breakfast", "lunch", "dinner" },
                    IsVegan = true
                });
            }

            _recipeRepoMock
                .Setup(r => r.FindAsync(It.IsAny<Expression<Func<Recipe, bool>>>()))
                .ReturnsAsync(recipePool);

            _mealPlanRepoMock
                .Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<MealPlan, bool>>>()))
                .ReturnsAsync((MealPlan?)null);

            var request = new GenerateMealPlanRequest
            {
                StartDate = "2026-11-02",
                UsePantry = false
            };

            var planResponse = await _mealPlanService.GenerateMealPlanAsync(userId, request);

            Assert.NotNull(planResponse);
            Assert.Equal(7, planResponse.Days.Count);

            var recipeUsageCounts = new Dictionary<string, int>();

            foreach (var day in planResponse.Days)
            {
                // Assert total calories within 90% - 110% of 2000 kcal (1800 - 2200)
                Assert.InRange(day.TotalCalories, (int)(targetCalories * 0.90), (int)(targetCalories * 1.10));

                foreach (var slot in day.Meals.Values)
                {
                    // Assert portion clamped between 0.75 and 1.5
                    Assert.InRange(slot.Portion, 0.75, 1.5);

                    if (!string.IsNullOrEmpty(slot.RecipeId))
                    {
                        recipeUsageCounts[slot.RecipeId] = recipeUsageCounts.GetValueOrDefault(slot.RecipeId, 0) + 1;
                    }
                }
            }

            // Assert no recipe is repeated more than 2 times in the entire week
            foreach (var kvp in recipeUsageCounts)
            {
                Assert.True(kvp.Value <= 2, $"Recipe {kvp.Key} appeared {kvp.Value} times, exceeding maximum 2 repeats/week.");
            }
        }

        [Fact]
        public async Task B29_CreateMealPlan_EmptyTrue_ClearsMealsOnExistingPlan()
        {
            var userId = "user123";
            var startDate = "2026-11-02";

            var existingPlan = new MealPlan
            {
                Id = "plan_existing_123",
                UserId = userId,
                StartDate = startDate,
                Days = new List<MealPlanDay>
                {
                    new MealPlanDay
                    {
                        Date = "2026-11-02",
                        Meals = new Dictionary<string, MealSlotItem>
                        {
                            ["breakfast"] = new MealSlotItem { Name = "Phở chay", Calories = 450 }
                        }
                    }
                }
            };

            _mealPlanRepoMock
                .Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<MealPlan, bool>>>()))
                .ReturnsAsync(existingPlan);

            var request = new CreateMealPlanRequest
            {
                StartDate = startDate,
                Empty = true
            };

            var result = await _mealPlanService.CreateMealPlanAsync(userId, request);

            Assert.NotNull(result);
            // Assert that meals on the existing plan were cleared
            Assert.Empty(existingPlan.Days[0].Meals);
            _mealPlanRepoMock.Verify(r => r.UpdateAsync(existingPlan.Id, existingPlan), Times.Once);
        }

        [Fact]
        public async Task B19_CreateMyRecipe_PreservesZeroCalories_AndMapsPrepMinutes()
        {
            var userId = "user123";
            var request = new CreateRecipeRequest
            {
                Name = "Trà hoa cúc không đường",
                Calories = 0, // B19: zero calories must NOT be changed to 300
                PrepMinutes = 5
            };

            Recipe? savedRecipe = null;
            _recipeRepoMock
                .Setup(r => r.CreateAsync(It.IsAny<Recipe>()))
                .Callback<Recipe>(r => savedRecipe = r)
                .ReturnsAsync((Recipe r) => r);

            var response = await _mealPlanService.CreateMyRecipeAsync(userId, request);

            Assert.NotNull(savedRecipe);
            Assert.Equal(0, savedRecipe.Calories);
            Assert.Equal(5, savedRecipe.PrepMinutes);
            Assert.Equal(0, response.Calories);
            Assert.Equal(5, response.PrepMinutes);
        }

        [Fact]
        public async Task B30_GetSwapSuggestions_ExcludesCurrentRecipeId()
        {
            var userId = "user123";
            var planId = "plan123";
            var currentRecipeId = "recipe_current_soup";

            var plan = new MealPlan
            {
                Id = planId,
                UserId = userId,
                Days = new List<MealPlanDay>
                {
                    new MealPlanDay
                    {
                        Date = "2026-11-02",
                        Meals = new Dictionary<string, MealSlotItem>
                        {
                            ["lunch"] = new MealSlotItem { RecipeId = currentRecipeId, Calories = 400 }
                        }
                    }
                }
            };

            _mealPlanRepoMock.Setup(r => r.FindByIdAsync(planId)).ReturnsAsync(plan);

            var recipeList = new List<Recipe>
            {
                new Recipe { Id = currentRecipeId, Name = "Súp nấm hiện tại", Calories = 400, MealTypes = new List<string> { "lunch" }, IsVegan = true },
                new Recipe { Id = "recipe_other_salad", Name = "Salad bơ", Calories = 420, MealTypes = new List<string> { "lunch" }, IsVegan = true }
            };

            _recipeRepoMock.Setup(r => r.FindAsync(It.IsAny<Expression<Func<Recipe, bool>>>())).ReturnsAsync(recipeList);

            var suggestions = (await _mealPlanService.GetSwapSuggestionsAsync(userId, planId, "2026-11-02", "lunch")).ToList();

            // B30: Suggestion list must NOT contain the dish currently placed
            Assert.DoesNotContain(suggestions, s => s.Id == currentRecipeId);
            Assert.Contains(suggestions, s => s.Id == "recipe_other_salad");
        }

        [Fact]
        public async Task M1_SuggestFromIngredients_DoesNotModifyDatabase()
        {
            var userId = "user123";

            _pantryRepoMock.Setup(r => r.FindAsync(It.IsAny<Expression<Func<PantryItem, bool>>>()))
                .ReturnsAsync(new List<PantryItem>
                {
                    new PantryItem { Ingredient = "Đậu phụ" },
                    new PantryItem { Ingredient = "Cà chua" }
                });

            _recipeRepoMock.Setup(r => r.FindAsync(It.IsAny<Expression<Func<Recipe, bool>>>()))
                .ReturnsAsync(new List<Recipe>
                {
                    new Recipe
                    {
                        Id = "r1",
                        Name = "Đậu sốt cà chua",
                        Ingredients = new List<string> { "Đậu phụ", "Cà chua", "Hành lá" },
                        IsVegan = true
                    }
                });

            var result = await _mealPlanService.SuggestFromIngredientsAsync(userId);

            Assert.NotEmpty(result);
            Assert.Equal("r1", result[0].Id);

            // M1: Verify that _mealPlanRepo was NEVER touched (no CreateAsync or UpdateAsync)
            _mealPlanRepoMock.Verify(r => r.CreateAsync(It.IsAny<MealPlan>()), Times.Never);
            _mealPlanRepoMock.Verify(r => r.UpdateAsync(It.IsAny<string>(), It.IsAny<MealPlan>()), Times.Never);
        }
    }
}
