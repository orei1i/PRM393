using System.Collections.Generic;
using DomainLayer.Entities;
using DomainLayer.Helpers;

namespace InfrastructureLayer.Seed
{
    public static class RecipeSeedData
    {
        public static List<Recipe> GetSeeds()
        {
            var raw = new List<(string Name, int Kcal, double P, double C, double F, double Fi, int Prep, string[] Types, string[] Allergens, string[] DietTags, string[] Ings)>
            {
                // Bữa sáng (Breakfast)
                ("Yến mạch ngâm hạt chia & việt quất", 420, 18, 62, 12, 11, 5, new[] { "breakfast" }, new[] { "gluten" }, new[] { "whole_food", "high_fiber" }, new[] { "Yến mạch", "Hạt chia", "Sữa đậu nành", "Việt quất" }),
                ("Bánh mì đậu hũ sả ớt", 460, 22, 58, 15, 6, 15, new[] { "breakfast" }, new[] { "gluten", "soy" }, new[] { "quick" }, new[] { "Đậu hũ", "Bánh mì", "Sả", "Ớt", "Dưa leo", "Rau mùi" }),
                ("Xôi đậu xanh mè đen", 440, 14, 78, 8, 7, 20, new[] { "breakfast" }, new[] { "sesame" }, new[] { "traditional" }, new[] { "Gạo nếp", "Đậu xanh", "Mè đen", "Nước cốt dừa" }),
                ("Sinh tố chuối bơ đậu phộng", 480, 19, 60, 19, 9, 5, new[] { "breakfast", "snack" }, new[] { "peanut", "soy" }, new[] { "high_protein", "quick" }, new[] { "Chuối", "Đậu phộng", "Sữa đậu nành", "Hạt chia" }),
                ("Phở nấm hương chay", 390, 15, 68, 6, 5, 25, new[] { "breakfast", "lunch" }, new[] { "soy" }, new[] { "warm", "comfort" }, new[] { "Phở tươi", "Nấm đông cô", "Đậu hũ", "Củ cải trắng", "Hành boa-rô", "Ngò gai" }),
                ("Bún riêu chay đậu hũ cà chua", 430, 19, 64, 11, 7, 25, new[] { "breakfast", "lunch" }, new[] { "soy" }, new[] { "comfort" }, new[] { "Bún tươi", "Đậu hũ", "Cà chua", "Nấm rơm", "Sữa đậu nành", "Rau muống" }),
                ("Cháo yến mạch nấm rơm hạt sen", 360, 14, 58, 7, 8, 20, new[] { "breakfast" }, new string[0], new[] { "easy_digest", "comfort" }, new[] { "Yến mạch", "Nấm rơm", "Hạt sen", "Cà rốt", "Hành lá" }),
                ("Khoai lang mật nướng hạt chia", 320, 6, 65, 5, 9, 15, new[] { "breakfast", "snack" }, new string[0], new[] { "quick", "whole_food" }, new[] { "Khoai lang", "Hạt chia", "Mật mía" }),

                // Bữa trưa (Lunch)
                ("Cơm gạo lứt đậu hũ kho nấm đông cô", 520, 26, 75, 14, 10, 25, new[] { "lunch", "dinner" }, new[] { "soy" }, new[] { "balanced", "whole_food" }, new[] { "Gạo lứt", "Đậu hũ", "Nấm đông cô", "Nước tương", "Tiêu đen" }),
                ("Cơm chiên hạt sen bông cải xanh", 480, 16, 76, 12, 8, 20, new[] { "lunch", "dinner" }, new string[0], new[] { "quick", "colorful" }, new[] { "Gạo lứt", "Hạt sen", "Bông cải xanh", "Cà rốt", "Bắp ngọt" }),
                ("Bún chả giò chay rau sống", 490, 18, 72, 15, 8, 30, new[] { "lunch" }, new[] { "soy" }, new[] { "crispy", "traditional" }, new[] { "Bún tươi", "Khoai môn", "Đậu xanh", "Nấm mộc nhĩ", "Bánh tráng", "Rau sống" }),
                ("Đậu hũ sốt cà chua & cơm lứt", 450, 22, 65, 12, 7, 20, new[] { "lunch", "dinner" }, new[] { "soy" }, new[] { "classic", "comfort" }, new[] { "Đậu hũ", "Cà chua", "Gạo lứt", "Hành boa-rô", "Nước tương" }),
                ("Nấm đùi gà kho tiêu xanh & rau luộc", 430, 18, 62, 11, 9, 20, new[] { "lunch", "dinner" }, new[] { "soy" }, new[] { "spicy", "comfort" }, new[] { "Nấm đùi gà", "Gạo lứt", "Tiêu xanh", "Bông cải xanh", "Cà rốt" }),
                ("Canh chua nấm đậu bắp & cơm lứt", 410, 17, 68, 8, 8, 25, new[] { "lunch", "dinner" }, new[] { "soy" }, new[] { "refreshing", "traditional" }, new[] { "Nấm rơm", "Đậu hũ", "Cà chua", "Bạc hà", "Đậu bắp", "Giá đỗ", "Gạo lứt" }),
                ("Tempeh áp chảo sốt tương tỏi", 530, 32, 54, 20, 11, 20, new[] { "lunch", "dinner" }, new[] { "soy" }, new[] { "high_protein" }, new[] { "Tempeh", "Gạo lứt", "Tỏi", "Nước tương", "Bông cải xanh" }),
                ("Mì xào giòn rau củ thập cẩm chay", 470, 18, 68, 14, 7, 20, new[] { "lunch" }, new[] { "gluten", "soy" }, new[] { "quick" }, new[] { "Mì căn", "Bông cải xanh", "Cà rốt", "Nấm bào ngư", "Cải thìa" }),
                ("Cà ri đậu gà khoai lang cốt dừa", 540, 21, 72, 19, 14, 30, new[] { "lunch", "dinner" }, new string[0], new[] { "comfort", "rich" }, new[] { "Đậu gà", "Khoai lang", "Nước cốt dừa", "Cà rốt", "Bột cà ri", "Gạo lứt" }),

                // Bữa tối (Dinner)
                ("Canh rong biển đậu hũ non & cơm gạo lứt", 380, 20, 56, 8, 6, 20, new[] { "dinner" }, new[] { "soy", "sesame" }, new[] { "light", "detox" }, new[] { "Rong biển", "Đậu hũ non", "Gạo lứt", "Mè trắng", "Gừng" }),
                ("Nấm bào ngư xào sả ớt & canh rau dền", 420, 17, 58, 13, 8, 20, new[] { "dinner" }, new[] { "soy" }, new[] { "warm", "light" }, new[] { "Nấm bào ngư", "Sả", "Ớt", "Rau dền", "Gạo lứt" }),
                ("Mướp hương xào nấm rơm & cơm lứt", 390, 15, 62, 9, 7, 15, new[] { "dinner" }, new string[0], new[] { "quick", "light" }, new[] { "Mướp hương", "Nấm rơm", "Gạo lứt", "Hành lá", "Tiêu" }),
                ("Cải thìa sốt nấm đông cô dầu hào chay", 370, 14, 55, 10, 8, 15, new[] { "dinner" }, new[] { "soy" }, new[] { "light", "delicate" }, new[] { "Cải thìa", "Nấm đông cô", "Gạo lứt", "Dầu hào chay" }),
                ("Súp bí đỏ đậu lăng đỏ sánh mịn", 360, 18, 52, 9, 12, 25, new[] { "dinner" }, new string[0], new[] { "warm", "high_fiber" }, new[] { "Bí đỏ", "Đậu lăng đỏ", "Nước cốt dừa", "Hạt bí" }),
                ("Đậu hũ ky cuốn nấm hấp tương", 410, 24, 45, 15, 6, 25, new[] { "dinner" }, new[] { "soy" }, new[] { "high_protein", "delicate" }, new[] { "Đậu hũ ky", "Nấm kim châm", "Nấm mộc nhĩ", "Gừng", "Nước tương" }),
                ("Gỏi cuốn đậu hũ bơ sốt tương phộng", 430, 17, 56, 16, 8, 20, new[] { "dinner", "lunch" }, new[] { "peanut", "soy" }, new[] { "fresh", "no_cook" }, new[] { "Bánh tráng", "Đậu hũ", "Bơ", "Rau thơm", "Bún tươi", "Đậu phộng" }),

                // Bữa phụ / Ăn nhẹ (Snack)
                ("Sữa hạt điều mè đen ấm", 180, 6, 12, 12, 3, 10, new[] { "snack", "snack_pm" }, new[] { "tree_nut", "sesame" }, new[] { "calm", "drink" }, new[] { "Hạt điều", "Mè đen", "Nước ấm" }),
                ("Bánh chuối yến mạch nướng", 210, 6, 38, 4, 5, 20, new[] { "snack", "snack_pm" }, new[] { "gluten" }, new[] { "sweet", "baked" }, new[] { "Chuối", "Yến mạch", "Hạt chia" }),
                ("Chè hạt sen đậu đỏ ngọt thanh", 220, 8, 42, 2, 6, 30, new[] { "snack", "snack_pm" }, new string[0], new[] { "sweet", "traditional" }, new[] { "Hạt sen", "Đậu đỏ", "Đường phèn" }),
                ("Đậu phộng rang tỏi ớt lá chanh", 190, 8, 8, 15, 3, 10, new[] { "snack", "snack_pm" }, new[] { "peanut" }, new[] { "crunchy", "savory" }, new[] { "Đậu phộng", "Tỏi", "Ớt", "Lá chanh" }),
                ("Bơ dầm sữa đậu nành hạt chia", 230, 7, 18, 15, 6, 5, new[] { "snack", "snack_pm" }, new[] { "soy" }, new[] { "creamy", "quick" }, new[] { "Bơ", "Sữa đậu nành", "Hạt chia" })
            };

            var list = new List<Recipe>();
            foreach (var r in raw)
            {
                list.Add(new Recipe
                {
                    Name = r.Name,
                    NormalizedName = AllergyMatcher.RemoveDiacritics(r.Name).ToLowerInvariant(),
                    Calories = r.Kcal,
                    ProteinG = r.P,
                    CarbsG = r.C,
                    FatG = r.F,
                    FiberG = r.Fi,
                    PrepMinutes = r.Prep,
                    MealTypes = new List<string>(r.Types),
                    Allergens = new List<string>(r.Allergens),
                    DietTags = new List<string>(r.DietTags),
                    Ingredients = new List<string>(r.Ings),
                    Instructions = new List<string> { "Sơ chế nguyên liệu sạch sẽ.", "Nấu theo công thức chuẩn thuần chay.", "Thưởng thức khi còn ấm nóng." },
                    IsVegan = true,
                    CreatedBy = null // System
                });
            }
            return list;
        }
    }
}

