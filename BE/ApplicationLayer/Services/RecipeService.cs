using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>Danh mục công thức, sửa và xoá công thức của tôi, bản tuỳ chỉnh, đánh giá, ghi chú.</summary>
    public class RecipeService : IRecipeService
    {
        private const string RecipeNotFound = "Không tìm thấy công thức.";
        private const string NoteNotFound = "Chưa có ghi chú.";
        private const int ReviewContentMin = 10;
        private const int ReviewContentMax = 500;
        private const int NoteContentMax = 2000;

        private readonly IGenericRepository<Recipe> _recipeRepo;
        private readonly IGenericRepository<RecipeReview> _reviewRepo;
        private readonly IGenericRepository<RecipeNote> _noteRepo;
        private readonly IGenericRepository<User> _userRepo;
        private readonly IGenericRepository<Post> _postRepo;

        public RecipeService(
            IGenericRepository<Recipe> recipeRepo,
            IGenericRepository<RecipeReview> reviewRepo,
            IGenericRepository<RecipeNote> noteRepo,
            IGenericRepository<User> userRepo,
            IGenericRepository<Post> postRepo)
        {
            _recipeRepo = recipeRepo;
            _reviewRepo = reviewRepo;
            _noteRepo = noteRepo;
            _userRepo = userRepo;
            _postRepo = postRepo;
        }

        public async Task<RecipeCatalogPageResponse> GetCatalogAsync(string? q, bool veganOnly, int? limit, string? cursor)
        {
            if (!string.IsNullOrWhiteSpace(cursor) && !MongoDB.Bson.ObjectId.TryParse(cursor, out _))
            {
                throw new BadRequestException("Cursor không hợp lệ.");
            }

            var pageSize = Math.Clamp(limit ?? 50, 1, 200);
            var term = string.IsNullOrWhiteSpace(q) ? null : AllergyMatcher.RemoveDiacritics(q.Trim()).ToLowerInvariant();

            Expression<Func<Recipe, bool>> filter = r =>
                !r.IsDeleted &&
                r.CreatedBy == null &&
                (!veganOnly || r.IsVegan) &&
                (term == null || r.NormalizedName.Contains(term));

            var rows = (await _recipeRepo.FindCursorAsync(filter, string.IsNullOrWhiteSpace(cursor) ? null : cursor, pageSize + 1)).ToList();
            var hasMore = rows.Count > pageSize;
            var items = rows.Take(pageSize).ToList();

            return new RecipeCatalogPageResponse
            {
                Items = items.Select(MealPlanService.MapToRecipeResponse).ToList(),
                NextCursor = hasMore ? items.Last().Id : null
            };
        }

        public async Task<RecipeResponse> GetByIdAsync(string? userId, string recipeId) =>
            MealPlanService.MapToRecipeResponse(await VisibleRecipeAsync(recipeId, userId));

        public async Task<RecipeResponse> UpdateMineAsync(string userId, string recipeId, CreateRecipeRequest request)
        {
            var recipe = await OwnRecipeAsync(recipeId, userId);
            RecipeRules.RequireValidRecipe(request);

            var (basedOnId, basedOnName) = await ResolveBasedOnAsync(userId, request.BasedOnRecipeId, recipe);

            recipe.Name = request.Name.Trim();
            recipe.NormalizedName = AllergyMatcher.RemoveDiacritics(request.Name).ToLowerInvariant();
            recipe.ImageUrl = request.ImageUrl;
            recipe.Calories = request.Calories;
            recipe.PrepMinutes = request.PrepMinutes;
            recipe.ProteinG = request.ProteinG;
            recipe.CarbsG = request.CarbsG;
            recipe.FatG = request.FatG;
            recipe.FiberG = request.FiberG;
            recipe.Allergens = request.Allergens ?? new List<string>();
            recipe.DietTags = request.DietTags ?? new List<string>();
            recipe.Ingredients = request.Ingredients ?? new List<string>();
            recipe.Instructions = request.Instructions ?? new List<string>();
            recipe.Servings = request.Servings;
            recipe.IngredientItems = request.IngredientItems;
            recipe.BasedOnRecipeId = basedOnId;
            recipe.BasedOnName = basedOnName;
            recipe.UpdatedAt = DateTime.UtcNow;

            await _recipeRepo.UpdateAsync(recipe.Id, recipe);
            return MealPlanService.MapToRecipeResponse(recipe);
        }

        public async Task DeleteMineAsync(string userId, string recipeId)
        {
            var recipe = await OwnRecipeAsync(recipeId, userId);
            recipe.IsDeleted = true;
            recipe.DeletedAt = DateTime.UtcNow;
            recipe.UpdatedAt = DateTime.UtcNow;
            await _recipeRepo.UpdateAsync(recipe.Id, recipe);
        }

        public async Task<RecipeResponse> CreateVariantAsync(string userId, string recipeId, CreateRecipeVariantRequest request)
        {
            var baseRecipe = await VisibleRecipeAsync(recipeId, userId);

            var name = request.Name?.Trim() ?? string.Empty;
            if (name.Length < 2 || name.Length > 80)
            {
                throw new BadRequestException("Tên công thức phải có từ 2 đến 80 ký tự.", "invalid_name");
            }
            RecipeRules.RequireVegan(name, "Tên công thức");

            var swaps = request.Swaps ?? new List<RecipeSwapRequest>();
            var removed = (request.Removed ?? new List<string>()).ToHashSet(StringComparer.Ordinal);
            if (!swaps.Any() && !removed.Any())
            {
                throw new BadRequestException("Bạn chưa thay đổi gì so với công thức gốc.", "no_changes");
            }

            var baseItems = baseRecipe.IngredientItems ?? new List<RecipeIngredientItem>();
            var items = new List<RecipeIngredientItem>();
            var notes = new List<RecipeCustomization>();

            var unknownSwap = swaps.FirstOrDefault(s => baseItems.All(i => i.Key != s.IngredientKey));
            if (unknownSwap != null || removed.Any(key => baseItems.All(i => i.Key != key)))
            {
                throw new BadRequestException("Công thức gốc không có nguyên liệu này.", "invalid_substitute");
            }

            foreach (var item in baseItems)
            {
                if (removed.Contains(item.Key))
                {
                    if (item.IsSignature)
                    {
                        throw new BadRequestException($"'{item.Name}' là nguyên liệu đặc trưng của món nên không bỏ được.", "signature_required");
                    }
                    notes.Add(new RecipeCustomization { Type = "remove", Name = item.Name });
                    continue;
                }

                var swap = swaps.FirstOrDefault(s => s.IngredientKey == item.Key);
                if (swap == null)
                {
                    items.Add(item);
                    continue;
                }

                var sub = item.Substitutes.FirstOrDefault(s => s.Key == swap.SubstituteKey);
                if (sub == null)
                {
                    throw new BadRequestException($"'{item.Name}' không có món thay thế này.", "invalid_substitute");
                }
                if (item.IsSignature && !string.IsNullOrEmpty(sub.Role) && !string.Equals(sub.Role, item.Role, StringComparison.OrdinalIgnoreCase))
                {
                    throw new BadRequestException($"'{item.Name}' là nguyên liệu đặc trưng, chỉ đổi được trong cùng vai trò.", "signature_required");
                }

                notes.Add(new RecipeCustomization { Type = "swap", From = item.Name, To = sub.Name });
                items.Add(new RecipeIngredientItem
                {
                    Key = item.Key,
                    IngredientId = sub.IngredientId,
                    Name = sub.Name,
                    Quantity = sub.Quantity,
                    Unit = sub.Unit,
                    Role = sub.Role ?? item.Role,
                    IsSignature = item.IsSignature,
                    IsOptional = item.IsOptional,
                    Allergens = sub.Allergens,
                    Nutrition = sub.Nutrition,
                    Substitutes = new List<RecipeSubstituteItem>()
                });
            }

            var everyRowHasNutrition = items.All(i => i.Nutrition?.Calories != null);
            var everyRowHasAllergens = items.All(i => i.Allergens != null);

            var variant = new Recipe
            {
                Name = name,
                NormalizedName = AllergyMatcher.RemoveDiacritics(name).ToLowerInvariant(),
                ImageUrl = baseRecipe.ImageUrl,
                MealTypes = baseRecipe.MealTypes,
                PrepMinutes = baseRecipe.PrepMinutes,
                Calories = everyRowHasNutrition ? (int)Math.Round(items.Sum(i => i.Nutrition!.Calories ?? 0)) : baseRecipe.Calories,
                ProteinG = everyRowHasNutrition ? Math.Round(items.Sum(i => i.Nutrition!.ProteinG ?? 0), 1) : baseRecipe.ProteinG,
                CarbsG = everyRowHasNutrition ? Math.Round(items.Sum(i => i.Nutrition!.CarbsG ?? 0), 1) : baseRecipe.CarbsG,
                FatG = everyRowHasNutrition ? Math.Round(items.Sum(i => i.Nutrition!.FatG ?? 0), 1) : baseRecipe.FatG,
                FiberG = everyRowHasNutrition ? Math.Round(items.Sum(i => i.Nutrition!.FiberG ?? 0), 1) : baseRecipe.FiberG,
                NutritionEstimated = !everyRowHasNutrition,
                // Không biết chắc từng dòng thì giữ cả dị ứng của món gốc: báo thừa còn hơn báo thiếu.
                Allergens = (everyRowHasAllergens
                        ? items.SelectMany(i => i.Allergens!)
                        : baseRecipe.Allergens.Concat(items.SelectMany(i => i.Allergens ?? new List<string>())))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList(),
                DietTags = baseRecipe.DietTags,
                Ingredients = items.Select(RowText).ToList(),
                Instructions = baseRecipe.Instructions,
                IsVegan = true,
                Servings = baseRecipe.Servings,
                IngredientItems = items,
                BasedOnRecipeId = baseRecipe.Id,
                BasedOnName = baseRecipe.Name,
                Customizations = notes,
                CreatedBy = userId,
                CreatedAt = DateTime.UtcNow
            };

            await _recipeRepo.CreateAsync(variant);
            return MealPlanService.MapToRecipeResponse(variant);
        }

        private static string RowText(RecipeIngredientItem item)
        {
            if (item.Quantity is not > 0) return item.Name;
            return $"{item.Name} {item.Quantity.Value.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)} {item.Unit}".TrimEnd();
        }

        public async Task<RecipeReviewsPageResponse> GetReviewsAsync(string? userId, string recipeId, string? cursor, int? limit)
        {
            await PublicRecipeAsync(recipeId);

            if (!string.IsNullOrWhiteSpace(cursor) && !MongoDB.Bson.ObjectId.TryParse(cursor, out _))
            {
                throw new BadRequestException("Cursor không hợp lệ.");
            }
            var pageSize = Math.Clamp(limit ?? 10, 1, 50);

            var all = (await _reviewRepo.FindAsync(r => r.RecipeId == recipeId && !r.IsDeleted)).ToList();
            var mine = string.IsNullOrEmpty(userId) ? null : all.FirstOrDefault(r => r.UserId == userId);

            var rows = (await _reviewRepo.FindCursorAsync(
                r => r.RecipeId == recipeId && !r.IsDeleted && (userId == null || r.UserId != userId),
                string.IsNullOrWhiteSpace(cursor) ? null : cursor,
                pageSize + 1)).ToList();
            var hasMore = rows.Count > pageSize;
            var items = rows.Take(pageSize).ToList();

            var authors = await AuthorsOfAsync(items.Select(r => r.UserId).Concat(mine != null ? new[] { mine.UserId } : Array.Empty<string>()));

            return new RecipeReviewsPageResponse
            {
                RecipeId = recipeId,
                AverageRating = Average(all),
                RatingCount = all.Count,
                Distribution = Enumerable.Range(1, 5).Reverse().ToDictionary(n => n.ToString(), n => all.Count(r => r.Rating == n)),
                MyReview = mine == null ? null : MapReview(mine, authors),
                Items = items.Select(r => MapReview(r, authors)).ToList(),
                NextCursor = hasMore ? items.Last().Id : null
            };
        }

        public async Task<ReviewWriteResponse> UpsertMyReviewAsync(string userId, string recipeId, UpsertRecipeReviewRequest request)
        {
            var recipe = await _recipeRepo.FindByIdAsync(recipeId);
            if (recipe == null || recipe.IsDeleted) throw new NotFoundException(RecipeNotFound);
            if (recipe.CreatedBy == userId)
            {
                throw new ForbiddenException("Bạn không thể đánh giá công thức của chính mình.", "own_recipe");
            }
            if (recipe.CreatedBy != null)
            {
                throw new NotFoundException(RecipeNotFound, "private_recipe");
            }

            if (request.Rating is < 1 or > 5)
            {
                throw new BadRequestException("Số sao phải từ 1 đến 5.", "invalid_rating");
            }
            var content = string.IsNullOrWhiteSpace(request.Content) ? null : request.Content.Trim();
            if (content != null && (content.Length < ReviewContentMin || content.Length > ReviewContentMax))
            {
                throw new BadRequestException($"Nội dung đánh giá phải có từ {ReviewContentMin} đến {ReviewContentMax} ký tự.", "invalid_content");
            }

            var existing = await _reviewRepo.FirstOrDefaultAsync(r => r.RecipeId == recipeId && r.UserId == userId);
            RecipeReview review;
            if (existing == null)
            {
                review = new RecipeReview { RecipeId = recipeId, UserId = userId, Rating = request.Rating, Content = content, CreatedAt = DateTime.UtcNow };
                await _reviewRepo.CreateAsync(review);
            }
            else
            {
                review = existing;
                review.Rating = request.Rating;
                review.Content = content;
                review.IsDeleted = false;
                review.DeletedAt = null;
                review.UpdatedAt = DateTime.UtcNow;
                await _reviewRepo.UpdateAsync(review.Id, review);
            }

            var totals = await RefreshTotalsAsync(recipeId);
            var authors = await AuthorsOfAsync(new[] { userId });
            return new ReviewWriteResponse
            {
                Review = MapReview(review, authors),
                AverageRating = totals.AverageRating,
                RatingCount = totals.RatingCount
            };
        }

        public async Task<RatingTotalsResponse> DeleteMyReviewAsync(string userId, string recipeId)
        {
            await PublicRecipeAsync(recipeId);

            var existing = await _reviewRepo.FirstOrDefaultAsync(r => r.RecipeId == recipeId && r.UserId == userId && !r.IsDeleted);
            if (existing != null)
            {
                existing.IsDeleted = true;
                existing.DeletedAt = DateTime.UtcNow;
                await _reviewRepo.UpdateAsync(existing.Id, existing);
            }
            return await RefreshTotalsAsync(recipeId);
        }

        public async Task<RecipeNoteResponse> GetMyNoteAsync(string userId, string recipeId)
        {
            await VisibleRecipeAsync(recipeId, userId);
            var note = await _noteRepo.FirstOrDefaultAsync(n => n.RecipeId == recipeId && n.UserId == userId && !n.IsDeleted);
            if (note == null) throw new NotFoundException(NoteNotFound, "no_note");
            return MapNote(note);
        }

        public async Task<RecipeNoteResponse?> SaveMyNoteAsync(string userId, string recipeId, SaveRecipeNoteRequest request)
        {
            await VisibleRecipeAsync(recipeId, userId);

            var content = request.Content?.Trim() ?? string.Empty;
            if (content.Length > NoteContentMax)
            {
                throw new BadRequestException($"Ghi chú tối đa {NoteContentMax} ký tự.", "invalid_content");
            }

            var existing = await _noteRepo.FirstOrDefaultAsync(n => n.RecipeId == recipeId && n.UserId == userId);
            if (content.Length == 0)
            {
                if (existing != null && !existing.IsDeleted)
                {
                    existing.IsDeleted = true;
                    existing.DeletedAt = DateTime.UtcNow;
                    await _noteRepo.UpdateAsync(existing.Id, existing);
                }
                return null;
            }

            if (existing == null)
            {
                existing = new RecipeNote { RecipeId = recipeId, UserId = userId, Content = content, CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow };
                await _noteRepo.CreateAsync(existing);
            }
            else
            {
                existing.Content = content;
                existing.IsDeleted = false;
                existing.DeletedAt = null;
                existing.UpdatedAt = DateTime.UtcNow;
                await _noteRepo.UpdateAsync(existing.Id, existing);
            }
            return MapNote(existing);
        }

        public async Task DeleteMyNoteAsync(string userId, string recipeId)
        {
            await VisibleRecipeAsync(recipeId, userId);
            var existing = await _noteRepo.FirstOrDefaultAsync(n => n.RecipeId == recipeId && n.UserId == userId && !n.IsDeleted);
            if (existing != null)
            {
                existing.IsDeleted = true;
                existing.DeletedAt = DateTime.UtcNow;
                await _noteRepo.UpdateAsync(existing.Id, existing);
            }
        }

        public async Task<IEnumerable<PostResponse>> GetRelatedPostsAsync(string? userId, string recipeId)
        {
            var recipe = await VisibleRecipeAsync(recipeId, userId);
            var name = recipe.Name.ToLowerInvariant();

            var posts = (await _postRepo.FindPagedAsync(
                p => !p.IsDeleted && p.Status == "Published" && p.Type == "recipe" && (p.Title.ToLower().Contains(name) || p.Body.ToLower().Contains(name)),
                1,
                10,
                sortDesc: p => p.CreatedAt)).ToList();

            var authorIds = posts.Select(p => p.UserId);
            var authors = await AuthorsOfAsync(authorIds);
            return posts.Select(p => PostService.MapToResponse(
                p,
                authors.TryGetValue(p.UserId, out var a) ? a : new AuthorSummaryDto { Id = p.UserId, FullName = "Thành viên" },
                false)).ToList();
        }

        private async Task<Recipe> VisibleRecipeAsync(string recipeId, string? userId)
        {
            var recipe = await _recipeRepo.FindByIdAsync(recipeId);
            if (recipe == null || !RecipeRules.CanSee(recipe, userId))
            {
                throw new NotFoundException(RecipeNotFound);
            }
            return recipe;
        }

        /// <summary>Đánh giá chỉ có trên công thức công khai; công thức riêng tư trả private_recipe, kể cả với chủ.</summary>
        private async Task<Recipe> PublicRecipeAsync(string recipeId)
        {
            var recipe = await _recipeRepo.FindByIdAsync(recipeId);
            if (recipe == null || recipe.IsDeleted) throw new NotFoundException(RecipeNotFound);
            if (recipe.CreatedBy != null) throw new NotFoundException(RecipeNotFound, "private_recipe");
            return recipe;
        }

        private async Task<Recipe> OwnRecipeAsync(string recipeId, string userId)
        {
            var recipe = await _recipeRepo.FindByIdAsync(recipeId);
            if (recipe == null || recipe.IsDeleted || recipe.CreatedBy != userId)
            {
                throw new NotFoundException(RecipeNotFound);
            }
            return recipe;
        }

        private async Task<(string? Id, string? Name)> ResolveBasedOnAsync(string userId, string? basedOnRecipeId, Recipe current)
        {
            if (string.IsNullOrWhiteSpace(basedOnRecipeId)) return (current.BasedOnRecipeId, current.BasedOnName);
            if (basedOnRecipeId == current.Id)
            {
                throw new BadRequestException("Công thức không thể dựa trên chính nó.", "invalid_based_on");
            }
            var based = await _recipeRepo.FindByIdAsync(basedOnRecipeId);
            if (based == null || !RecipeRules.CanSee(based, userId))
            {
                throw new BadRequestException("Không tìm thấy công thức gốc.", "invalid_based_on");
            }
            return (based.Id, based.Name);
        }

        private async Task<RatingTotalsResponse> RefreshTotalsAsync(string recipeId)
        {
            var all = (await _reviewRepo.FindAsync(r => r.RecipeId == recipeId && !r.IsDeleted)).ToList();
            var totals = new RatingTotalsResponse { AverageRating = Average(all), RatingCount = all.Count };
            await _recipeRepo.UpdateFieldAsync(recipeId, r => r.AverageRating, totals.AverageRating);
            await _recipeRepo.UpdateFieldAsync(recipeId, r => r.RatingCount, totals.RatingCount);
            return totals;
        }

        private static double? Average(List<RecipeReview> reviews) =>
            reviews.Any() ? Math.Round(reviews.Average(r => r.Rating), 1) : null;

        private async Task<Dictionary<string, AuthorSummaryDto>> AuthorsOfAsync(IEnumerable<string> ids)
        {
            var userIds = ids.Distinct().ToList();
            if (!userIds.Any()) return new Dictionary<string, AuthorSummaryDto>();
            return (await _userRepo.FindAsync(u => userIds.Contains(u.Id) && !u.IsDeleted))
                .ToDictionary(
                    u => u.Id,
                    u => new AuthorSummaryDto
                    {
                        Id = u.Id,
                        FullName = u.FullName,
                        IsVerifiedChef = u.Role?.Equals("Chef", StringComparison.OrdinalIgnoreCase) == true
                    });
        }

        private static RecipeReviewResponse MapReview(RecipeReview r, Dictionary<string, AuthorSummaryDto> authors) => new()
        {
            Id = r.Id,
            Rating = r.Rating,
            Content = r.Content,
            Author = authors.TryGetValue(r.UserId, out var a) ? a : new AuthorSummaryDto { Id = r.UserId, FullName = "Thành viên" },
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt
        };

        private static RecipeNoteResponse MapNote(RecipeNote n) => new()
        {
            RecipeId = n.RecipeId,
            Content = n.Content,
            UpdatedAt = n.UpdatedAt ?? n.CreatedAt
        };
    }
}
