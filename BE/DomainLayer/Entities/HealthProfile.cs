using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class HealthProfile : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        public double HeightCm { get; set; }

        public double WeightKg { get; set; }

        public double Bmi { get; set; }

        public string BmiCategory { get; set; } = "normal";

        /// <summary>
        /// "maintain" | "lose" | "gain" | "lean_muscle"
        /// </summary>
        public string Goal { get; set; } = "maintain";

        /// <summary>
        /// "Male" | "Female" | "Other"
        /// </summary>
        public string Gender { get; set; } = "Other";

        public int BirthYear { get; set; }

        /// <summary>
        /// "sedentary" | "light" | "moderate" | "active"
        /// </summary>
        public string ActivityLevel { get; set; } = "light";

        /// <summary>
        /// Danh sách slot bữa mặc định: "breakfast", "lunch", "snack_pm", "dinner"
        /// </summary>
        public List<string> MealPattern { get; set; } = new() { "breakfast", "lunch", "dinner" };

        /// <summary>
        /// Danh sách khóa dị ứng chuẩn (ví dụ "peanut", "soy") hoặc chuỗi tự do (ví dụ "nấm", "lá lốt")
        /// </summary>
        public List<string> Allergies { get; set; } = new();

        public List<string> DietaryRestrictions { get; set; } = new();

        public double Bmr { get; set; }

        public double Tdee { get; set; }

        public int TargetCalories { get; set; }
    }
}

