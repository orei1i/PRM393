namespace InfrastructureLayer.Configuration
{
    public class GeminiSettings
    {
        public const string SectionName = "Gemini";

        public string ApiKey { get; set; } = string.Empty;

        public string Model { get; set; } = "gemini-2.0-flash";

        public string EmbeddingModel { get; set; } = "gemini-embedding-001";

        public string BaseUrl { get; set; } = "https://generativelanguage.googleapis.com/v1beta";
    }
}

