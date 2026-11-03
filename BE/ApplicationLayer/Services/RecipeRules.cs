using System;
using System.Collections.Generic;
using System.Linq;
using ApplicationLayer.DTOs.MealPlan;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;

namespace ApplicationLayer.Services
{
    /// <summary>Kiểm tra dữ liệu ghi của công thức và món trong thực đơn, dùng chung cho mọi route ghi (B41).</summary>
    internal static class RecipeRules
    {
        public const int MaxCalories = 5000;
        public const int MaxPrepMinutes = 1440;
        public const double MaxMacroGrams = 1000;

        public static readonly HashSet<string> MealSlots = new(StringComparer.OrdinalIgnoreCase)
        {
            "breakfast", "snack_am", "lunch", "snack_pm", "dinner", "snack_late"
        };

        public static readonly HashSet<string> MealSources = new(StringComparer.OrdinalIgnoreCase)
        {
            "ai", "manual", "user_recipe", "chef", "fridge_scan", "recipe"
        };

        public static void RequireSlot(string? slot)
        {
            if (string.IsNullOrWhiteSpace(slot) || !MealSlots.Contains(slot.Trim()))
            {
                throw new BadRequestException("Bữa ăn không hợp lệ. Các bữa hợp lệ: breakfast, snack_am, lunch, snack_pm, dinner, snack_late.", "invalid_slot");
            }
        }

        public static void RequireSource(string? source)
        {
            if (!string.IsNullOrWhiteSpace(source) && !MealSources.Contains(source.Trim()))
            {
                throw new BadRequestException("Nguồn món không hợp lệ. Các nguồn hợp lệ: ai, manual, user_recipe, chef, fridge_scan, recipe.", "invalid_source");
            }
        }

        public static void RequireVegan(string name, string what)
        {
            if (!VeganClassifier.IsVegan(name))
            {
                throw new BadRequestException($"{what} '{name.Trim()}' không thuần chay. VeganLife chỉ chấp nhận món thuần chay.", "not_vegan");
            }
        }

        /// <summary>Trả null khi hợp lệ, để route thêm hàng loạt bỏ qua dòng lỗi thay vì huỷ cả lô.</summary>
        public static string? MealProblem(AddMealRequestDto request, double maxPortion)
        {
            if (string.IsNullOrWhiteSpace(request.Slot) || !MealSlots.Contains(request.Slot.Trim())) return "invalid_slot";
            if (!string.IsNullOrWhiteSpace(request.Source) && !MealSources.Contains(request.Source.Trim())) return "invalid_source";
            if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Trim().Length > 200) return "invalid_name";
            if (!VeganClassifier.IsVegan(request.Name)) return "not_vegan";
            if (request.Ingredients != null && request.Ingredients.Any(i => !string.IsNullOrWhiteSpace(i) && !VeganClassifier.IsVegan(i))) return "not_vegan";
            if (request.Calories < 0 || request.Calories > MaxCalories) return "invalid_calories";
            if (request.Portion.HasValue && (request.Portion.Value <= 0 || request.Portion.Value > maxPortion)) return "invalid_portion";
            if (IsBadMacro(request.ProteinG) || IsBadMacro(request.CarbsG) || IsBadMacro(request.FatG) || IsBadMacro(request.FiberG)) return "invalid_macro";
            if (request.PrepMinutes is < 0 or > MaxPrepMinutes) return "invalid_prep_minutes";
            return null;
        }

        public static void RequireValidMeal(AddMealRequestDto request, double maxPortion)
        {
            switch (MealProblem(request, maxPortion))
            {
                case null: return;
                case "invalid_slot": RequireSlot(request.Slot); return;
                case "invalid_source": RequireSource(request.Source); return;
                case "invalid_name": throw new BadRequestException("Tên món là bắt buộc và tối đa 200 ký tự.", "invalid_name");
                case "not_vegan": throw new BadRequestException("Món này không thuần chay. VeganLife chỉ chấp nhận món thuần chay.", "not_vegan");
                case "invalid_calories": throw new BadRequestException($"Calories phải nằm trong khoảng từ 0 đến {MaxCalories} kcal.", "invalid_calories");
                case "invalid_portion": throw new BadRequestException($"Portion phải nằm trong khoảng từ 0.1 đến {maxPortion}.", "invalid_portion");
                case "invalid_macro": throw new BadRequestException($"Dinh dưỡng phải nằm trong khoảng từ 0 đến {MaxMacroGrams} g.", "invalid_macro");
                default: throw new BadRequestException($"Thời gian nấu phải nằm trong khoảng từ 0 đến {MaxPrepMinutes} phút.", "invalid_prep_minutes");
            }
        }

        public static void RequireValidRecipe(CreateRecipeRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.Name))
            {
                throw new BadRequestException("Tên công thức không được để trống.", "invalid_name");
            }
            if (request.Name.Trim().Length > 120)
            {
                throw new BadRequestException("Tên công thức tối đa 120 ký tự.", "invalid_name");
            }

            // B13: chỉ nhận món thuần chay (chặn thịt bò xào...)
            if (!VeganClassifier.IsVegan(request.Name))
            {
                throw new BadRequestException("Tên công thức chứa nguyên liệu không thuần chay. VeganLife chỉ chấp nhận các món thuần chay.", "not_vegan");
            }

            if (request.Calories < 0 || request.Calories > MaxCalories)
            {
                throw new BadRequestException($"Calories phải nằm trong khoảng từ 0 đến {MaxCalories} kcal.", "invalid_calories");
            }
            if (request.PrepMinutes is < 0 or > MaxPrepMinutes)
            {
                throw new BadRequestException($"Thời gian nấu phải nằm trong khoảng từ 0 đến {MaxPrepMinutes} phút.", "invalid_prep_minutes");
            }
            if (IsBadMacro(request.ProteinG) || IsBadMacro(request.CarbsG) || IsBadMacro(request.FatG) || IsBadMacro(request.FiberG))
            {
                throw new BadRequestException($"Dinh dưỡng phải nằm trong khoảng từ 0 đến {MaxMacroGrams} g.", "invalid_macro");
            }
            if (request.Servings is < 1 or > 50)
            {
                throw new BadRequestException("Số phần phải nằm trong khoảng từ 1 đến 50.", "invalid_servings");
            }
            RequireList(request.Ingredients, 100, 200, "Nguyên liệu");
            RequireList(request.Instructions, 100, 2000, "Các bước");
            RequireList(request.Allergens, 20, 60, "Dị ứng");
            RequireList(request.DietTags, 20, 60, "Nhãn");

            foreach (var ingredient in request.Ingredients ?? new List<string>())
            {
                if (!VeganClassifier.IsVegan(ingredient))
                {
                    throw new BadRequestException($"Nguyên liệu '{ingredient}' không thuần chay. VeganLife chỉ chấp nhận các nguyên liệu thuần chay.", "not_vegan");
                }
            }

            if (!string.IsNullOrWhiteSpace(request.ImageUrl))
            {
                var url = request.ImageUrl.Trim();
                var isLocal = url.StartsWith("/uploads/", StringComparison.OrdinalIgnoreCase);
                var isWeb = Uri.TryCreate(url, UriKind.Absolute, out var parsed) && (parsed.Scheme == Uri.UriSchemeHttp || parsed.Scheme == Uri.UriSchemeHttps);
                if (url.Length > 2000 || (!isLocal && !isWeb))
                {
                    throw new BadRequestException("Ảnh của công thức phải là đường dẫn http(s) hoặc ảnh đã tải lên.", "invalid_image");
                }
            }

            RequireValidItems(request.IngredientItems);
        }

        private static void RequireValidItems(List<RecipeIngredientItem>? items)
        {
            if (items == null) return;
            if (items.Count > 100)
            {
                throw new BadRequestException("Tối đa 100 dòng nguyên liệu.", "invalid_ingredient_items");
            }

            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in items)
            {
                if (string.IsNullOrWhiteSpace(item.Key) || string.IsNullOrWhiteSpace(item.Name) || !keys.Add(item.Key))
                {
                    throw new BadRequestException("Mỗi dòng nguyên liệu phải có key không trùng và có tên.", "invalid_ingredient_items");
                }
                RequireVegan(item.Name, "Nguyên liệu");
                RequireAmount(item.Quantity, item.Nutrition);
                foreach (var sub in item.Substitutes ?? new List<RecipeSubstituteItem>())
                {
                    if (string.IsNullOrWhiteSpace(sub.Key) || string.IsNullOrWhiteSpace(sub.Name))
                    {
                        throw new BadRequestException("Mỗi nguyên liệu thay thế phải có key và tên.", "invalid_ingredient_items");
                    }
                    RequireVegan(sub.Name, "Nguyên liệu thay thế");
                    RequireAmount(sub.Quantity, sub.Nutrition);
                }
            }
        }

        private static void RequireAmount(double? quantity, RecipeNutrition? nutrition)
        {
            if (quantity is < 0 || IsBadMacro(nutrition?.ProteinG) || IsBadMacro(nutrition?.CarbsG) || IsBadMacro(nutrition?.FatG) || IsBadMacro(nutrition?.FiberG)
                || nutrition?.Calories is < 0 or > MaxCalories)
            {
                throw new BadRequestException("Định lượng và dinh dưỡng của nguyên liệu không được âm.", "invalid_ingredient_items");
            }
        }

        private static bool IsBadMacro(double? value) => value is < 0 or > MaxMacroGrams;

        private static void RequireList(List<string>? values, int maxCount, int maxLength, string what)
        {
            if (values == null) return;
            if (values.Count > maxCount)
            {
                throw new BadRequestException($"{what} tối đa {maxCount} dòng.", "invalid_list");
            }
            if (values.Any(v => v == null || v.Length > maxLength))
            {
                throw new BadRequestException($"Mỗi dòng {what.ToLowerInvariant()} tối đa {maxLength} ký tự.", "invalid_list");
            }
        }

        /// <summary>Công thức của hệ thống ai cũng thấy; công thức do thành viên tạo là riêng tư.</summary>
        public static bool CanSee(Recipe recipe, string? userId) =>
            !recipe.IsDeleted && (recipe.CreatedBy == null || (!string.IsNullOrEmpty(userId) && recipe.CreatedBy == userId));
    }
}
