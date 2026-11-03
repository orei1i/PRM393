using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using DomainLayer.Entities;

namespace DomainLayer.Interfaces
{
    /// <summary>Kho tri thức trong DB RAG riêng.</summary>
    public interface IKnowledgeRepository
    {
        /// <summary>False khi chưa cấu hình RagDatabaseName, hoặc trùng DB chính.</summary>
        bool IsConfigured { get; }

        Task<KnowledgeDoc> CreateDocAsync(KnowledgeDoc doc);
        Task<KnowledgeDoc?> GetDocAsync(string id);
        Task<KnowledgeDoc?> FindByHashAsync(string contentHash);
        Task<List<KnowledgeDoc>> ListDocsAsync(string? status, string? source, string? search, string? chefId);
        Task<Dictionary<string, long>> CountByStatusAsync();
        Task UpdateDocAsync(KnowledgeDoc doc);

        /// <summary>Đổi trạng thái nguyên tử: hai admin cùng duyệt thì chỉ một người thắng.</summary>
        Task<bool> TryDecideAsync(string id, string fromStatus, string toStatus, string? note, string reviewedBy, DateTime reviewedAt);

        Task ReplaceChunksAsync(string docId, List<KnowledgeChunk> chunks);
        Task<List<KnowledgeChunk>> GetChunksAsync(string docId, int? limit = null);
        Task SaveEmbeddingsAsync(IEnumerable<KnowledgeChunk> chunks);
        Task DeleteChunksAsync(string docId);

        /// <summary>Tài liệu đã duyệt, chưa xoá. Truyền ids để chỉ kiểm tra các tài liệu đó.</summary>
        Task<List<KnowledgeDoc>> GetApprovedDocsAsync(IEnumerable<string>? ids = null);

        Task IncrementCitationAsync(string docId);
        Task<IngestionJob> CreateJobAsync(string docId);
        Task FinishJobAsync(string jobId, string status, string? error);
    }

    /// <summary>Đọc chữ từ tệp tài liệu.</summary>
    public interface IDocumentTextExtractor
    {
        /// <summary>BadRequestException khi tệp hỏng, có mật khẩu, hoặc quá nhiều trang.</summary>
        string ExtractPdf(Stream pdf);
    }

    /// <summary>Các thao tác nguyên tử của chat mà GenericRepository không có.</summary>
    public interface IChatStore
    {
        Task<ChatSession> GetOrCreateSessionAsync(string ownerKey, string clientSessionId, string? userId);
        Task<ChatSession?> FindSessionAsync(string ownerKey, string clientSessionId);

        /// <summary>Trừ một lượt miễn phí. False khi đã hết (không vượt limit dù gửi đồng thời).</summary>
        Task<bool> TryConsumeGuestTrialAsync(string guestKey, int limit);
        Task<int> GetGuestTrialUsedAsync(string guestKey);
    }
}
