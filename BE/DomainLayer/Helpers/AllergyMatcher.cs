using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace DomainLayer.Helpers
{
    public static class AllergyMatcher
    {
        public static readonly HashSet<string> StandardAllergenIds = new(StringComparer.OrdinalIgnoreCase)
        {
            "peanut",
            "tree_nut",
            "soy",
            "gluten",
            "sesame",
            "mustard",
            "celery"
        };

        public static readonly Dictionary<string, string> StandardAllergenLabels = new(StringComparer.OrdinalIgnoreCase)
        {
            ["peanut"] = "Đậu phộng (Lạc)",
            ["tree_nut"] = "Hạt cây (Hạt điều, óc chó, hạnh nhân...)",
            ["soy"] = "Đậu nành (Đậu tương)",
            ["gluten"] = "Gluten (Lúa mì, yến mạch không nhãn gluten-free)",
            ["sesame"] = "Mè (Vừng)",
            ["mustard"] = "Mù tạt",
            ["celery"] = "Cần tây"
        };

        public static bool IsStandardAllergen(string key) => StandardAllergenIds.Contains(key);

        public static string RemoveDiacritics(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return string.Empty;
            var normalizedString = text.Normalize(NormalizationForm.FormD);
            var stringBuilder = new StringBuilder();

            foreach (var c in normalizedString)
            {
                var unicodeCategory = CharUnicodeInfo.GetUnicodeCategory(c);
                if (unicodeCategory != UnicodeCategory.NonSpacingMark)
                {
                    stringBuilder.Append(c);
                }
            }

            // Đổi đ/Đ thành d/D
            return stringBuilder.ToString().Normalize(NormalizationForm.FormC)
                .Replace('đ', 'd').Replace('Đ', 'D');
        }

        public static string NormalizeForSearch(string text)
        {
            var folded = RemoveDiacritics(text.ToLowerInvariant());
            var clean = Regex.Replace(folded, @"[^a-z0-9]+", " ").Trim();
            return $" {clean} ";
        }

        public static string AccentedWords(string text)
        {
            var clean = Regex.Replace(text.ToLowerInvariant(), @"[^\p{L}\p{N}]+", " ").Trim();
            return $" {clean} ";
        }

        public static bool MentionsAllergy(string allergyName, IEnumerable<string> searchTexts)
        {
            if (string.IsNullOrWhiteSpace(allergyName)) return false;
            var trimmed = allergyName.Trim();

            // Nếu từ ngắn (<= 3 ký tự ví dụ "bơ", "nấm"), giữ nguyên dấu để tránh nhầm lẫn
            if (trimmed.Length <= 3)
            {
                var exact = AccentedWords(trimmed);
                return searchTexts.Any(t => AccentedWords(t).Contains(exact));
            }

            var needle = NormalizeForSearch(trimmed);
            return searchTexts.Any(t => NormalizeForSearch(t).Contains(needle));
        }

        public static List<string> FindConflicts(
            IEnumerable<string> dishAllergenTags,
            IEnumerable<string> dishTexts,
            IEnumerable<string> userAllergies)
        {
            var conflicts = new List<string>();
            var userAllergySet = userAllergies.Where(a => !string.IsNullOrWhiteSpace(a)).Select(a => a.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var dishTagSet = dishAllergenTags.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);

            // 1. Khớp theo mã dị ứng chuẩn
            foreach (var tag in dishTagSet)
            {
                if (userAllergySet.Contains(tag) && !conflicts.Contains(tag))
                {
                    conflicts.Add(tag);
                }
            }

            // 2. Khớp theo tên tự do trong tên món ăn và danh sách nguyên liệu
            var textList = dishTexts.Where(t => !string.IsNullOrWhiteSpace(t)).ToList();
            foreach (var allergy in userAllergySet)
            {
                if (!IsStandardAllergen(allergy) && !conflicts.Contains(allergy))
                {
                    if (MentionsAllergy(allergy, textList))
                    {
                        conflicts.Add(allergy);
                    }
                }
            }

            return conflicts;
        }
    }
}

