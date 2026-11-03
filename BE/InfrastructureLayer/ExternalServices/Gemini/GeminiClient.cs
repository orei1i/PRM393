using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using InfrastructureLayer.Configuration;
using InfrastructureLayer.Database;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MongoDB.Driver;

namespace InfrastructureLayer.ExternalServices.Gemini
{
    public class GeminiClient : IGeminiClient
    {
        private readonly HttpClient _httpClient;
        private readonly GeminiSettings _settings;
        private readonly MongoDbContext _mongoDbContext;
        private readonly ILogger<GeminiClient> _logger;
        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNameCaseInsensitive = true
        };

        public GeminiClient(
            HttpClient httpClient,
            IOptions<GeminiSettings> options,
            MongoDbContext mongoDbContext,
            ILogger<GeminiClient> logger)
        {
            _httpClient = httpClient;
            _settings = options.Value ?? new GeminiSettings();
            _mongoDbContext = mongoDbContext;
            _logger = logger;
        }

        private bool IsMockMode =>
            string.IsNullOrWhiteSpace(_settings.ApiKey) ||
            _settings.ApiKey.StartsWith("dummy", StringComparison.OrdinalIgnoreCase) ||
            _settings.ApiKey.Contains("YOUR_GEMINI_API_KEY", StringComparison.OrdinalIgnoreCase);

        private const int StreamMaxAttempts = 4;

        /// <summary>Test đặt về 0 để không phải chờ thật.</summary>
        internal static TimeSpan StreamRetryBaseDelay { get; set; } = TimeSpan.FromSeconds(1);

        public bool IsConfigured => !IsMockMode;

        public async Task<T> GenerateJsonAsync<T>(
            string prompt,
            byte[]? imageBytes = null,
            string? mimeType = null,
            string taskType = "Vision",
            string? userId = null,
            string? scanId = null,
            CancellationToken ct = default)
        {
            var sw = Stopwatch.StartNew();
            int promptTokens = 0;
            int candidatesTokens = 0;

            if (IsMockMode)
            {
                _logger.LogInformation("GeminiClient chạy ở chế độ MOCK (chưa cấu hình API Key thật).");
                await Task.Delay(300, ct); // Giả lập độ trễ mạng thực tế
                sw.Stop();

                var mockJson = GetMockJsonForType<T>(taskType);
                return JsonSerializer.Deserialize<T>(mockJson, JsonOptions)!;
            }

            var requestUrl = $"{_settings.BaseUrl.TrimEnd('/')}/models/{_settings.Model}:generateContent";

            // Chuẩn bị payload request cho Gemini
            var parts = new List<object>
            {
                new { text = prompt }
            };

            if (imageBytes != null && imageBytes.Length > 0)
            {
                parts.Add(new
                {
                    inline_data = new
                    {
                        mime_type = string.IsNullOrWhiteSpace(mimeType) ? "image/jpeg" : mimeType,
                        data = Convert.ToBase64String(imageBytes)
                    }
                });
            }

            var payload = new
            {
                contents = new[]
                {
                    new { parts = parts.ToArray() }
                },
                generationConfig = new
                {
                    responseMimeType = "application/json",
                    temperature = 0.2
                }
            };

            var jsonPayload = JsonSerializer.Serialize(payload);
            const int maxRetries = 3;
            Exception? lastException = null;

            for (int attempt = 1; attempt <= maxRetries; attempt++)
            {
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Post, requestUrl);
                    request.Headers.Add("x-goog-api-key", _settings.ApiKey);
                    request.Content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

                    var response = await _httpClient.SendAsync(request, ct);

                    if (response.StatusCode == HttpStatusCode.TooManyRequests ||
                        response.StatusCode == HttpStatusCode.ServiceUnavailable)
                    {
                        if (attempt == maxRetries)
                        {
                            throw new TooManyRequestsException("Hệ thống AI đang quá tải. Bạn thử lại sau ít phút nhé.");
                        }

                        var delayMs = (int)Math.Pow(2, attempt) * 1000;
                        _logger.LogWarning("Gemini trả mã {StatusCode}. Thử lại lần {Attempt}/{MaxRetries} sau {Delay}ms...", response.StatusCode, attempt, maxRetries, delayMs);
                        await Task.Delay(delayMs, ct);
                        continue;
                    }

                    if (!response.IsSuccessStatusCode)
                    {
                        throw new HttpRequestException($"Gemini API trả mã lỗi {(int)response.StatusCode}.");
                    }

                    var responseBody = await response.Content.ReadAsStringAsync(ct);
                    sw.Stop();

                    using var doc = JsonDocument.Parse(responseBody);
                    var root = doc.RootElement;

                    if (root.TryGetProperty("usageMetadata", out var usage))
                    {
                        if (usage.TryGetProperty("promptTokenCount", out var pTokens)) promptTokens = pTokens.GetInt32();
                        if (usage.TryGetProperty("candidatesTokenCount", out var cTokens)) candidatesTokens = cTokens.GetInt32();
                    }

                    var rawText = string.Empty;
                    if (root.TryGetProperty("candidates", out var candidates) && candidates.GetArrayLength() > 0)
                    {
                        var firstCandidate = candidates[0];
                        if (firstCandidate.TryGetProperty("content", out var content) &&
                            content.TryGetProperty("parts", out var respParts) &&
                            respParts.GetArrayLength() > 0)
                        {
                            rawText = respParts[0].GetProperty("text").GetString() ?? string.Empty;
                        }
                    }

                    var cleanedJson = CleanJsonFences(rawText);
                    var result = JsonSerializer.Deserialize<T>(cleanedJson, JsonOptions);

                    await LogAiCallAsync(taskType, _settings.Model, promptTokens, candidatesTokens, sw.ElapsedMilliseconds, userId, scanId, success: true);
                    return result!;
                }
                catch (TooManyRequestsException)
                {
                    throw;
                }
                catch (Exception ex) when (attempt < maxRetries && !ct.IsCancellationRequested)
                {
                    lastException = ex;
                    var delayMs = (int)Math.Pow(2, attempt) * 1000;
                    _logger.LogWarning(ex, "Lỗi khi gọi Gemini (lần {Attempt}/{MaxRetries}). Đợi {Delay}ms trước khi thử lại...", attempt, maxRetries, delayMs);
                    await Task.Delay(delayMs, ct);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    // Hết lượt thử: người dùng nhận câu dễ hiểu, chi tiết kỹ thuật chỉ vào log.
                    sw.Stop();
                    _logger.LogWarning(ex, "Gemini vẫn lỗi sau {MaxRetries} lần thử.", maxRetries);
                    await LogAiCallAsync(taskType, _settings.Model, promptTokens, candidatesTokens, sw.ElapsedMilliseconds, userId, scanId, success: false, errorMessage: ex.Message);
                    throw new ServiceUnavailableException("Hệ thống AI tạm thời không phản hồi. Bạn thử lại sau nhé.", ex, "model_unavailable");
                }
            }

            sw.Stop();
            await LogAiCallAsync(taskType, _settings.Model, promptTokens, candidatesTokens, sw.ElapsedMilliseconds, userId, scanId, success: false, errorMessage: lastException?.Message);
            throw new ServerFailureException("Không thể kết nối đến hệ thống trí tuệ nhân tạo Gemini.", lastException ?? new Exception("Lỗi không xác định khi gọi Gemini."));
        }

        public async Task<string> GenerateTextAsync(string prompt, string taskType = "General", string? userId = null, CancellationToken ct = default)
        {
            var sw = Stopwatch.StartNew();
            if (IsMockMode)
            {
                sw.Stop();
                return "Mock Gemini text generation response.";
            }

            var requestUrl = $"{_settings.BaseUrl.TrimEnd('/')}/models/{_settings.Model}:generateContent";
            using var request = new HttpRequestMessage(HttpMethod.Post, requestUrl);
            request.Headers.Add("x-goog-api-key", _settings.ApiKey);

            var payload = new
            {
                contents = new[]
                {
                    new { parts = new[] { new { text = prompt } } }
                }
            };
            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

            var response = await _httpClient.SendAsync(request, ct);
            sw.Stop();

            if (!response.IsSuccessStatusCode)
            {
                var err = await response.Content.ReadAsStringAsync(ct);
                throw new DomainException($"Gemini API error: {err}");
            }

            var body = await response.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(body);
            var rawText = string.Empty;
            if (doc.RootElement.TryGetProperty("candidates", out var candidates) && candidates.GetArrayLength() > 0)
            {
                rawText = candidates[0].GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString() ?? string.Empty;
            }

            await LogAiCallAsync(taskType, _settings.Model, 0, 0, sw.ElapsedMilliseconds, userId, success: true);
            return rawText;
        }

        public async IAsyncEnumerable<string> StreamTextAsync(
            string prompt,
            string taskType = "Chat",
            string? userId = null,
            [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default,
            string? systemInstruction = null)
        {
            if (IsMockMode)
            {
                yield return "Chào ";
                yield return "bạn, ";
                yield return "đây là câu trả lời thử nghiệm từ hệ thống tư vấn dinh dưỡng thuần chay.";
                yield break;
            }

            var sw = Stopwatch.StartNew();
            var requestUrl = $"{_settings.BaseUrl.TrimEnd('/')}/models/{_settings.Model}:streamGenerateContent?alt=sse";
            var payload = new Dictionary<string, object>
            {
                ["contents"] = new[]
                {
                    new { role = "user", parts = new[] { new { text = prompt } } }
                },
                ["generationConfig"] = new { temperature = 0.2 }
            };
            if (!string.IsNullOrWhiteSpace(systemInstruction))
            {
                payload["system_instruction"] = new { parts = new[] { new { text = systemInstruction } } };
            }
            var body = JsonSerializer.Serialize(payload);

            // Chưa có token nào gửi đi nên thử lại an toàn. 503 và 429 của Gemini thường hết sau vài giây.
            HttpResponseMessage? received = null;
            for (var attempt = 1; ; attempt++)
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, requestUrl);
                request.Headers.Add("x-goog-api-key", _settings.ApiKey);
                request.Content = new StringContent(body, Encoding.UTF8, "application/json");
                received = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);

                var overloaded = received.StatusCode == HttpStatusCode.TooManyRequests || received.StatusCode == HttpStatusCode.ServiceUnavailable;
                if (!overloaded || attempt >= StreamMaxAttempts) break;

                received.Dispose();
                await Task.Delay(StreamRetryBaseDelay * Math.Pow(2, attempt - 1), ct);
            }

            using var response = received;
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Gemini model {Model} trả mã {StatusCode}", _settings.Model, (int)response.StatusCode);
                await LogAiCallAsync(taskType, _settings.Model, 0, 0, sw.ElapsedMilliseconds, userId, success: false, errorMessage: $"HTTP {(int)response.StatusCode}");
                throw new ServiceUnavailableException("Hệ thống AI tạm thời không phản hồi. Bạn thử lại sau nhé.", "model_unavailable");
            }

            using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var reader = new System.IO.StreamReader(stream);
            int promptTokens = 0;
            int candidatesTokens = 0;
            string? finishReason = null;

            while (!ct.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(ct);
                if (line == null) break;
                if (string.IsNullOrWhiteSpace(line) || !line.StartsWith("data:")) continue;

                var dataJson = line.Substring(5).TrimStart();
                string? chunkText = null;
                try
                {
                    using var doc = JsonDocument.Parse(dataJson);
                    if (doc.RootElement.TryGetProperty("usageMetadata", out var usage))
                    {
                        if (usage.TryGetProperty("promptTokenCount", out var pTokens)) promptTokens = pTokens.GetInt32();
                        if (usage.TryGetProperty("candidatesTokenCount", out var cTokens)) candidatesTokens = cTokens.GetInt32();
                    }
                    if (doc.RootElement.TryGetProperty("candidates", out var finishCandidates) && finishCandidates.GetArrayLength() > 0 &&
                        finishCandidates[0].TryGetProperty("finishReason", out var reason))
                    {
                        finishReason = reason.GetString();
                    }
                    if (doc.RootElement.TryGetProperty("candidates", out var candidates) && candidates.GetArrayLength() > 0 &&
                        candidates[0].TryGetProperty("content", out var content) &&
                        content.TryGetProperty("parts", out var parts) && parts.GetArrayLength() > 0 &&
                        parts[0].TryGetProperty("text", out var textValue))
                    {
                        chunkText = textValue.GetString();
                    }
                }
                catch (JsonException)
                {
                    // Bỏ qua chunk không parse được
                }

                if (!string.IsNullOrEmpty(chunkText))
                {
                    yield return chunkText;
                }
            }

            ct.ThrowIfCancellationRequested();

            // Kết nối đóng êm mà không có finishReason nghĩa là luồng bị cắt, hoặc mô hình từ chối trả lời.
            // Không được coi câu trả lời dở là đã xong. MAX_TOKENS vẫn là câu trả lời dùng được.
            if (finishReason != "STOP" && finishReason != "MAX_TOKENS")
            {
                await LogAiCallAsync(taskType, _settings.Model, promptTokens, candidatesTokens, sw.ElapsedMilliseconds, userId, success: false, errorMessage: $"finishReason={finishReason ?? "none"}");
                throw new ServiceUnavailableException("Hệ thống AI bị gián đoạn. Bạn thử lại nhé.", "model_unavailable");
            }

            await LogAiCallAsync(taskType, _settings.Model, promptTokens, candidatesTokens, sw.ElapsedMilliseconds, userId, success: true);
        }

        public async Task<List<float[]>> EmbedAsync(IEnumerable<string> texts, string taskType = "RETRIEVAL_DOCUMENT", CancellationToken ct = default)
        {
            var inputs = new List<string>(texts);
            if (IsMockMode)
            {
                var mockList = new List<float[]>();
                foreach (var _ in inputs)
                {
                    mockList.Add(new float[_settings.EmbeddingDimensions]);
                }
                return mockList;
            }

            const int batchSize = 100;
            var sw = Stopwatch.StartNew();
            var result = new List<float[]>(inputs.Count);
            for (var offset = 0; offset < inputs.Count; offset += batchSize)
            {
                var batch = inputs.GetRange(offset, Math.Min(batchSize, inputs.Count - offset));
                result.AddRange(await EmbedBatchAsync(batch, taskType, ct));
            }

            await LogAiCallAsync("Embedding", _settings.EmbeddingModel, 0, 0, sw.ElapsedMilliseconds, success: true);
            return result;
        }

        private async Task<List<float[]>> EmbedBatchAsync(List<string> batch, string taskType, CancellationToken ct)
        {
            var requestUrl = $"{_settings.BaseUrl.TrimEnd('/')}/models/{_settings.EmbeddingModel}:batchEmbedContents";
            var requests = new List<object>();
            foreach (var t in batch)
            {
                requests.Add(new
                {
                    model = $"models/{_settings.EmbeddingModel}",
                    content = new { parts = new[] { new { text = t } } },
                    taskType,
                    outputDimensionality = _settings.EmbeddingDimensions
                });
            }
            var body = JsonSerializer.Serialize(new { requests });

            const int maxRetries = 3;
            for (var attempt = 1; ; attempt++)
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, requestUrl);
                request.Headers.Add("x-goog-api-key", _settings.ApiKey);
                request.Content = new StringContent(body, Encoding.UTF8, "application/json");

                HttpResponseMessage response;
                try
                {
                    response = await _httpClient.SendAsync(request, ct);
                }
                catch (Exception ex) when ((ex is HttpRequestException || ex is TaskCanceledException) && !ct.IsCancellationRequested)
                {
                    if (attempt < maxRetries)
                    {
                        await Task.Delay((int)Math.Pow(2, attempt) * 500, ct);
                        continue;
                    }
                    throw new ServiceUnavailableException("Không kết nối được dịch vụ embedding. Bạn thử lại sau nhé.", ex);
                }

                using (response)
                {
                    if ((response.StatusCode == HttpStatusCode.TooManyRequests || response.StatusCode == HttpStatusCode.ServiceUnavailable) && attempt < maxRetries)
                    {
                        // Nạp tài liệu dài vượt hạn mức theo phút thì chờ qua cửa sổ. Câu hỏi của người dùng không chờ lâu.
                        var isDocument = taskType == "RETRIEVAL_DOCUMENT";
                        var wait = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(isDocument ? 60 : Math.Pow(2, attempt) / 2);
                        await Task.Delay(isDocument ? wait : TimeSpan.FromSeconds(Math.Min(wait.TotalSeconds, 4)), ct);
                        continue;
                    }
                    if (!response.IsSuccessStatusCode)
                    {
                        _logger.LogWarning("Gemini embedding trả mã {StatusCode}", (int)response.StatusCode);
                        throw new ServiceUnavailableException(response.StatusCode == HttpStatusCode.TooManyRequests
                            ? "Hệ thống AI đang quá tải. Bạn thử lại sau ít phút nhé."
                            : "Dịch vụ embedding đang lỗi. Bạn thử lại sau nhé.");
                    }

                    var text = await response.Content.ReadAsStringAsync(ct);
                    using var doc = JsonDocument.Parse(text);
                    var vectors = new List<float[]>();
                    if (doc.RootElement.TryGetProperty("embeddings", out var embeddings))
                    {
                        foreach (var item in embeddings.EnumerateArray())
                        {
                            var values = item.GetProperty("values");
                            var floatArr = new float[values.GetArrayLength()];
                            int idx = 0;
                            foreach (var v in values.EnumerateArray())
                            {
                                floatArr[idx++] = v.GetSingle();
                            }
                            vectors.Add(floatArr);
                        }
                    }
                    if (vectors.Count != batch.Count)
                    {
                        throw new ServiceUnavailableException("Dịch vụ embedding trả thiếu kết quả. Bạn thử lại sau nhé.");
                    }
                    return vectors;
                }
            }
        }

        private static string CleanJsonFences(string input)
        {
            if (string.IsNullOrWhiteSpace(input)) return "{}";
            var text = input.Trim();
            // Lọc bỏ markdown code fence ```json ... ```
            if (text.StartsWith("```json", StringComparison.OrdinalIgnoreCase))
            {
                text = text.Substring(7);
            }
            else if (text.StartsWith("```"))
            {
                text = text.Substring(3);
            }

            if (text.EndsWith("```"))
            {
                text = text.Substring(0, text.Length - 3);
            }

            return text.Trim();
        }

        private static string GetMockJsonForType<T>(string taskType)
        {
            // Trả về JSON mock chuẩn cho Vision tủ lạnh
            if (taskType.Equals("Vision", StringComparison.OrdinalIgnoreCase))
            {
                return """
                {
                  "items": [
                    {
                      "label": "Bông cải xanh",
                      "confidence": 0.96,
                      "isVegan": true,
                      "nonVeganReason": null,
                      "veganAlternatives": [],
                      "box_2d": [180, 60, 400, 360],
                      "alternatives": [
                        { "label": "Súp lơ", "confidence": 0.03, "isVegan": true }
                      ]
                    },
                    {
                      "label": "Cà chua",
                      "confidence": 0.95,
                      "isVegan": true,
                      "nonVeganReason": null,
                      "veganAlternatives": [],
                      "box_2d": [200, 400, 420, 650],
                      "alternatives": []
                    },
                    {
                      "label": "Đậu hũ",
                      "confidence": 0.92,
                      "isVegan": true,
                      "nonVeganReason": null,
                      "veganAlternatives": [],
                      "box_2d": [450, 100, 650, 350],
                      "alternatives": [
                        { "label": "Đậu phụ", "confidence": 0.90, "isVegan": true }
                      ]
                    },
                    {
                      "label": "Trứng gà",
                      "confidence": 0.94,
                      "isVegan": false,
                      "nonVeganReason": "Có nguồn gốc động vật: trứng",
                      "veganAlternatives": ["Đậu hũ non", "Bột hạt lanh"],
                      "box_2d": [430, 50, 550, 410],
                      "alternatives": []
                    },
                    {
                      "label": "Nấm rơm",
                      "confidence": 0.89,
                      "isVegan": true,
                      "nonVeganReason": null,
                      "veganAlternatives": [],
                      "box_2d": [660, 300, 850, 550],
                      "alternatives": []
                    }
                  ]
                }
                """;
            }

            return "{}";
        }

        private async Task LogAiCallAsync(
            string taskType,
            string model,
            int promptTokens,
            int candidatesTokens,
            long latencyMs,
            string? userId = null,
            string? scanId = null,
            bool success = true,
            string? errorMessage = null)
        {
            try
            {
                var log = new AiLog
                {
                    TaskType = taskType,
                    Model = model,
                    UserId = userId,
                    ScanId = scanId,
                    PromptTokens = promptTokens,
                    CandidatesTokens = candidatesTokens,
                    LatencyMs = latencyMs,
                    Success = success,
                    ErrorMessage = errorMessage,
                    CreatedAt = DateTime.UtcNow
                };

                await _mongoDbContext.AiLogs.InsertOneAsync(log);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Không thể ghi nhật ký ai_logs (non-fatal)");
            }
        }
    }
}
