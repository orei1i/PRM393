using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using DomainLayer.Entities;

namespace DomainLayer.Helpers
{
    public static class VeganClassifier
    {
        // Danh sách ngoại lệ thực vật dù chứa từ có vẻ động vật (gà, vịt, mỡ...)
        private static readonly string[] PlantExceptions = new[]
        {
            "nấm đùi gà", "nam dui ga",
            "nấm mỡ", "nam mo",
            "yến mạch", "yen mach",
            "đậu gà", "dau ga",
            "rau chân vịt", "rau chan vit", "chân vịt", "chan vit",
            "khoai mỡ", "khoai mo",
            "quả bơ", "qua bo", "trái bơ", "trai bo",
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

        // Từ khóa động vật chuẩn (chỉ bắt bơ lạt, bơ sữa, butter; không bắt "bơ" đứng một mình để nhường cho catalog)
        private static readonly Regex AnimalRegex = new(
            @"\b(thịt|thit|bò|bo|heo|lợn|lon|gà|ga|vịt|vit|ngan|ngỗng|ngong|chim|cút|cut|cá|ca|tôm|tom|cua|ghẹ|ghe|mực|muc|bạch tuộc|bach tuoc|ốc|oc|nghêu|ngheu|sò|so|hến|hen|hàu|hau|hào|hao|dầu hào|dau hao|sò huyết|so huyet|trai|trứng|trung|sữa|sua|bơ lạt|bo lat|bơ động vật|bo dong vat|bơ sữa|bo sua|butter|pho mát|phô mai|pho mai|cheese|mỡ|mo|da heo|bì|lạp xưởng|lap xuong|chả lụa|cha lua|giò lụa|gio lua|nem chua|xúc xích|xuc xich|pate|nước mắm|nuoc mam|mắm tôm|mam tom|mắm|mam|mật ong|mat ong|yến sào|yen sao|tổ yến|to yen)\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly Regex PlantRegex = new(
            @"\b(rau|củ|cu|quả|qua|trái|trai|nấm|nam|đậu|dau|hạt|hat|gạo|gao|mè|vừng|vung|ngô|ngo|bắp|bap|khoai|sắn|san|đậu phụ|dau phu|đậu hũ|dau hu|tàu hũ|tau hu|rong biển|rong bien|tảo|tao|hành|hanh|tỏi|toi|ớt|ot|tiêu|tieu|gừng|gung|sả|sa|chanh|chuối|chuoi|táo|tao|cam|xoài|xoai|dưa|dua|dứa|thơm|thom|khóm|khom|bông cải|súp lơ|cải|cai|xà lách|xa lach|bắp cải|bap cai)\b",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public static bool ClassifyIsVegan(string name, Ingredient? matchedIngredient = null)
        {
            if (string.IsNullOrWhiteSpace(name)) return true;

            var normalizedNfc = name.Normalize(NormalizationForm.FormC).Trim();
            var lower = normalizedNfc.ToLowerInvariant();

            // Tầng 0: Tên món chứa "chay", "thuần chay", "thực vật" -> luôn là món chay
            if (lower.Contains("chay") || lower.Contains("thuần chay") || lower.Contains("thuan chay") ||
                lower.Contains("thực vật") || lower.Contains("thuc vat"))
            {
                return true;
            }

            // Tầng 1: Nếu khớp chính xác nguyên liệu trong Catalog -> Ưu tiên quyết định của Catalog
            if (matchedIngredient != null)
            {
                return matchedIngredient.IsVegan;
            }

            // Tầng 2: Gỡ các cụm từ ngoại lệ thực vật ra khỏi chuỗi trước khi quét regex động vật
            var textToCheck = lower;
            foreach (var plantEx in PlantExceptions)
            {
                if (textToCheck.Contains(plantEx))
                {
                    textToCheck = textToCheck.Replace(plantEx, " ");
                }
            }

            // Tầng 3: Quét từ động vật trên phần chuỗi còn lại
            if (AnimalRegex.IsMatch(textToCheck))
            {
                return false;
            }

            // Tầng 4: Kiểm tra từ khóa thực vật
            if (PlantRegex.IsMatch(lower))
            {
                return true;
            }

            // Tầng 5: Mặc định là thuần chay trong ứng dụng VeganLife
            return true;
        }

        public static bool IsVegan(string name) => ClassifyIsVegan(name, null);
    }
}
