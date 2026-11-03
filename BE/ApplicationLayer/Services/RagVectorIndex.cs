using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DomainLayer.Entities;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    public sealed record RagHit(KnowledgeChunk Chunk, double Score);

    /// <summary>
    /// Chỉ mục vector trong RAM (khoảng 1.000 chunk, theo kế hoạch backend), chỉ gồm tài liệu đã duyệt.
    /// Vector đã chuẩn hoá nên cosine là tích vô hướng. Nạp lại định kỳ để nhiều instance không lệch lâu;
    /// ChatService vẫn kiểm tra lại trạng thái tài liệu trong DB trước khi dùng kết quả.
    /// </summary>
    public class RagVectorIndex
    {
        private static readonly TimeSpan ReloadAfter = TimeSpan.FromMinutes(5);

        private readonly IKnowledgeRepository _repo;
        private readonly SemaphoreSlim _loadLock = new(1, 1);
        private readonly ConcurrentDictionary<string, IReadOnlyList<KnowledgeChunk>> _docs = new();
        private DateTime _loadedAt = DateTime.MinValue;

        public RagVectorIndex(IKnowledgeRepository repo)
        {
            _repo = repo;
        }

        public async Task EnsureLoadedAsync()
        {
            if (DateTime.UtcNow - _loadedAt < ReloadAfter) return;

            await _loadLock.WaitAsync();
            try
            {
                if (DateTime.UtcNow - _loadedAt < ReloadAfter) return;

                var approved = await _repo.GetApprovedDocsAsync();
                var ids = approved.Select(d => d.Id).ToHashSet();
                foreach (var stale in _docs.Keys.Where(id => !ids.Contains(id)))
                {
                    _docs.TryRemove(stale, out _);
                }
                foreach (var doc in approved)
                {
                    _docs[doc.Id] = Usable(await _repo.GetChunksAsync(doc.Id));
                }
                _loadedAt = DateTime.UtcNow;
            }
            finally
            {
                _loadLock.Release();
            }
        }

        public void SetDoc(string docId, IEnumerable<KnowledgeChunk> chunks) => _docs[docId] = Usable(chunks);

        public void RemoveDoc(string docId) => _docs.TryRemove(docId, out _);

        public List<RagHit> Search(float[] unitQuery, int topK, double minScore)
        {
            var hits = new List<RagHit>();
            foreach (var chunks in _docs.Values)
            {
                foreach (var chunk in chunks)
                {
                    var score = RagText.Dot(unitQuery, chunk.Embedding!);
                    if (score >= minScore) hits.Add(new RagHit(chunk, score));
                }
            }

            return hits.OrderByDescending(h => h.Score).Take(topK).ToList();
        }

        private static List<KnowledgeChunk> Usable(IEnumerable<KnowledgeChunk> chunks) =>
            chunks.Where(c => c.Embedding is { Length: > 0 }).ToList();
    }

    /// <summary>Luồng trả lời đang chạy theo phiên: yêu cầu mới huỷ yêu cầu cũ và chờ nó lưu xong.</summary>
    public class ChatStreamRegistry
    {
        private sealed class Entry
        {
            public CancellationTokenSource Cts { get; } = new();
            public TaskCompletionSource Done { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }

        private readonly ConcurrentDictionary<string, Entry> _active = new();

        public async Task<(CancellationToken Token, Action Release)> AcquireAsync(string sessionKey)
        {
            var entry = new Entry();
            while (!_active.TryAdd(sessionKey, entry))
            {
                if (_active.TryGetValue(sessionKey, out var previous))
                {
                    previous.Cts.Cancel();
                    await Task.WhenAny(previous.Done.Task, Task.Delay(TimeSpan.FromSeconds(3)));
                    _active.TryRemove(new KeyValuePair<string, Entry>(sessionKey, previous));
                }
            }

            return (entry.Cts.Token, () =>
            {
                _active.TryRemove(new KeyValuePair<string, Entry>(sessionKey, entry));
                entry.Done.TrySetResult();
                entry.Cts.Dispose();
            });
        }
    }
}
