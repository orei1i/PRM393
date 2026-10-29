using System.Collections.Generic;
using DomainLayer.Entities;
using DomainLayer.Helpers;

namespace InfrastructureLayer.Seed
{
    public static class IngredientSeedData
    {
        public static List<Ingredient> GetSeeds()
        {
            var raw = new List<(string Name, string Cat, int Kcal, double P, double C, double F, double Fi, string[] Aliases, string[] Allergens)>
            {
                // Đạm thực vật
                ("Đậu hũ", "plant_protein", 76, 8.1, 1.9, 4.8, 0.3, new[] { "đậu phụ", "tàu hũ", "tofu" }, new[] { "soy" }),
                ("Đậu hũ chiên", "plant_protein", 132, 10.5, 3.2, 8.5, 0.4, new[] { "tàu hũ chiên" }, new[] { "soy" }),
                ("Đậu hũ non", "plant_protein", 55, 5.0, 1.5, 3.0, 0.2, new[] { "tàu hũ non", "silken tofu" }, new[] { "soy" }),
                ("Đậu hũ ky", "plant_protein", 480, 49.5, 18.0, 22.0, 3.0, new[] { "váng đậu", "phù chúc", "yuba" }, new[] { "soy" }),
                ("Tempeh", "plant_protein", 192, 20.3, 7.6, 10.8, 4.5, new[] { "tương nén" }, new[] { "soy" }),
                ("Sữa đậu nành", "plant_protein", 54, 3.3, 6.0, 1.8, 0.5, new[] { "nước đậu" }, new[] { "soy" }),
                ("Đậu đen", "plant_protein", 341, 21.6, 62.4, 1.4, 15.2, new[] { "đỗ đen" }, new string[0]),
                ("Đậu xanh", "plant_protein", 328, 23.4, 59.0, 1.2, 16.3, new[] { "đỗ xanh", "mung bean" }, new string[0]),
                ("Đậu đỏ", "plant_protein", 329, 21.0, 61.2, 1.0, 12.7, new[] { "đỗ đỏ" }, new string[0]),
                ("Đậu gà", "plant_protein", 364, 19.3, 60.7, 6.0, 17.4, new[] { "chickpea" }, new string[0]),
                ("Đậu lăng đỏ", "plant_protein", 358, 24.6, 63.4, 1.1, 10.8, new[] { "red lentil" }, new string[0]),
                ("Mì căn", "plant_protein", 370, 75.2, 13.8, 1.9, 0.6, new[] { "seitan", "đạm lúa mì" }, new[] { "gluten" }),

                // Nấm
                ("Nấm rơm", "mushroom", 32, 3.4, 4.2, 0.3, 1.5, new[] { "straw mushroom" }, new string[0]),
                ("Nấm đùi gà", "mushroom", 35, 3.1, 5.5, 0.4, 2.3, new[] { "nấm bào ngư Nhật", "king oyster mushroom" }, new string[0]),
                ("Nấm đông cô", "mushroom", 34, 2.2, 6.8, 0.5, 2.5, new[] { "nấm hương", "shiitake" }, new string[0]),
                ("Nấm kim châm", "mushroom", 37, 2.7, 7.8, 0.3, 2.7, new[] { "enoki" }, new string[0]),
                ("Nấm bào ngư", "mushroom", 33, 3.3, 6.1, 0.4, 2.3, new[] { "nấm sò", "oyster mushroom" }, new string[0]),
                ("Nấm mộc nhĩ", "mushroom", 25, 0.5, 7.0, 0.1, 5.1, new[] { "nấm mèo", "wood ear" }, new string[0]),
                ("Nấm mối đen", "mushroom", 38, 3.5, 6.2, 0.4, 2.6, new string[0], new string[0]),

                // Tinh bột & Ngũ cốc
                ("Gạo lứt", "grain", 111, 2.6, 23.0, 0.9, 1.8, new[] { "cơm lứt", "brown rice" }, new string[0]),
                ("Gạo trắng", "grain", 130, 2.7, 28.2, 0.3, 0.4, new[] { "cơm trắng" }, new string[0]),
                ("Yến mạch", "grain", 389, 16.9, 66.3, 6.9, 10.6, new[] { "oats" }, new[] { "gluten" }),
                ("Hạt diêm mạch", "grain", 120, 4.4, 21.3, 1.9, 2.8, new[] { "quinoa" }, new string[0]),
                ("Bún tươi", "grain", 110, 1.7, 25.7, 0.1, 0.3, new[] { "bún sợi" }, new string[0]),
                ("Phở tươi", "grain", 120, 2.0, 27.5, 0.2, 0.4, new[] { "bánh phở" }, new string[0]),
                ("Khoai lang", "grain", 86, 1.6, 20.1, 0.1, 3.0, new[] { "khoai lang mật", "sweet potato" }, new string[0]),
                ("Khoai tây", "grain", 77, 2.0, 17.5, 0.1, 2.2, new[] { "potato" }, new string[0]),
                ("Bắp ngọt", "grain", 86, 3.3, 18.7, 1.4, 2.0, new[] { "ngô ngọt", "ngô ngọt Mỹ" }, new string[0]),

                // Rau củ
                ("Bông cải xanh", "vegetable", 34, 2.8, 6.6, 0.4, 2.6, new[] { "súp lơ xanh", "broccoli" }, new string[0]),
                ("Bông cải trắng", "vegetable", 25, 1.9, 5.0, 0.3, 2.0, new[] { "súp lơ trắng", "cauliflower" }, new string[0]),
                ("Cà rốt", "vegetable", 41, 0.9, 9.6, 0.2, 2.8, new[] { "carrot" }, new string[0]),
                ("Cải ngọt", "vegetable", 18, 1.5, 2.8, 0.2, 1.2, new string[0], new string[0]),
                ("Cải thìa", "vegetable", 13, 1.5, 2.2, 0.2, 1.0, new[] { "cải bẹ trắng", "bok choy" }, new string[0]),
                ("Rau muống", "vegetable", 19, 3.0, 2.1, 0.4, 1.0, new[] { "water spinach" }, new string[0]),
                ("Rau dền", "vegetable", 23, 2.5, 4.0, 0.3, 1.3, new string[0], new string[0]),
                ("Cải bó xôi", "vegetable", 23, 2.9, 3.6, 0.4, 2.2, new[] { "rau bina", "spinach" }, new string[0]),
                ("Cà chua", "vegetable", 18, 0.9, 3.9, 0.2, 1.2, new[] { "tomato" }, new string[0]),
                ("Dưa leo", "vegetable", 15, 0.7, 3.6, 0.1, 0.5, new[] { "dưa chuột", "cucumber" }, new string[0]),
                ("Bí đỏ", "vegetable", 26, 1.0, 6.5, 0.1, 0.5, new[] { "bí ngô", "pumpkin" }, new string[0]),
                ("Củ cải trắng", "vegetable", 16, 0.7, 3.4, 0.1, 1.6, new[] { "radish", "daikon" }, new string[0]),
                ("Mướp hương", "vegetable", 16, 0.9, 3.0, 0.1, 0.5, new[] { "mướp" }, new string[0]),
                ("Cần tây", "vegetable", 16, 0.7, 3.0, 0.2, 1.6, new[] { "celery" }, new[] { "celery" }),

                // Hạt dinh dưỡng & Gia vị
                ("Đậu phộng", "nut_seed", 567, 25.8, 16.1, 49.2, 8.5, new[] { "lạc", "peanut" }, new[] { "peanut" }),
                ("Hạt điều", "nut_seed", 553, 18.2, 30.2, 43.8, 3.3, new[] { "cashew" }, new[] { "tree_nut" }),
                ("Hạt óc chó", "nut_seed", 654, 15.2, 13.7, 65.2, 6.7, new[] { "walnut" }, new[] { "tree_nut" }),
                ("Hạt hạnh nhân", "nut_seed", 579, 21.2, 21.6, 49.9, 12.5, new[] { "almond" }, new[] { "tree_nut" }),
                ("Hạt chia", "nut_seed", 486, 16.5, 42.1, 30.7, 34.4, new[] { "chia seed" }, new string[0]),
                ("Mè đen", "nut_seed", 573, 17.7, 23.4, 49.7, 11.8, new[] { "vừng đen", "black sesame" }, new[] { "sesame" }),
                ("Mè trắng", "nut_seed", 573, 17.7, 23.4, 49.7, 11.8, new[] { "vừng trắng", "sesame" }, new[] { "sesame" }),
                ("Hạt sen", "nut_seed", 350, 17.9, 64.9, 2.0, 7.9, new[] { "lotus seed" }, new string[0]),

                // Trái cây phổ biến
                ("Chuối", "fruit", 89, 1.1, 22.8, 0.3, 2.6, new[] { "banana" }, new string[0]),
                ("Bơ", "fruit", 160, 2.0, 8.5, 14.7, 6.7, new[] { "trái bơ", "avocado" }, new string[0]),
                ("Táo", "fruit", 52, 0.3, 13.8, 0.2, 2.4, new[] { "apple" }, new string[0]),
                ("Thanh long", "fruit", 60, 1.2, 13.0, 0.0, 2.9, new[] { "dragon fruit" }, new string[0])
            };

            var list = new List<Ingredient>();
            foreach (var r in raw)
            {
                list.Add(new Ingredient
                {
                    Name = r.Name,
                    NormalizedName = AllergyMatcher.RemoveDiacritics(r.Name).ToLowerInvariant(),
                    Category = r.Cat,
                    CaloriesPer100g = r.Kcal,
                    ProteinG = r.P,
                    CarbsG = r.C,
                    FatG = r.F,
                    FiberG = r.Fi,
                    Aliases = new List<string>(r.Aliases),
                    Allergens = new List<string>(r.Allergens),
                    IsVegan = true
                });
            }
            return list;
        }
    }
}

