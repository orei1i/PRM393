using System.Collections.Generic;

namespace ApplicationLayer.DTOs.Vision
{
    public class ScanResultDto
    {
        public string ScanId { get; set; } = string.Empty;

        public List<DetectedIngredientDto> Items { get; set; } = new();
    }
}

