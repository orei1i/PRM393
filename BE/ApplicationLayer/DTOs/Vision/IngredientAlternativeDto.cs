namespace ApplicationLayer.DTOs.Vision
{
    public class IngredientAlternativeDto
    {
        public string Label { get; set; } = string.Empty;
        public double Confidence { get; set; }
        public bool? IsVegan { get; set; }
    }
}

