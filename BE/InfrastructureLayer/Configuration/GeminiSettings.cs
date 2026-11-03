namespace InfrastructureLayer.Configuration
{
    public class GeminiSettings
    {
        public const string SectionName = "Gemini";

        public string ApiKey { get; set; } = string.Empty;

        public string Model { get; set; } = "gemini-3.6-flash";

        public string EmbeddingModel { get; set; } = "gemini-embedding-001";

        public int EmbeddingDimensions { get; set; } = 768;

        public string BaseUrl { get; set; } = "https://generativelanguage.googleapis.com/v1beta";
    }
}

