using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Knowledge;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Nạp và duyệt tài liệu RAG. Tài liệu chuyên gia được cắt đoạn ngay để admin xem trước, nhưng chỉ tạo
    /// embedding khi được duyệt, nên tài liệu chưa duyệt không thể xuất hiện trong truy xuất.
    /// </summary>
    public class KnowledgeService : IKnowledgeService
    {
        private const int MaxContentChars = 2_000_000;
        private const int MaxChunks = 2000;
        private const int MinContentChars = 50;
        private const int MinRejectNoteChars = 10;

        private readonly IKnowledgeRepository _repo;
        private readonly IGeminiClient _gemini;
        private readonly IGenericRepository<User> _userRepo;
        private readonly RagVectorIndex _index;
        private readonly IDocumentTextExtractor _extractor;
        private readonly ILogger<KnowledgeService> _logger;

        public KnowledgeService(
            IKnowledgeRepository repo,
            IGeminiClient gemini,
            IGenericRepository<User> userRepo,
            RagVectorIndex index,
            IDocumentTextExtractor extractor,
            ILogger<KnowledgeService> logger)
        {
            _repo = repo;
            _gemini = gemini;
            _userRepo = userRepo;
            _index = index;
            _extractor = extractor;
            _logger = logger;
        }

        public async Task<List<KnowledgeDocResponse>> ListAsync(string? status, string? source, string? search)
        {
            EnsureStore();
            var docs = await _repo.ListDocsAsync(CanonicalStatus(status), CanonicalSource(source), search, null);
            return docs.Select(ToResponse).ToList();
        }

        public async Task<Dictionary<string, long>> CountsAsync()
        {
            EnsureStore();
            var counts = await _repo.CountByStatusAsync();
            return new[] { KnowledgeDocStatuses.Pending, KnowledgeDocStatuses.Approved, KnowledgeDocStatuses.Rejected }
                .ToDictionary(status => status, status => counts.GetValueOrDefault(status));
        }

        /// <summary>
        /// Tài liệu admin tải lên: duyệt ngay khi tạo embedding thành công. Embedding lỗi thì để Pending
        /// với IngestStatus = Failed và không vào chỉ mục; duyệt lại sẽ thử lại.
        /// </summary>
        public async Task<KnowledgeDocResponse> CreateAdminDocAsync(CreateKnowledgeDocRequest request, string adminId, CancellationToken ct = default)
        {
            EnsureStore();
            var adminName = await UserNameAsync(adminId) ?? "Quản trị viên";
            var doc = await CreateDocWithChunksAsync(request, KnowledgeSources.Who, null, null);

            try
            {
                await EmbedAndApproveAsync(doc, null, adminName, ct);
            }
            catch (ServiceUnavailableException ex)
            {
                _logger.LogWarning(ex, "Không tạo được embedding cho tài liệu {DocId}", doc.Id);
            }

            return ToResponse((await _repo.GetDocAsync(doc.Id))!);
        }

        public async Task<KnowledgeDocResponse> SubmitChefDocAsync(CreateKnowledgeDocRequest request, string chefId)
        {
            EnsureStore();
            var doc = await CreateDocWithChunksAsync(request, KnowledgeSources.Chef, chefId, await UserNameAsync(chefId));
            return ToResponse(doc);
        }

        public string ExtractPdfText(System.IO.Stream pdf) => _extractor.ExtractPdf(pdf);

        public async Task<List<KnowledgeDocResponse>> ListMineAsync(string chefId)
        {
            EnsureStore();
            var docs = await _repo.ListDocsAsync(null, null, null, chefId);
            return docs.Select(ToResponse).ToList();
        }

        public async Task<KnowledgeDocResponse> ReviewAsync(string id, ReviewKnowledgeDocRequest request, string adminId, CancellationToken ct = default)
        {
            EnsureStore();
            var doc = await GetRequiredAsync(id);
            if (doc.Status != KnowledgeDocStatuses.Pending)
            {
                throw new ConflictException("Tài liệu này đã được xử lý trước đó.", "already_decided");
            }

            var adminName = await UserNameAsync(adminId) ?? "Quản trị viên";
            var note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim();

            if (request.Decision == "Reject")
            {
                if (note == null || note.Length < MinRejectNoteChars)
                {
                    throw new BadRequestException($"Lý do từ chối phải có ít nhất {MinRejectNoteChars} ký tự.", "note_too_short");
                }
                if (!await _repo.TryDecideAsync(id, KnowledgeDocStatuses.Pending, KnowledgeDocStatuses.Rejected, note, adminName, DateTime.UtcNow))
                {
                    throw new ConflictException("Tài liệu này đã được xử lý trước đó.", "already_decided");
                }
                _index.RemoveDoc(id);
            }
            else
            {
                await EmbedAndApproveAsync(doc, note, adminName, ct);
            }

            return ToResponse(await GetRequiredAsync(id));
        }

        public async Task<KnowledgeDocResponse> UpdateContentAsync(string id, UpdateKnowledgeContentRequest request, string adminId, CancellationToken ct = default)
        {
            EnsureStore();
            var doc = await GetRequiredAsync(id);
            var normalized = ValidatedContent(request.Content);
            var hash = RagText.Hash(normalized);
            var same = await _repo.FindByHashAsync(hash);
            if (same != null && same.Id != id)
            {
                throw new ConflictException($"Nội dung này trùng với tài liệu \"{same.Title}\".", "duplicate_document");
            }

            var chunks = BuildChunks(id, normalized);
            var wasApproved = doc.Status == KnowledgeDocStatuses.Approved;
            if (wasApproved)
            {
                // Tạo embedding trước khi thay: dịch vụ AI lỗi thì bản cũ vẫn phục vụ nguyên vẹn.
                await EmbedChunksAsync(chunks, ct);
            }

            doc.Content = normalized;
            doc.ContentHash = hash;
            doc.ChunkCount = chunks.Count;
            doc.IngestStatus = wasApproved ? IngestStatuses.Done : IngestStatuses.Pending;
            doc.IngestError = null;
            await _repo.ReplaceChunksAsync(id, chunks);
            await _repo.UpdateDocAsync(doc);
            if (wasApproved) _index.SetDoc(id, chunks);

            return ToResponse(doc);
        }

        public async Task DeleteAsync(string id)
        {
            EnsureStore();
            var doc = await GetRequiredAsync(id);
            doc.IsDeleted = true;
            doc.DeletedAt = DateTime.UtcNow;
            await _repo.UpdateDocAsync(doc);
            await _repo.DeleteChunksAsync(id);
            _index.RemoveDoc(id);
        }

        public async Task<List<KnowledgeChunkResponse>> GetChunksAsync(string id, int limit)
        {
            EnsureStore();
            await GetRequiredAsync(id);
            var chunks = await _repo.GetChunksAsync(id, Math.Clamp(limit, 1, 200));
            return chunks.Select(c => new KnowledgeChunkResponse
            {
                Id = c.Id,
                DocId = c.DocId,
                ChunkIndex = c.ChunkIndex,
                Content = c.Content
            }).ToList();
        }

        private async Task<KnowledgeDoc> CreateDocWithChunksAsync(CreateKnowledgeDocRequest request, string source, string? chefId, string? chefName)
        {
            var normalized = ValidatedContent(request.Content);
            var hash = RagText.Hash(normalized);
            var same = await _repo.FindByHashAsync(hash);
            if (same != null)
            {
                throw new ConflictException($"Nội dung này trùng với tài liệu \"{same.Title}\".", "duplicate_document");
            }

            var fileUrl = string.IsNullOrWhiteSpace(request.FileUrl) ? null : request.FileUrl.Trim();
            if (fileUrl != null && !IsHttpUrl(fileUrl))
            {
                throw new BadRequestException("Liên kết nguồn phải bắt đầu bằng http:// hoặc https://.", "invalid_url");
            }

            var doc = await _repo.CreateDocAsync(new KnowledgeDoc
            {
                Title = request.Title.Trim(),
                Source = source,
                ChefId = chefId,
                ChefName = chefName,
                FileUrl = fileUrl,
                Publisher = string.IsNullOrWhiteSpace(request.Publisher)
                    ? (source == KnowledgeSources.Who ? "WHO" : chefName)
                    : request.Publisher.Trim(),
                PublishedAt = request.PublishedAt,
                Content = normalized,
                ContentHash = hash,
                Status = KnowledgeDocStatuses.Pending
            });

            var chunks = BuildChunks(doc.Id, normalized);
            await _repo.ReplaceChunksAsync(doc.Id, chunks);
            doc.ChunkCount = chunks.Count;
            await _repo.UpdateDocAsync(doc);
            return doc;
        }

        private async Task EmbedAndApproveAsync(KnowledgeDoc doc, string? note, string reviewedBy, CancellationToken ct)
        {
            var job = await _repo.CreateJobAsync(doc.Id);
            var chunks = await _repo.GetChunksAsync(doc.Id);
            try
            {
                await EmbedChunksAsync(chunks, ct);
                await _repo.SaveEmbeddingsAsync(chunks);
            }
            catch (ServiceUnavailableException ex)
            {
                await _repo.FinishJobAsync(job.Id, IngestStatuses.Failed, ex.Message);
                doc.IngestStatus = IngestStatuses.Failed;
                doc.IngestError = ex.Message;
                await _repo.UpdateDocAsync(doc);
                throw;
            }

            if (!await _repo.TryDecideAsync(doc.Id, KnowledgeDocStatuses.Pending, KnowledgeDocStatuses.Approved, note, reviewedBy, DateTime.UtcNow))
            {
                await _repo.FinishJobAsync(job.Id, IngestStatuses.Failed, "already_decided");
                throw new ConflictException("Tài liệu này đã được xử lý trước đó.", "already_decided");
            }

            var fresh = await GetRequiredAsync(doc.Id);
            fresh.IngestStatus = IngestStatuses.Done;
            fresh.IngestError = null;
            await _repo.UpdateDocAsync(fresh);
            await _repo.FinishJobAsync(job.Id, IngestStatuses.Done, null);
            _index.SetDoc(doc.Id, chunks);
        }

        private async Task EmbedChunksAsync(List<KnowledgeChunk> chunks, CancellationToken ct)
        {
            if (!_gemini.IsConfigured)
            {
                throw new ServiceUnavailableException("Chưa cấu hình dịch vụ AI nên chưa tạo được chỉ mục cho tài liệu này.");
            }

            var vectors = await _gemini.EmbedAsync(chunks.Select(c => c.Content), "RETRIEVAL_DOCUMENT", ct);
            if (vectors.Count != chunks.Count)
            {
                throw new ServiceUnavailableException("Dịch vụ embedding trả thiếu kết quả. Bạn thử lại sau nhé.");
            }

            for (var i = 0; i < chunks.Count; i++)
            {
                chunks[i].Embedding = RagText.UnitVector(vectors[i])
                    ?? throw new ServiceUnavailableException("Dịch vụ embedding trả vector không hợp lệ. Bạn thử lại sau nhé.");
            }
        }

        private static List<KnowledgeChunk> BuildChunks(string docId, string normalized)
        {
            var pieces = RagText.Chunk(normalized);
            if (pieces.Count > MaxChunks)
            {
                throw new PayloadTooLargeException($"Tài liệu quá dài: tối đa {MaxChunks} đoạn.");
            }

            return pieces.Select((content, i) => new KnowledgeChunk
            {
                DocId = docId,
                ChunkIndex = i,
                Content = content
            }).ToList();
        }

        private static string ValidatedContent(string? content)
        {
            var normalized = RagText.Normalize(content);
            if (normalized.Length < MinContentChars)
            {
                throw new BadRequestException($"Nội dung tài liệu trống hoặc quá ngắn (cần ít nhất {MinContentChars} ký tự).", "empty_document");
            }
            if (normalized.Length > MaxContentChars)
            {
                throw new PayloadTooLargeException("Tài liệu quá dài: tối đa 2 triệu ký tự.");
            }
            return normalized;
        }

        private void EnsureStore()
        {
            if (!_repo.IsConfigured)
            {
                throw new ServiceUnavailableException("Kho tri thức chưa được cấu hình trên máy chủ.", "rag_not_configured");
            }
        }

        private async Task<KnowledgeDoc> GetRequiredAsync(string id) =>
            await _repo.GetDocAsync(id) ?? throw new NotFoundException($"Không tìm thấy tài liệu với id: {id}");

        private async Task<string?> UserNameAsync(string userId)
        {
            var user = await _userRepo.FindByIdAsync(userId);
            return user?.FullName;
        }

        private static string? CanonicalStatus(string? status)
        {
            if (string.IsNullOrWhiteSpace(status)) return null;
            return status.Trim().ToLowerInvariant() switch
            {
                "pending" => KnowledgeDocStatuses.Pending,
                "approved" => KnowledgeDocStatuses.Approved,
                "rejected" => KnowledgeDocStatuses.Rejected,
                _ => throw new BadRequestException($"Trạng thái tài liệu không hợp lệ: '{status}'.")
            };
        }

        private static string? CanonicalSource(string? source)
        {
            if (string.IsNullOrWhiteSpace(source)) return null;
            return source.Trim().ToLowerInvariant() switch
            {
                "who" => KnowledgeSources.Who,
                "chef" => KnowledgeSources.Chef,
                _ => throw new BadRequestException($"Nguồn tài liệu không hợp lệ: '{source}'.")
            };
        }

        private static bool IsHttpUrl(string value) =>
            Uri.TryCreate(value, UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);

        private static KnowledgeDocResponse ToResponse(KnowledgeDoc d) => new()
        {
            Id = d.Id,
            ChefId = d.ChefId,
            ChefName = d.ChefName,
            Title = d.Title,
            Source = d.Source,
            FileUrl = d.FileUrl ?? string.Empty,
            Publisher = d.Publisher,
            PublishedAt = d.PublishedAt,
            CreatedAt = d.CreatedAt,
            Status = d.Status,
            ChunkCount = d.ChunkCount,
            CitationCount = d.CitationCount,
            ReviewNote = d.ReviewNote,
            ReviewedBy = d.ReviewedBy,
            ReviewedAt = d.ReviewedAt,
            IngestStatus = d.IngestStatus,
            IngestError = d.IngestError
        };
    }
}
