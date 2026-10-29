using System.Collections.Generic;

namespace DomainLayer.Entities
{
    public class Ingredient : BaseEntity
    {
        public string Name { get; set; } = string.Empty;

        /// <summary>
        /// Tên đã chuẩn hóa không dấu và chữ thường dùng để tìm kiếm nhanh
        /// </summary>
        public string NormalizedName { get; set; } = string.Empty;

        /// <summary>
        /// Các tên gọi khác (ví dụ: "tàu hũ", "đậu phụ" cho Đậu hũ)
        /// </summary>
        public List<string> Aliases { get; set; } = new();

        /// <summary>
        /// "plant_protein", "vegetable", "grain", "mushroom", "nut_seed", "fruit", "condiment"
        /// </summary>
        public string Category { get; set; } = "vegetable";

        public int CaloriesPer100g { get; set; }

        public double? ProteinG { get; set; }

        public double? CarbsG { get; set; }

        public double? FatG { get; set; }

        public double? FiberG { get; set; }

        public double? SugarG { get; set; }

        /// <summary>
        /// Danh sách mã dị ứng (ví dụ ["soy"], ["gluten"], ["peanut"])
        /// </summary>
        public List<string> Allergens { get; set; } = new();

        public bool IsVegan { get; set; } = true;

        public List<string> GoodFor { get; set; } = new();

        public List<string> CautionFor { get; set; } = new();
    }
}

