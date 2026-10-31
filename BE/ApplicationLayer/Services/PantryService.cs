using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    public class PantryService : IPantryService
    {
        private readonly IGenericRepository<PantryItem> _pantryRepo;
        private readonly IGenericRepository<Ingredient> _ingredientRepo;
        private readonly IGenericRepository<HealthProfile> _profileRepo;

        public PantryService(
            IGenericRepository<PantryItem> pantryRepo,
            IGenericRepository<Ingredient> ingredientRepo,
            IGenericRepository<HealthProfile> profileRepo)
        {
            _pantryRepo = pantryRepo;
            _ingredientRepo = ingredientRepo;
            _profileRepo = profileRepo;
        }

        public async Task<IEnumerable<PantryItemResponse>> GetPantryItemsAsync(string userId, int? expiringInDays)
        {
            var userAllergies = await GetUserAllergiesAsync(userId);

            var items = await _pantryRepo.FindAsync(x => x.UserId == userId && !x.IsDeleted);

            if (expiringInDays.HasValue && expiringInDays.Value > 0)
            {
                var threshold = DateTime.UtcNow.AddDays(expiringInDays.Value);
                items = items.Where(x => x.ExpiryDate.HasValue && x.ExpiryDate.Value <= threshold);
            }

            return items
                .OrderBy(x => x.ExpiryDate.HasValue ? 0 : 1)
                .ThenBy(x => x.ExpiryDate)
                .ThenByDescending(x => x.CreatedAt)
                .Select(item => MapToResponse(item, userAllergies));
        }

        public async Task<PantryItemResponse> AddPantryItemAsync(string userId, AddPantryItemRequest request)
        {
            var items = await AddPantryItemsBatchAsync(userId, new List<AddPantryItemRequest> { request });
            return items.First();
        }

        public async Task<IEnumerable<PantryItemResponse>> AddPantryItemsBatchAsync(string userId, List<AddPantryItemRequest> requests)
        {
            if (requests == null || !requests.Any())
            {
                return Enumerable.Empty<PantryItemResponse>();
            }

            var userAllergies = await GetUserAllergiesAsync(userId);
            var results = new List<PantryItemResponse>();

            // Lấy danh sách nguyên liệu hiện có trong tủ của user để gộp nếu trùng tên
            var existingPantry = (await _pantryRepo.FindAsync(x => x.UserId == userId && !x.IsDeleted)).ToList();

            foreach (var req in requests)
            {
                var trimmedName = req.Ingredient.Trim();
                if (string.IsNullOrWhiteSpace(trimmedName)) continue;

                var normalized = AllergyMatcher.RemoveDiacritics(trimmedName).ToLowerInvariant();

                // Tìm trong danh mục nguyên liệu chuẩn
                var matchedIngredient = await _ingredientRepo.FirstOrDefaultAsync(i =>
                    !i.IsDeleted &&
                    (i.NormalizedName == normalized || i.Name.ToLower() == trimmedName.ToLower() || i.Aliases.Contains(trimmedName)));

                var isVegan = VeganClassifier.ClassifyIsVegan(trimmedName, matchedIngredient);
                var allergens = matchedIngredient?.Allergens ?? new List<string>();

                // Kiểm tra xem món này đã có trong tủ chưa
                var duplicate = existingPantry.FirstOrDefault(p =>
                    (p.NormalizedName == normalized || AllergyMatcher.RemoveDiacritics(p.Ingredient).ToLowerInvariant() == normalized));


                if (duplicate != null)
                {
                    if (req.Quantity > 0) duplicate.Quantity = req.Quantity;
                    if (req.ExpiryDate.HasValue) duplicate.ExpiryDate = req.ExpiryDate;
                    if (req.ScannedAt.HasValue) duplicate.ScannedAt = req.ScannedAt;
                    duplicate.NormalizedName = normalized;
                    duplicate.IsVegan = isVegan;
                    if (allergens.Any()) duplicate.Allergens = allergens;
                    duplicate.UpdatedAt = DateTime.UtcNow;

                    await _pantryRepo.UpdateAsync(duplicate.Id, duplicate);
                    results.Add(MapToResponse(duplicate, userAllergies));
                }
                else
                {
                    var newItem = new PantryItem
                    {
                        UserId = userId,
                        Ingredient = trimmedName,
                        NormalizedName = normalized,
                        IngredientId = matchedIngredient?.Id,
                        Category = matchedIngredient?.Category ?? "vegetable",
                        CaloriesPer100g = matchedIngredient?.CaloriesPer100g,
                        Quantity = req.Quantity > 0 ? req.Quantity : 1.0,
                        Unit = string.IsNullOrWhiteSpace(req.Unit) ? "phần" : req.Unit.Trim(),
                        ExpiryDate = req.ExpiryDate,
                        ScannedAt = req.ScannedAt,
                        IsVegan = isVegan,
                        Allergens = allergens,
                        Source = req.ScannedAt.HasValue ? "vision" : "manual",
                        CreatedAt = DateTime.UtcNow
                    };

                    await _pantryRepo.CreateAsync(newItem);
                    existingPantry.Add(newItem);
                    results.Add(MapToResponse(newItem, userAllergies));
                }
            }

            return results;
        }

        public async Task<PantryItemResponse> UpdatePantryItemAsync(string userId, string id, UpdatePantryItemRequest request)
        {
            var item = await _pantryRepo.FindByIdAsync(id);
            if (item == null || item.IsDeleted || item.UserId != userId)
            {
                throw new NotFoundException($"Không tìm thấy nguyên liệu với id: {id}");
            }

            if (request.Quantity > 0) item.Quantity = request.Quantity;
            if (!string.IsNullOrWhiteSpace(request.Unit)) item.Unit = request.Unit.Trim();
            if (request.ExpiryDate.HasValue) item.ExpiryDate = request.ExpiryDate;
            item.UpdatedAt = DateTime.UtcNow;

            await _pantryRepo.UpdateAsync(id, item);

            var userAllergies = await GetUserAllergiesAsync(userId);
            return MapToResponse(item, userAllergies);
        }

        public async Task<bool> DeletePantryItemAsync(string userId, string id)
        {
            var item = await _pantryRepo.FindByIdAsync(id);
            if (item == null || item.IsDeleted || item.UserId != userId)
            {
                return false;
            }

            item.IsDeleted = true;
            item.DeletedAt = DateTime.UtcNow;
            await _pantryRepo.UpdateAsync(id, item);
            return true;
        }

        public async Task<bool> ClearPantryAsync(string userId)
        {
            var items = (await _pantryRepo.FindAsync(x => x.UserId == userId && !x.IsDeleted)).ToList();
            foreach (var item in items)
            {
                item.IsDeleted = true;
                item.DeletedAt = DateTime.UtcNow;
                await _pantryRepo.UpdateAsync(item.Id, item);
            }
            return true;
        }

        public async Task<IEnumerable<IngredientResponse>> SearchIngredientsAsync(string? q, bool veganOnly = true)
        {
            var all = await _ingredientRepo.FindAsync(x => !x.IsDeleted && (!veganOnly || x.IsVegan));

            if (!string.IsNullOrWhiteSpace(q))
            {
                var queryNormalized = AllergyMatcher.RemoveDiacritics(q.Trim()).ToLowerInvariant();
                all = all.Where(x =>
                    x.NormalizedName.Contains(queryNormalized) ||
                    x.Name.ToLowerInvariant().Contains(q.Trim().ToLowerInvariant()) ||
                    x.Aliases.Any(a => AllergyMatcher.RemoveDiacritics(a).ToLowerInvariant().Contains(queryNormalized)));
            }

            return all.Select(MapToIngredientResponse);
        }

        public async Task<IngredientResponse> GetIngredientByIdAsync(string id)
        {
            var item = await _ingredientRepo.FindByIdAsync(id);
            if (item == null || item.IsDeleted)
            {
                throw new NotFoundException($"Không tìm thấy nguyên liệu với id: {id}");
            }

            return MapToIngredientResponse(item);
        }

        private async Task<List<string>> GetUserAllergiesAsync(string userId)
        {
            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            return profile?.Allergies ?? new List<string>();
        }

        private static PantryItemResponse MapToResponse(PantryItem item, List<string> userAllergies)
        {
            string? warning = null;
            if (userAllergies.Any())
            {
                var conflicts = AllergyMatcher.FindConflicts(
                    dishAllergenTags: item.Allergens ?? Enumerable.Empty<string>(),
                    dishTexts: new[] { item.Ingredient },
                    userAllergies: userAllergies);

                if (conflicts.Any())
                {
                    warning = $"Cảnh báo dị ứng: {string.Join(", ", conflicts)}";
                }
            }

            return new PantryItemResponse
            {
                Id = item.Id,
                Ingredient = item.Ingredient,
                ScannedAt = item.ScannedAt,
                IngredientId = item.IngredientId,
                Category = item.Category,
                CaloriesPer100g = item.CaloriesPer100g,
                Quantity = item.Quantity,
                Unit = item.Unit,
                ExpiryDate = item.ExpiryDate,
                IsVegan = item.IsVegan,
                AllergyWarning = warning
            };
        }

        private static IngredientResponse MapToIngredientResponse(Ingredient i)
        {
            return new IngredientResponse
            {
                Id = i.Id,
                Name = i.Name,
                Category = i.Category,
                CaloriesPer100g = i.CaloriesPer100g,
                ProteinG = i.ProteinG,
                CarbsG = i.CarbsG,
                FatG = i.FatG,
                FiberG = i.FiberG,
                Allergens = i.Allergens,
                IsVegan = i.IsVegan,
                Aliases = i.Aliases,
                GoodFor = i.GoodFor,
                CautionFor = i.CautionFor
            };
        }
    }
}

