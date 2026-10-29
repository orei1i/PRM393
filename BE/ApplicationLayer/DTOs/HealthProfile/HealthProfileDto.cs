using System.Collections.Generic;

namespace ApplicationLayer.DTOs.HealthProfile
{
    public class AllergyItemDto
    {
        public string? AllergenId { get; set; }
        public string Name { get; set; } = string.Empty;
    }

    public class HealthProfileResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public double HeightCm { get; set; }
        public double WeightKg { get; set; }
        public double Bmi { get; set; }
        public string BmiCategory { get; set; } = "normal";
        public string Goal { get; set; } = "maintain";
        public string Gender { get; set; } = "Other";
        public int BirthYear { get; set; }
        public string ActivityLevel { get; set; } = "light";
        public List<string> MealPattern { get; set; } = new();
        public List<AllergyItemDto> Allergies { get; set; } = new();
        public List<string> DietaryRestrictions { get; set; } = new();
        public double Bmr { get; set; }
        public double Tdee { get; set; }
        public int TargetCalories { get; set; }
    }
}

