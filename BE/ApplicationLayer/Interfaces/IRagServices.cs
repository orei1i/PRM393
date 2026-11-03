using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Chat;
using ApplicationLayer.DTOs.Knowledge;

namespace ApplicationLayer.Interfaces
{
    public interface IKnowledgeService
    {
        Task<List<KnowledgeDocResponse>> ListAsync(string? status, string? source, string? search);

        /// <summary>Khoá là tên trạng thái (Pending, Approved, Rejected), đúng cách web admin đọc.</summary>
        Task<Dictionary<string, long>> CountsAsync();

        Task<KnowledgeDocResponse> CreateAdminDocAsync(CreateKnowledgeDocRequest request, string adminId, CancellationToken ct = default);
        string ExtractPdfText(System.IO.Stream pdf);
        Task<KnowledgeDocResponse> ReviewAsync(string id, ReviewKnowledgeDocRequest request, string adminId, CancellationToken ct = default);
        Task<KnowledgeDocResponse> UpdateContentAsync(string id, UpdateKnowledgeContentRequest request, string adminId, CancellationToken ct = default);
        Task DeleteAsync(string id);
        Task<List<KnowledgeChunkResponse>> GetChunksAsync(string id, int limit);

        Task<List<KnowledgeDocResponse>> ListMineAsync(string chefId);
        Task<KnowledgeDocResponse> SubmitChefDocAsync(CreateKnowledgeDocRequest request, string chefId);
    }

    public interface IChatService
    {
        Task<GuestTrialResponse> GetGuestTrialAsync(string? guestToken);

        /// <summary>
        /// Lỗi trước sự kiện đầu tiên được ném ra (controller trả mã HTTP thường).
        /// Lỗi sau đó thành sự kiện "error", vì header đã gửi rồi.
        /// </summary>
        IAsyncEnumerable<ChatSseEvent> StreamReplyAsync(ChatCaller caller, string sessionId, ChatMessageRequest request, CancellationToken ct);

        Task<List<ChatHistoryMessage>> GetHistoryAsync(ChatCaller caller, string sessionId);
    }
}
