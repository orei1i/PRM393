using System;

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
        public double? WeightKg { get; set; }
        public double? HeightCm { get; set; }
        public double? WaistCm { get; set; }
        public double? BodyFatPct { get; set; }
    }
}
