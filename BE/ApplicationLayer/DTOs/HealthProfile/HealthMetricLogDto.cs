using System;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.HealthProfile
{
    public class HealthMetricLogResponse
    {
        public string Id { get; set; } = string.Empty;
        public double WeightKg { get; set; }
        public double HeightCm { get; set; }
        public double Bmi { get; set; }
        public double? WaistCm { get; set; }
        public double? BodyFatPct { get; set; }
        public DateTime LoggedAt { get; set; }
    }

    public class LogMetricsRequest
    {
        [Range(20, 300, ErrorMessage = "Cân nặng phải nằm trong khoảng từ 20 đến 300 kg.")]
        public double? WeightKg { get; set; }

        [Range(50, 250, ErrorMessage = "Chiều cao phải nằm trong khoảng từ 50 đến 250 cm.")]
        public double? HeightCm { get; set; }

        [Range(30, 200, ErrorMessage = "Vòng eo phải nằm trong khoảng từ 30 đến 200 cm.")]
        public double? WaistCm { get; set; }

        [Range(3, 60, ErrorMessage = "Tỷ lệ mỡ phải nằm trong khoảng từ 3 đến 60 %.")]
        public double? BodyFatPct { get; set; }
    }
}
