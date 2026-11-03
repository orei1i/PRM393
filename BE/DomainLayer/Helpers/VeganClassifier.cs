using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using DomainLayer.Entities;

namespace DomainLayer.Helpers
{
    /// <summary>
    /// Xếp một tên món hoặc nguyên liệu là thuần chay hay không, theo thứ tự:
    /// 1. Ghi rõ là chay hoặc từ thực vật thì thuần chay ("không chay" thì không).
    /// 2. Có trong danh mục nguyên liệu: danh mục quyết định.
    /// 3. Gỡ các cụm thực vật có tên dễ nhầm, rồi đối chiếu danh sách không thuần chay.
    /// 4. Không rơi vào đâu cả thì coi là thuần chay, vì ở đây chỉ có danh sách cấm.
    /// Muốn thêm tên mới thì sửa các danh sách dưới đây.
    /// </summary>
    public static class VeganClassifier
    {
        // Tên thực vật chứa từ có vẻ là động vật.
        private static readonly string[] PlantCompounds =
        {
            // Sữa, sữa chua, phô mai, kem, bơ từ thực vật
            "sữa hạt", "sữa đậu nành", "sữa đậu", "sữa dừa", "sữa hạnh nhân", "sữa óc chó", "sữa bắp", "sữa gạo",
            "sữa mè", "sữa yến mạch", "sữa điều", "sữa hạt điều", "sữa đặc dừa",
            "sữa chua dừa", "sữa chua hạt", "sữa chua đậu nành", "sữa chua hạnh nhân", "sữa chua yến mạch", "sữa chua hạt điều",
            "phô mai hạt điều", "phô mai hạt", "phô mai dừa", "phô mai đậu", "phô mai hạnh nhân",
            "pho mát hạt điều", "pho mát hạt", "pho mát dừa", "cheese hạt điều",
            "kem dừa", "kem hạt", "kem đậu nành", "kem hạnh nhân", "kem chuối", "kem bơ",
            "bơ đậu phộng", "bơ lạc", "bơ hạt", "bơ hạnh nhân", "bơ hạt hướng dương", "bơ ca cao", "bơ thực vật", "bơ dừa",
            "quả bơ", "trái bơ",
            "peanut butter", "almond butter", "cocoa butter", "coconut milk", "soy milk", "almond milk", "oat milk",
            "oyster mushroom", "king oyster mushroom", "chicken of the woods", "butternut", "butter bean", "fish mint",
            // Nấm, rau, củ, đậu
            "nấm đùi gà", "nấm mỡ", "nấm sò", "nấm tai mèo", "nấm mèo",
            "yến mạch", "đậu gà", "đậu mắt cua", "óc chó", "hạt óc chó", "rau bò khai",
            "rau chân vịt", "rau diếp cá", "diếp cá", "dấp cá", "giấp cá",
            "khoai mỡ", "củ mỡ", "cà chua", "cà rốt", "cà tím", "cà pháo", "cà phê", "cà ri", "ca cao",
            "trái cây",
            // Món có tên dễ nhầm
            "bánh bò", "bánh da lợn", "bánh tai heo", "kẹo dừa",
        };

        // Danh sách không thuần chay. So đúng dấu, vì không dấu thì "bò", "bơ", "bo" là một.
        private static readonly string[] AnimalTerms =
        {
            // Thịt và phần của con vật
            "thịt", "bò", "heo", "lợn", "gà", "vịt", "ngan", "ngỗng", "chim", "cút", "dê", "cừu", "nai", "thỏ", "ếch", "lươn", "rắn", "trâu", "ngựa", "chó", "mèo",
            "sườn", "sườn non", "ba chỉ", "ba rọi", "nạc", "móng giò", "giò heo", "chân giò",
            "tim", "gan", "cật", "lòng", "dồi", "dạ dày", "bao tử", "xương", "tủy", "tuỷ", "bì", "gân", "tiết", "tiết canh", "huyết",
            "mỡ", "tóp mỡ",
            "giò", "giò lụa", "giò thủ", "chả", "nem", "xúc xích", "lạp xưởng", "pate", "pa tê", "ruốc", "chà bông", "dăm bông", "ham", "bacon",
            // Hải sản
            "hải sản", "cá", "tôm", "tép", "cua", "ghẹ", "mực", "bạch tuộc", "ốc", "nghêu", "ngao", "sò", "hến", "hàu", "trai", "sứa", "rươi", "cáy", "bề bề",
            // Mắm, nước chấm, chất từ động vật
            "mắm", "dầu hào", "gelatin", "gelatine", "collagen", "whey", "casein", "lactose", "rennet", "isinglass", "carmine", "shellac", "lanolin", "cánh kiến",
            "mật ong", "sáp ong", "yến sào", "tổ yến",
            // Trứng, sữa
            "trứng", "sữa", "yaourt", "yogurt", "da ua",
            "bơ lạt", "bơ mặn", "bơ sữa", "bơ động vật", "phô mai", "pho mát", "kem sữa", "kem tươi", "whipping cream", "ghee",
            // Tiếng Anh
            "beef", "pork", "chicken", "duck", "goat", "lamb", "mutton", "fish", "salmon", "tuna", "shrimp", "prawn", "crab", "squid", "oyster", "seafood", "egg", "eggs", "milk", "cheese", "butter", "honey", "lard", "tallow", "anchovy", "meat",
        };

        // Gõ không dấu. Chỉ gồm từ một nghĩa hoặc cụm rõ ràng: "ga", "so", "ca", "bo", "me" một mình có nhiều nghĩa nên không xét.
        private static readonly string[] UnaccentedAnimalTerms =
        {
            "thit", "heo", "vit", "ngong", "suon", "ba chi", "ba roi", "tiet canh", "hai san", "tom", "muc", "bach tuoc", "ngheu", "trung", "sua",
            "pho mai", "pho mat", "bo lat", "bo sua", "nuoc mam", "mam tom", "mat ong", "yen sao", "to yen", "xuc xich", "lap xuong", "cha lua", "gio lua", "nem chua",
            "dau hao", "ca hoi", "ca ngu", "ca kho", "ca chien", "ca sot", "canh ca", "bun bo", "pho bo", "pho ga", "com ga", "ga ran", "ga nuong", "bo xao", "bo nuong",
        };

        private static readonly string[] OrderedPlantCompounds = PlantCompounds
            .Distinct()
            .OrderByDescending(c => c.Length)
            .ToArray();

        private static readonly string[] UnaccentedPlantCompounds = PlantCompounds
            .Select(c => AllergyMatcher.RemoveDiacritics(c).ToLowerInvariant())
            .Distinct()
            .OrderByDescending(c => c.Length)
            .ToArray();

        private static readonly Regex AnimalRegex = BuildWordRegex(AnimalTerms);
        private static readonly Regex UnaccentedAnimalRegex = BuildWordRegex(UnaccentedAnimalTerms);

        private static readonly Regex NotPlantDeclaration = new(
            @"(?<![\p{L}\p{N}])(không|ko|khong|phi)\s+(chay|thuần chay|thuan chay)(?![\p{L}\p{N}])",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly Regex PlantDeclaration = new(
            @"(?<![\p{L}\p{N}])(chay|thuần chay|thuan chay|thực vật|thuc vat|vegan|plant[- ]based)(?![\p{L}\p{N}])",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static Regex BuildWordRegex(IEnumerable<string> terms)
        {
            var alternatives = string.Join("|", terms.Distinct().OrderByDescending(t => t.Length).Select(Regex.Escape));
            return new Regex($@"(?<![\p{{L}}\p{{N}}])({alternatives})(?![\p{{L}}\p{{N}}])", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        }

        public static bool ClassifyIsVegan(string name, Ingredient? matchedIngredient = null)
        {
            if (string.IsNullOrWhiteSpace(name)) return true;

            var lower = name.Normalize(NormalizationForm.FormC).Trim().ToLowerInvariant();

            if (NotPlantDeclaration.IsMatch(lower)) return false;
            if (PlantDeclaration.IsMatch(lower)) return true;

            if (matchedIngredient != null) return matchedIngredient.IsVegan;

            // Gỡ cả dạng không dấu: "trai cay" là trái cây, không phải con trai.
            if (AnimalRegex.IsMatch(Without(Without(lower, OrderedPlantCompounds), UnaccentedPlantCompounds))) return false;

            // Chỉ xét kiểu gõ không dấu khi cả tên không có dấu nào, để "Bơ" không thành "bo".
            var folded = AllergyMatcher.RemoveDiacritics(lower).ToLowerInvariant();
            if (folded == lower && UnaccentedAnimalRegex.IsMatch(Without(folded, UnaccentedPlantCompounds))) return false;

            return true;
        }

        public static bool IsVegan(string name) => ClassifyIsVegan(name, null);

        private static string Without(string text, IEnumerable<string> phrases)
        {
            foreach (var phrase in phrases)
            {
                text = Regex.Replace(text, $@"(?<![\p{{L}}\p{{N}}]){Regex.Escape(phrase)}(?![\p{{L}}\p{{N}}])", " ", RegexOptions.IgnoreCase);
            }
            return text;
        }
    }
}
