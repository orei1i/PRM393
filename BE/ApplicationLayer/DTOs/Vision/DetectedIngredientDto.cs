using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Vision
{
    public class DetectedIngredientDto
    {
        public string Id { get; set; } = string.Empty;

        public string Label { get; set; } = string.Empty;

        public double Confidence { get; set; }

        public bool? IsVegan { get; set; }

        public string? NonVeganReason { get; set; }

        public List<string> VeganAlternatives { get; set; } = new();

        public BoundingBoxDto? Bbox { get; set; }

        public List<IngredientAlternativeDto> Alternatives { get; set; } = new();
    }
}

