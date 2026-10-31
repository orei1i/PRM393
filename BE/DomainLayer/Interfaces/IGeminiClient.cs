using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace DomainLayer.Interfaces
{
    public interface IGeminiClient
    {
        /// <summary>
        /// Gọi Gemini để sinh dữ liệu JSON có cấu trúc theo generic DTO.
        /// Tự động retry 3 lần cho mã 429 và 503 với exponential backoff.
        /// Ghi log vào ai_logs collection.
        /// </summary>
        Task<T> GenerateJsonAsync<T>(
            string prompt,
            byte[]? imageBytes = null,
            string? mimeType = null,
            string taskType = "Vision",
            string? userId = null,
            string? scanId = null,
            CancellationToken ct = default);

        /// <summary>
        /// Gọi Gemini sinh văn bản thông thường.
        /// </summary>
        Task<string> GenerateTextAsync(
            string prompt,
            string taskType = "General",
            string? userId = null,
            CancellationToken ct = default);

        /// <summary>
        /// Gọi stream SSE cho Chat.
        /// </summary>
        IAsyncEnumerable<string> StreamTextAsync(
            string prompt,
            string taskType = "Chat",
            string? userId = null,
            CancellationToken ct = default);

        /// <summary>
        /// Embed văn bản (gemini-embedding-001, 768 chiều).
        /// </summary>
        Task<List<float[]>> EmbedAsync(
            IEnumerable<string> texts,
            string taskType = "RETRIEVAL_DOCUMENT",
            CancellationToken ct = default);
    }
}

