using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Vision
{
    public class GeminiVisionRawItem
    {
        public string Label { get; set; } = string.Empty;

        public double Confidence { get; set; } = 0.9;

        public bool? IsVegan { get; set; }

        public string? NonVeganReason { get; set; }

        public List<string>? VeganAlternatives { get; set; }

        /// <summary>
        /// [ymin, xmin, ymax, xmax] scaled 0 to 1000 from Gemini
        /// </summary>
        public double[]? Box_2d { get; set; }

        public List<IngredientAlternativeDto>? Alternatives { get; set; }
    }

    public class GeminiVisionRawResponse
    {
        public List<GeminiVisionRawItem> Items { get; set; } = new();
    }
}

