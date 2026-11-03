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

        // B14: Nhãn ngắn tiếng Việt dùng riêng cho thông báo cảnh báo dị ứng
        public static readonly Dictionary<string, string> ShortAllergenLabels = new(StringComparer.OrdinalIgnoreCase)
        {
            ["peanut"] = "Đậu phộng",
            ["tree_nut"] = "Hạt cây",
            ["soy"] = "Đậu nành",
            ["gluten"] = "Gluten",
            ["sesame"] = "Mè",
            ["mustard"] = "Mù tạt",
            ["celery"] = "Cần tây"
        };

        public static string GetShortLabel(string allergenId)
        {
            if (string.IsNullOrWhiteSpace(allergenId)) return string.Empty;
            return ShortAllergenLabels.TryGetValue(allergenId, out var label) ? label : allergenId;
        }

        private static readonly Dictionary<string, List<string>> StandardAllergenKeywords = new(StringComparer.OrdinalIgnoreCase)
        {
            ["peanut"] = new() { "đậu phộng", "dau phong", "lạc", "lac", "peanut" },
            ["soy"] = new() { "đậu nành", "dau nanh", "đậu tương", "dau tuong", "đậu hũ", "dau hu", "tàu hũ", "tau hu", "đậu phụ", "dau phu", "soy", "tofu", "tempeh", "miso", "nước tương", "nuoc tuong", "tàu hũ ky", "váng đậu", "vang dau" },
            ["gluten"] = new() { "gluten", "lúa mì", "lua mi", "bột mì", "bot mi", "bánh mì", "banh mi", "yến mạch", "yen mach", "mì căn", "mi can", "seitan" },
            // B14: Bỏ từ khóa "me" không dấu để tránh quả Me bị bắt nhầm thành dị ứng Mè
            ["sesame"] = new() { "mè", "vừng", "vung", "sesame" },
            ["mustard"] = new() { "mù tạt", "mu tat", "mustard" },
            ["celery"] = new() { "cần tây", "can tay", "celery" },
            ["tree_nut"] = new() { "hạt điều", "hat dieu", "óc chó", "oc cho", "hạnh nhân", "hanh nhan", "dẻ cười", "de cuoi", "macca", "hạt dẻ", "hat de", "walnut", "almond", "cashew" }
        };

        public static bool IsStandardAllergen(string key) => StandardAllergenIds.Contains(key);

        // B68: Chuẩn hóa tên dị ứng tự do sang AllergenId chuẩn
        public static string? NormalizeToId(string? input)
        {
            if (string.IsNullOrWhiteSpace(input)) return null;
            var trimmed = input.Trim();
            if (IsStandardAllergen(trimmed)) return trimmed.ToLowerInvariant();

            // So theo nguyên từ: "Cá" không được khớp vào "macca", "Me" không phải "Mè".
            foreach (var kvp in StandardAllergenKeywords)
            {
                foreach (var kw in kvp.Value)
                {
                    if (MentionsAllergy(kw, new[] { trimmed }))
                    {
                        return kvp.Key;
                    }
                }
            }
            return null;
        }

        /// <summary>
        /// Khoá gộp dòng trong tủ lạnh. Tên dài bỏ dấu để "dau hu" gộp với "Đậu hũ" (B34).
        /// Tên rất ngắn giữ dấu vì dấu đổi nghĩa: "Me" khác "Mè", "Bò" khác "Bơ" (B70).
        /// </summary>
        public static string PantryKey(string name)
        {
            var lower = name.Normalize(NormalizationForm.FormC).Trim().ToLowerInvariant();
            var folded = RemoveDiacritics(lower).ToLowerInvariant();
            return folded.Count(char.IsLetterOrDigit) <= 3 ? lower : folded;
        }

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

        /// <summary>
        /// Mã dị ứng suy ra từ tên món và nguyên liệu, cho món nhập tay không có nhãn (món chuyên gia tự viết).
        /// Chỉ là phát hiện theo từ khoá: không có mã nào không có nghĩa là an toàn.
        /// </summary>
        public static List<string> DetectAllergens(IEnumerable<string> dishTexts)
        {
            var texts = dishTexts.Where(t => !string.IsNullOrWhiteSpace(t)).ToList();
            return StandardAllergenKeywords
                .Where(kvp => kvp.Value.Any(k => MentionsAllergy(k, texts)))
                .Select(kvp => kvp.Key)
                .ToList();
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
                else if (StandardAllergenKeywords.TryGetValue(tag, out var kws))
                {
                    var matchingAllergy = userAllergySet.FirstOrDefault(u => kws.Any(k => string.Equals(k, u, StringComparison.OrdinalIgnoreCase)));
                    if (matchingAllergy != null && !conflicts.Contains(matchingAllergy))
                    {
                        conflicts.Add(matchingAllergy);
                    }
                }
            }

            // 2. Khớp theo tên tự do trong tên món ăn và danh sách nguyên liệu
            var textList = dishTexts.Where(t => !string.IsNullOrWhiteSpace(t)).ToList();
            foreach (var allergy in userAllergySet)
            {
                if (!conflicts.Contains(allergy))
                {
                    if (MentionsAllergy(allergy, textList) ||
                        (StandardAllergenKeywords.TryGetValue(allergy, out var kws) && kws.Any(k => MentionsAllergy(k, textList))))
                    {
                        conflicts.Add(allergy);
                    }
                }
            }

            return conflicts;
        }
    }
}
