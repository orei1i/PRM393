using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    public class MealPlanService : IMealPlanService
    {
        private readonly IGenericRepository<MealPlan> _mealPlanRepo;
        private readonly IGenericRepository<Recipe> _recipeRepo;
        private readonly IGenericRepository<HealthProfile> _profileRepo;
        private readonly IGenericRepository<PantryItem> _pantryRepo;

        public MealPlanService(
            IGenericRepository<MealPlan> mealPlanRepo,
            IGenericRepository<Recipe> recipeRepo,
            IGenericRepository<HealthProfile> profileRepo,
            IGenericRepository<PantryItem> pantryRepo)
        {
            _mealPlanRepo = mealPlanRepo;
            _recipeRepo = recipeRepo;
            _profileRepo = profileRepo;
            _pantryRepo = pantryRepo;
        }

        public async Task<MealPlanResponse> GetCurrentMealPlanAsync(string userId)
        {
            var today = DateTime.UtcNow.Date;
            var currentMonday = GetMondayOfWeek(today).ToString("yyyy-MM-dd");

            var plan = await _mealPlanRepo.FirstOrDefaultAsync(x => x.UserId == userId && x.StartDate == currentMonday && !x.IsDeleted);
            if (plan == null)
            {
                // Tìm plan gần nhất
                var plans = await _mealPlanRepo.FindPagedAsync(
                    x => x.UserId == userId && !x.IsDeleted,
                    page: 1,
                    pageSize: 1,
                    sortDesc: x => x.CreatedAt);

                plan = plans.FirstOrDefault();
            }

            if (plan == null)
            {
                throw new NotFoundException("Bạn chưa có thực đơn cho tuần này.");
            }

            var userAllergies = await GetUserAllergiesAsync(userId);
            return MapToResponse(plan, userAllergies);
        }

        public async Task<MealPlanResponse> GetMealPlanByIdAsync(string userId, string planId)
        {
            var plan = await _mealPlanRepo.FindByIdAsync(planId);
            if (plan == null || plan.IsDeleted || plan.UserId != userId)
            {
                throw new NotFoundException($"Không tìm thấy thực đơn với id: {planId}");
            }

            var userAllergies = await GetUserAllergiesAsync(userId);
            return MapToResponse(plan, userAllergies);
        }

        public async Task<MealPlanResponse> CreateMealPlanAsync(string userId, CreateMealPlanRequest request)
        {
            var startDateStr = NormalizeStartDate(request.StartDate);
            var existing = await _mealPlanRepo.FirstOrDefaultAsync(x => x.UserId == userId && x.StartDate == startDateStr && !x.IsDeleted);
            if (existing != null)
            {
                var allergies = await GetUserAllergiesAsync(userId);
                return MapToResponse(existing, allergies);
            }

            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);

            var startDt = DateTime.ParseExact(startDateStr, "yyyy-MM-dd", CultureInfo.InvariantCulture);
            var days = new List<MealPlanDay>();
            for (int i = 0; i < 7; i++)
            {
                days.Add(new MealPlanDay
                {
                    Date = startDt.AddDays(i).ToString("yyyy-MM-dd"),
                    Meals = new Dictionary<string, MealSlotItem>()
                });
            }

            var newPlan = new MealPlan
            {
                UserId = userId,
                StartDate = startDateStr,
                Goal = profile?.Goal ?? "maintain",
                DailyTargets = new MealPlanDailyTargets
                {
                    Calories = profile?.TargetCalories ?? 2000,
                    ProteinG = profile != null ? Math.Round(profile.TargetCalories * 0.15 / 4.0, 1) : 75,
                    CarbsG = profile != null ? Math.Round(profile.TargetCalories * 0.55 / 4.0, 1) : 275,
                    FatG = profile != null ? Math.Round(profile.TargetCalories * 0.30 / 9.0, 1) : 65,
                    FiberG = 30
                },
                Days = days,
                CreatedAt = DateTime.UtcNow
            };

            await _mealPlanRepo.CreateAsync(newPlan);
            return MapToResponse(newPlan, profile?.Allergies ?? new List<string>());
        }

        public async Task<MealPlanResponse> GenerateMealPlanAsync(string userId, GenerateMealPlanRequest request)
        {
            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            if (profile == null)
            {
                throw new BadRequestException("Vui lòng tạo hồ sơ sức khỏe trước khi tự động sinh thực đơn.");
            }

            var startDateStr = NormalizeStartDate(request.StartDate);
            var userAllergies = profile.Allergies ?? new List<string>();

            // Lấy tất cả công thức món chay
            var allRecipes = (await _recipeRepo.FindAsync(r => !r.IsDeleted && r.IsVegan)).ToList();

            // 1. TUYỆT ĐỐI LỌC DỊ ỨNG BẰNG CODE: Loại bỏ mọi món có chứa dị ứng của người dùng
            var safeRecipes = allRecipes.Where(recipe =>
            {
                var texts = recipe.Ingredients.Concat(new[] { recipe.Name });
                var conflicts = AllergyMatcher.FindConflicts(recipe.Allergens, texts, userAllergies);
                return !conflicts.Any();
            }).ToList();

            if (!safeRecipes.Any())
            {
                throw new BadRequestException("Không tìm thấy đủ công thức món ăn an toàn phù hợp với dị ứng của bạn.");
            }

            // Nếu người dùng yêu cầu xếp từ nguyên liệu trong tủ (Pantry)
            if (request.UsePantry)
            {
                var pantry = (await _pantryRepo.FindAsync(p => p.UserId == userId && !p.IsDeleted)).ToList();
                var pantryNormalized = pantry.Select(p => AllergyMatcher.RemoveDiacritics(p.Ingredient).ToLowerInvariant()).ToHashSet();

                safeRecipes = safeRecipes.OrderByDescending(recipe =>
                {
                    if (!recipe.Ingredients.Any()) return 0;
                    var matchCount = recipe.Ingredients.Count(ing =>
                    {
                        var ingNorm = AllergyMatcher.RemoveDiacritics(ing).ToLowerInvariant();
                        return pantryNormalized.Any(p => p.Contains(ingNorm) || ingNorm.Contains(p));
                    });
                    return (double)matchCount / recipe.Ingredients.Count;
                }).ToList();
            }

            // Phân nhóm công thức theo bữa
            var breakfasts = safeRecipes.Where(r => r.MealTypes.Contains("breakfast")).ToList();
            var lunches = safeRecipes.Where(r => r.MealTypes.Contains("lunch")).ToList();
            var dinners = safeRecipes.Where(r => r.MealTypes.Contains("dinner")).ToList();
            var snacks = safeRecipes.Where(r => r.MealTypes.Contains("snack") || r.MealTypes.Contains("snack_pm") || r.MealTypes.Contains("snack_am")).ToList();

            // Fallback nếu thiếu danh mục
            if (!breakfasts.Any()) breakfasts = safeRecipes;
            if (!lunches.Any()) lunches = safeRecipes;
            if (!dinners.Any()) dinners = safeRecipes;
            if (!snacks.Any()) snacks = safeRecipes;

            var startDt = DateTime.ParseExact(startDateStr, "yyyy-MM-dd", CultureInfo.InvariantCulture);
            var random = new Random();

            var days = new List<MealPlanDay>();
            var usedRecipeCounts = new Dictionary<string, int>();

            for (int i = 0; i < 7; i++)
            {
                var date = startDt.AddDays(i).ToString("yyyy-MM-dd");
                var dayMeals = new Dictionary<string, MealSlotItem>();

                // Chọn món sáng
                var b = PickRecipe(breakfasts, usedRecipeCounts, random);
                dayMeals["breakfast"] = MapToMealSlotItem(b, "ai");

                // Chọn món trưa
                var l = PickRecipe(lunches, usedRecipeCounts, random);
                dayMeals["lunch"] = MapToMealSlotItem(l, "ai");

                // Chọn món tối
                var d = PickRecipe(dinners, usedRecipeCounts, random);
                dayMeals["dinner"] = MapToMealSlotItem(d, "ai");

                // Nếu mealPattern có snack_pm
                if (profile.MealPattern.Contains("snack_pm") || profile.MealPattern.Contains("snack"))
                {
                    var s = PickRecipe(snacks, usedRecipeCounts, random);
                    dayMeals["snack_pm"] = MapToMealSlotItem(s, "ai");
                }

                days.Add(new MealPlanDay
                {
                    Date = date,
                    Meals = dayMeals
                });
            }

            var existingPlan = await _mealPlanRepo.FirstOrDefaultAsync(x => x.UserId == userId && x.StartDate == startDateStr && !x.IsDeleted);
            if (existingPlan != null)
            {
                existingPlan.Days = days;
                existingPlan.DailyTargets = new MealPlanDailyTargets
                {
                    Calories = profile.TargetCalories,
                    ProteinG = Math.Round(profile.TargetCalories * 0.15 / 4.0, 1),
                    CarbsG = Math.Round(profile.TargetCalories * 0.55 / 4.0, 1),
                    FatG = Math.Round(profile.TargetCalories * 0.30 / 9.0, 1),
                    FiberG = 30
                };
                existingPlan.UpdatedAt = DateTime.UtcNow;
                await _mealPlanRepo.UpdateAsync(existingPlan.Id, existingPlan);
                return MapToResponse(existingPlan, userAllergies);
            }
            else
            {
                var plan = new MealPlan
                {
                    UserId = userId,
                    StartDate = startDateStr,
                    Goal = profile.Goal,
                    DailyTargets = new MealPlanDailyTargets
                    {
                        Calories = profile.TargetCalories,
                        ProteinG = Math.Round(profile.TargetCalories * 0.15 / 4.0, 1),
                        CarbsG = Math.Round(profile.TargetCalories * 0.55 / 4.0, 1),
                        FatG = Math.Round(profile.TargetCalories * 0.30 / 9.0, 1),
                        FiberG = 30
                    },
                    Days = days,
                    CreatedAt = DateTime.UtcNow
                };

                await _mealPlanRepo.CreateAsync(plan);
                return MapToResponse(plan, userAllergies);
            }
        }

        public async Task<MealPlanDayResponse> SwapMealAsync(string userId, string planId, SwapMealRequestDto request)
        {
            var plan = await _mealPlanRepo.FindByIdAsync(planId);
            if (plan == null || plan.IsDeleted || plan.UserId != userId)
            {
                throw new NotFoundException($"Không tìm thấy thực đơn với id: {planId}");
            }

            var day = plan.Days.FirstOrDefault(d => d.Date == request.Date);
            if (day == null)
            {
                throw new BadRequestException($"Ngày {request.Date} không thuộc thực đơn này.");
            }

            var recipe = await _recipeRepo.FindByIdAsync(request.RecipeId);
            if (recipe == null || recipe.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy công thức món ăn: {request.RecipeId}");
            }

            var userAllergies = await GetUserAllergiesAsync(userId);
            var item = MapToMealSlotItem(recipe, "manual");

            // Kiểm tra cảnh báo dị ứng
            var texts = recipe.Ingredients.Concat(new[] { recipe.Name });
            item.AllergyConflicts = AllergyMatcher.FindConflicts(recipe.Allergens, texts, userAllergies);

            day.Meals[request.Slot.ToLowerInvariant()] = item;
            plan.UpdatedAt = DateTime.UtcNow;

            await _mealPlanRepo.UpdateAsync(plan.Id, plan);
            return MapToDayResponse(day);
        }

        public async Task<MealPlanDayResponse> AddMealToCurrentPlanAsync(string userId, AddMealRequestDto request)
        {
            var currentPlanRes = await GetCurrentMealPlanAsync(userId);
            var plan = await _mealPlanRepo.FindByIdAsync(currentPlanRes.Id);
            if (plan == null) throw new NotFoundException("Không tìm thấy thực đơn hiện tại.");

            var day = plan.Days.FirstOrDefault(d => d.Date == request.Date);
            if (day == null)
            {
                throw new BadRequestException($"Ngày {request.Date} không nằm trong tuần hiện tại.");
            }

            var userAllergies = await GetUserAllergiesAsync(userId);
            var slotItem = new MealSlotItem
            {
                Id = Guid.NewGuid().ToString("N"),
                RecipeId = request.SourceId,
                Name = request.Name.Trim(),
                Calories = request.Calories,
                PrepMinutes = request.PrepMinutes > 0 ? request.PrepMinutes : 15,
                Allergens = request.Allergens ?? new List<string>(),
                Source = string.IsNullOrWhiteSpace(request.Source) ? "manual" : request.Source,
                Portion = 1.0
            };

            var texts = (request.Ingredients ?? new List<string>()).Concat(new[] { request.Name });
            slotItem.AllergyConflicts = AllergyMatcher.FindConflicts(slotItem.Allergens, texts, userAllergies);

            day.Meals[request.Slot.ToLowerInvariant()] = slotItem;
            plan.UpdatedAt = DateTime.UtcNow;

            await _mealPlanRepo.UpdateAsync(plan.Id, plan);
            return MapToDayResponse(day);
        }

        public async Task<AddMealsResultDto> AddMealsBatchToCurrentPlanAsync(string userId, List<AddMealRequestDto> requests)
        {
            var currentPlanRes = await GetCurrentMealPlanAsync(userId);
            var plan = await _mealPlanRepo.FindByIdAsync(currentPlanRes.Id);
            if (plan == null) throw new NotFoundException("Không tìm thấy thực đơn hiện tại.");

            var userAllergies = await GetUserAllergiesAsync(userId);
            int placed = 0;
            int skipped = 0;
            var modifiedDays = new HashSet<string>();

            foreach (var req in requests)
            {
                var day = plan.Days.FirstOrDefault(d => d.Date == req.Date);
                if (day == null)
                {
                    skipped++;
                    continue;
                }

                var slotItem = new MealSlotItem
                {
                    Id = Guid.NewGuid().ToString("N"),
                    RecipeId = req.SourceId,
                    Name = req.Name.Trim(),
                    Calories = req.Calories,
                    PrepMinutes = req.PrepMinutes > 0 ? req.PrepMinutes : 15,
                    Allergens = req.Allergens ?? new List<string>(),
                    Source = string.IsNullOrWhiteSpace(req.Source) ? "manual" : req.Source,
                    Portion = 1.0
                };

                var texts = (req.Ingredients ?? new List<string>()).Concat(new[] { req.Name });
                slotItem.AllergyConflicts = AllergyMatcher.FindConflicts(slotItem.Allergens, texts, userAllergies);

                day.Meals[req.Slot.ToLowerInvariant()] = slotItem;
                modifiedDays.Add(day.Date);
                placed++;
            }

            plan.UpdatedAt = DateTime.UtcNow;
            await _mealPlanRepo.UpdateAsync(plan.Id, plan);

            var changedDayResponses = plan.Days
                .Where(d => modifiedDays.Contains(d.Date))
                .Select(MapToDayResponse)
                .ToList();

            return new AddMealsResultDto
            {
                Placed = placed,
                Skipped = skipped,
                Days = changedDayResponses
            };
        }

        public async Task<MealPlanDayResponse> RemoveMealAsync(string userId, string planId, string date, string slot)
        {
            var plan = await _mealPlanRepo.FindByIdAsync(planId);
            if (plan == null || plan.IsDeleted || plan.UserId != userId)
            {
                throw new NotFoundException($"Không tìm thấy thực đơn với id: {planId}");
            }

            var day = plan.Days.FirstOrDefault(d => d.Date == date);
            if (day == null)
            {
                throw new BadRequestException($"Ngày {date} không thuộc thực đơn này.");
            }

            day.Meals.Remove(slot.ToLowerInvariant());
            plan.UpdatedAt = DateTime.UtcNow;

            await _mealPlanRepo.UpdateAsync(plan.Id, plan);
            return MapToDayResponse(day);
        }

        public async Task<IEnumerable<RecipeResponse>> GetSwapSuggestionsAsync(string userId, string planId, string date, string slot, int limit = 3)
        {
            var plan = await _mealPlanRepo.FindByIdAsync(planId);
            var userAllergies = await GetUserAllergiesAsync(userId);
            var slotNormalized = slot.ToLowerInvariant();

            var currentMealCalories = 400;
            if (plan != null)
            {
                var day = plan.Days.FirstOrDefault(d => d.Date == date);
                if (day != null && day.Meals.TryGetValue(slotNormalized, out var existing))
                {
                    currentMealCalories = existing.Calories > 0 ? existing.Calories : 400;
                }
            }

            var all = (await _recipeRepo.FindAsync(r => !r.IsDeleted && r.IsVegan)).ToList();

            // 1. Phải an toàn về dị ứng
            var safe = all.Where(recipe =>
            {
                var texts = recipe.Ingredients.Concat(new[] { recipe.Name });
                return !AllergyMatcher.FindConflicts(recipe.Allergens, texts, userAllergies).Any();
            }).ToList();

            // 2. Lọc theo MealType phù hợp
            var matchingType = safe.Where(r => r.MealTypes.Contains(slotNormalized)).ToList();
            if (!matchingType.Any()) matchingType = safe;

            // 3. Sắp xếp theo mức độ gần với lượng calo hiện tại (±15%)
            return matchingType
                .OrderBy(r => Math.Abs(r.Calories - currentMealCalories))
                .Take(limit)
                .Select(MapToRecipeResponse);
        }

        public async Task<IEnumerable<RecipeResponse>> GetMyRecipesAsync(string userId)
        {
            var items = await _recipeRepo.FindAsync(r => !r.IsDeleted && r.CreatedBy == userId);
            return items.Select(MapToRecipeResponse);
        }

        public async Task<RecipeResponse> CreateMyRecipeAsync(string userId, CreateRecipeRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Name))
            {
                throw new BadRequestException("Tên công thức không được để trống.");
            }

            var recipe = new Recipe
            {
                Name = request.Name.Trim(),
                NormalizedName = AllergyMatcher.RemoveDiacritics(request.Name).ToLowerInvariant(),
                ImageUrl = request.ImageUrl,
                Calories = request.Calories > 0 ? request.Calories : 300,
                ProteinG = request.ProteinG,
                CarbsG = request.CarbsG,
                FatG = request.FatG,
                FiberG = request.FiberG,
                Allergens = request.Allergens ?? new List<string>(),
                DietTags = request.DietTags ?? new List<string>(),
                Ingredients = request.Ingredients ?? new List<string>(),
                Instructions = request.Instructions ?? new List<string>(),
                MealTypes = new List<string> { "lunch", "dinner" },
                IsVegan = true,
                CreatedBy = userId,
                CreatedAt = DateTime.UtcNow
            };

            await _recipeRepo.CreateAsync(recipe);
            return MapToRecipeResponse(recipe);
        }

        private async Task<List<string>> GetUserAllergiesAsync(string userId)
        {
            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            return profile?.Allergies ?? new List<string>();
        }

        private static Recipe PickRecipe(List<Recipe> pool, Dictionary<string, int> counts, Random random)
        {
            // Ưu tiên chọn món ít lặp nhất
            var candidates = pool.OrderBy(r => counts.GetValueOrDefault(r.Id, 0)).Take(5).ToList();
            var pick = candidates[random.Next(candidates.Count)];
            counts[pick.Id] = counts.GetValueOrDefault(pick.Id, 0) + 1;
            return pick;
        }

        private static MealSlotItem MapToMealSlotItem(Recipe r, string source)
        {
            return new MealSlotItem
            {
                Id = Guid.NewGuid().ToString("N"),
                RecipeId = r.Id,
                Name = r.Name,
                Calories = r.Calories,
                ProteinG = r.ProteinG,
                CarbsG = r.CarbsG,
                FatG = r.FatG,
                FiberG = r.FiberG,
                Allergens = r.Allergens,
                DietTags = r.DietTags,
                PrepMinutes = r.PrepMinutes,
                ImageUrl = r.ImageUrl,
                Source = source,
                Portion = 1.0,
                SeasonalSwap = r.SeasonalSwap
            };
        }

        private static MealPlanResponse MapToResponse(MealPlan plan, List<string> userAllergies)
        {
            return new MealPlanResponse
            {
                Id = plan.Id,
                StartDate = plan.StartDate,
                Goal = plan.Goal,
                DailyTargets = new DailyTargetsDto
                {
                    Calories = plan.DailyTargets.Calories,
                    ProteinG = plan.DailyTargets.ProteinG,
                    CarbsG = plan.DailyTargets.CarbsG,
                    FatG = plan.DailyTargets.FatG,
                    FiberG = plan.DailyTargets.FiberG
                },
                Days = plan.Days.Select(MapToDayResponse).ToList()
            };
        }

        private static MealPlanDayResponse MapToDayResponse(MealPlanDay d)
        {
            var slotDtos = d.Meals.ToDictionary(
                kvp => kvp.Key,
                kvp => new MealSlotItemDto
                {
                    Id = kvp.Value.Id,
                    RecipeId = kvp.Value.RecipeId,
                    Name = kvp.Value.Name,
                    Calories = kvp.Value.Calories,
                    ProteinG = kvp.Value.ProteinG,
                    CarbsG = kvp.Value.CarbsG,
                    FatG = kvp.Value.FatG,
                    FiberG = kvp.Value.FiberG,
                    Allergens = kvp.Value.Allergens,
                    DietTags = kvp.Value.DietTags,
                    PrepMinutes = kvp.Value.PrepMinutes,
                    ImageUrl = kvp.Value.ImageUrl,
                    Source = kvp.Value.Source,
                    SourceName = kvp.Value.SourceName,
                    Portion = kvp.Value.Portion,
                    SeasonalSwap = kvp.Value.SeasonalSwap != null ? new SeasonalSwapDto
                    {
                        Ingredient = kvp.Value.SeasonalSwap.Ingredient,
                        RecipeId = kvp.Value.SeasonalSwap.RecipeId
                    } : null,
                    AllergyConflicts = kvp.Value.AllergyConflicts
                });

            return new MealPlanDayResponse
            {
                Date = d.Date,
                Meals = slotDtos,
                TotalCalories = slotDtos.Values.Sum(m => (int)Math.Round(m.Calories * m.Portion))
            };
        }

        private static RecipeResponse MapToRecipeResponse(Recipe r)
        {
            return new RecipeResponse
            {
                Id = r.Id,
                Name = r.Name,
                ImageUrl = r.ImageUrl,
                Calories = r.Calories,
                ProteinG = r.ProteinG,
                CarbsG = r.CarbsG,
                FatG = r.FatG,
                FiberG = r.FiberG,
                Allergens = r.Allergens,
                DietTags = r.DietTags,
                PrepMinutes = r.PrepMinutes,
                Ingredients = r.Ingredients,
                Instructions = r.Instructions,
                SeasonalSwap = r.SeasonalSwap != null ? new SeasonalSwapDto
                {
                    Ingredient = r.SeasonalSwap.Ingredient,
                    RecipeId = r.SeasonalSwap.RecipeId
                } : null
            };
        }

        private static DateTime GetMondayOfWeek(DateTime dt)
        {
            int diff = (7 + (dt.DayOfWeek - DayOfWeek.Monday)) % 7;
            return dt.AddDays(-1 * diff).Date;
        }

        private static string NormalizeStartDate(string? startDate)
        {
            if (string.IsNullOrWhiteSpace(startDate) || !DateTime.TryParse(startDate, out var dt))
            {
                return GetMondayOfWeek(DateTime.UtcNow).ToString("yyyy-MM-dd");
            }
            return dt.ToString("yyyy-MM-dd");
        }
    }
}

