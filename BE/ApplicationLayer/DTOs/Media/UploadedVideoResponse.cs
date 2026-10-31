namespace ApplicationLayer.DTOs.Media
{
    public class UploadedVideoResponse
    {
        public string MediaUrl { get; set; } = string.Empty;
        public int? DurationSeconds { get; set; }
        public long SizeBytes { get; set; }
    }
}
