namespace ApplicationLayer.DTOs.Media
{
    public class UploadedImageResponse
    {
        public string MediaUrl { get; set; } = string.Empty;
        public long SizeBytes { get; set; }
        public int? Width { get; set; }
        public int? Height { get; set; }
    }
}
