using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Pantry
{
    public class IngredientResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public int CaloriesPer100g { get; set; }
        public double? ProteinG { get; set; }
        public double? CarbsG { get; set; }
        public double? FatG { get; set; }
        public double? FiberG { get; set; }
        public List<string> Allergens { get; set; } = new();
        public bool IsVegan { get; set; } = true;
        public List<string> Aliases { get; set; } = new();
        public List<string> GoodFor { get; set; } = new();
        public List<string> CautionFor { get; set; } = new();
    }
}

