using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using DomainLayer.Entities;

namespace DomainLayer.Helpers
{
    public static class VeganClassifier
    {
        // Tier 1: Exceptions that are plant-based even though they may contain animal words
        private static readonly HashSet<string> PlantExceptions = new(StringComparer.OrdinalIgnoreCase)
        {
            "nấm đùi gà", "nam dui ga",
            "nấm mỡ", "nam mo",
            "yến mạch", "yen mach",
            "sữa hạt", "sua hat",
            "sữa đậu nành", "sua dau nanh",
            "sữa dừa", "sua dua",
            "sữa hạnh nhân", "sua hanh nhan",
            "sữa óc chó", "sua oc cho",
            "sữa bắp", "sua bap",
            "sữa gạo", "sua gao",
            "sữa mè", "sua me",
            "sữa yến mạch", "sua yen mach",
            "sữa đậu", "sua dau",
            "bơ đậu phộng", "bo dau phong",
            "bơ lạc", "bo lac",
            "bơ hạt", "bo hat",
            "bơ hạnh nhân", "bo hanh nhan",
            "bơ hạt hướng dương", "bo hat huong duong",
            "bơ ca cao", "bo ca cao",
            "bơ thực vật", "bo thuc vat",
            "cà chua", "ca chua",
            "cà rốt", "ca rot",
            "cà tím", "ca tim",
            "cà pháo", "ca phao"
        };

        // Tier 2: Animal keywords with whole-word regex (preserves accents, NFC normalized)
        private static readonly Regex AnimalRegex = new(
            @"\b(thịt|thit|bò|bo|heo|lợn|lon|gà|ga|vịt|vit|ngan|ngỗng|ngong|chim|cút|cut|cá|ca|tôm|tom|cua|ghẹ|ghe|mực|muc|bạch tuộc|bach tuoc|ốc|oc|nghêu|ngheu|sò|so|hến|hen|hàu|hau|trai|trứng|trung|sữa|sua|bơ|pho mát|phô mai|pho mai|cheese|mỡ|mo|da heo|bì|lạp xưởng|lap xuong|chả lụa|cha lua|giò lụa|gio lua|nem chua|xúc xích|xuc xich|pate|nước mắm|nuoc mam|mắm|mam|mật ong|mat ong|yến sào|yen sao|tổ yến|to yen)\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        // Tier 4: Common plant/produce keywords
        private static readonly Regex PlantRegex = new(
            @"\b(rau|củ|cu|quả|qua|trái|trai|nấm|nam|đậu|dau|hạt|hat|gạo|gao|mè|me|vừng|vung|ngô|ngo|bắp|bap|khoai|sắn|san|đậu phụ|dau phu|đậu hũ|dau hu|tàu hũ|tau hu|rong biển|rong bien|tảo|tao|hành|hanh|tỏi|toi|ớt|ot|tiêu|tieu|gừng|gung|sả|sa|chanh|chuối|chuoi|táo|tao|cam|xoài|xoai|dưa|dua|dứa|dua|thơm|thom|khóm|khom|bông cải|súp lơ|cải|cai|xà lách|xa lach|bắp cải|bap cai)\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public static bool ClassifyIsVegan(string name, Ingredient? matchedIngredient = null)
        {
            if (string.IsNullOrWhiteSpace(name)) return true;

            var normalizedNfc = name.Normalize(NormalizationForm.FormC).Trim();
            var lower = normalizedNfc.ToLowerInvariant();

            // Tier 1: Whitelist plant exceptions & words containing "chay" or "thực vật"
            if (lower.Contains("chay") || lower.Contains("thực vật") || lower.Contains("thuc vat"))
            {
                return true;
            }

            foreach (var plantEx in PlantExceptions)
            {
                if (lower.Contains(plantEx))
                {
                    return true;
                }
            }

            // Tier 2: Animal regex
            if (AnimalRegex.IsMatch(lower))
            {
                return false;
            }

            // Tier 3: Matched ingredient from catalog
            if (matchedIngredient != null)
            {
                return matchedIngredient.IsVegan;
            }

            // Tier 4: Common plant dictionary
            if (PlantRegex.IsMatch(lower))
            {
                return true;
            }

            // Tier 5: Ambiguous / unknown -> Default to true (in vegan app context, keeping non-nullable bool)
            return true;
        }
    }
}

