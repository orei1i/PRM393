using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.HealthProfile
{
    public class UpdateHealthProfileRequest
    {
        [Range(50, 250, ErrorMessage = "Chiều cao phải nằm trong khoảng từ 50 đến 250 cm.")]
        public double HeightCm { get; set; }

        [Range(20, 300, ErrorMessage = "Cân nặng phải nằm trong khoảng từ 20 đến 300 kg.")]
        public double WeightKg { get; set; }

        public string Goal { get; set; } = "maintain";

        public string? Gender { get; set; }

        [Range(1920, 2015, ErrorMessage = "Năm sinh không hợp lệ (13–100 tuổi).")]
        public int? BirthYear { get; set; }

        public string ActivityLevel { get; set; } = "light";

        public List<string>? MealPattern { get; set; }

        public List<AllergyItemDto>? Allergies { get; set; }

        public List<string>? DietaryRestrictions { get; set; }
    }
}
