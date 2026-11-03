using System.Threading.Tasks;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Cấu hình admin đặt ở web /ai-models, đọc mỗi lần gọi để bật tắt có hiệu lực ngay.
    /// Chưa có dòng cấu hình thì coi là đang bật.
    /// </summary>
    public class AiModelGate
    {
        public const string Chatbot = "chatbot";
        public const string VisionScan = "vision_scan";
        public const string MealPlan = "meal_plan";

        private readonly IGenericRepository<AiModelConfig> _models;

        public AiModelGate(IGenericRepository<AiModelConfig> models)
        {
            _models = models;
        }

        public Task<AiModelConfig?> FindAsync(string task) =>
            _models.FirstOrDefaultAsync(m => m.Task == task && !m.IsDeleted);

        /// <summary>Trả cấu hình nếu đang bật. Đang tắt thì 503 ai_disabled kèm lời nhắc cho người dùng.</summary>
        public async Task<AiModelConfig?> EnsureEnabledAsync(string task, string disabledMessage)
        {
            var config = await FindAsync(task);
            if (config is { Enabled: false })
            {
                throw new ServiceUnavailableException(disabledMessage, "ai_disabled");
            }
            return config;
        }
    }
}
