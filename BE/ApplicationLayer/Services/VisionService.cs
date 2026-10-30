using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Vision;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    public class VisionService : IVisionService
    {
        private readonly IGeminiClient _geminiClient;
        private readonly IGenericRepository<Ingredient> _ingredientRepo;
        private readonly IGenericRepository<HealthProfile> _healthProfileRepo;
        private readonly ILogger<VisionService> _logger;

        private const long MaxFileSizeBytes = 10 * 1024 * 1024; // 10 MB
        private const int MaxCallsPerMinute = 10;
        private static readonly ConcurrentDictionary<string, List<DateTime>> UserRateLimitTracker = new();

        public VisionService(
            IGeminiClient geminiClient,
            IGenericRepository<Ingredient> ingredientRepo,
            IGenericRepository<HealthProfile> healthProfileRepo,
            ILogger<VisionService> logger)
        {
            _geminiClient = geminiClient;
            _ingredientRepo = ingredientRepo;
            _healthProfileRepo = healthProfileRepo;
            _logger = logger;
        }

        public async Task<ScanResultDto> ScanFridgeImageAsync(
            IFormFile image,
            string? currentUserId,
            CancellationToken ct = default)
        {
            // 1. Kiểm tra rate limit (10 lần / phút cho mỗi user)
            var rateKey = !string.IsNullOrWhiteSpace(currentUserId) ? currentUserId : "anonymous";
            CheckRateLimit(rateKey);

            // 2. Kiểm tra file ảnh hợp lệ
            if (image == null || image.Length == 0)
            {
                throw new BadRequestException("Vui lòng tải lên một bức ảnh hợp lệ.");
            }

            if (image.Length > MaxFileSizeBytes)
            {
                throw new PayloadTooLargeException("Dung lượng ảnh vượt quá 10 MB.");
            }

            var extension = Path.GetExtension(image.FileName).ToLowerInvariant();
            var allowedExtensions = new HashSet<string> { ".jpg", ".jpeg", ".png", ".webp" };
            if (!allowedExtensions.Contains(extension) &&
                !image.ContentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
            {
                throw new UnsupportedMediaTypeException("Định dạng ảnh không được hỗ trợ. Vui lòng tải lên ảnh JPG, PNG hoặc WEBP.");
            }

            // Đọc dữ liệu ảnh sang byte[]
            byte[] imageBytes;
            using (var memoryStream = new MemoryStream())
            {
                await image.CopyToAsync(memoryStream, ct);
                imageBytes = memoryStream.ToArray();
            }

            // 3. Sinh scanId định dạng scn_ + 8 ký tự hex ngẫu nhiên
            var scanId = $"scn_{Guid.NewGuid():N}".Substring(0, 12);

            // 4. Chuẩn bị prompt Vision yêu cầu Gemini nhận diện
            var prompt = """
            Bạn là chuyên gia thị giác máy tính và dinh dưỡng thuần chay phân tích thực phẩm trong tủ lạnh, bếp hoặc bàn ăn.
            NHIỆM VỤ:
            1. Nhận diện các loại thực phẩm, rau củ quả, nguyên liệu, đồ uống nhìn thấy rõ trong ảnh. Không đoán mò những món nằm trong hộp kín không nhìn thấy.
            2. Trả về tên tiếng Việt phổ biến (label, ví dụ: 'Bông cải xanh', 'Cà chua', 'Đậu hũ', 'Trứng gà', 'Sữa tươi').
            3. Xác định món đó có phải là thuần chay hay không ('isVegan': true/false).
            4. Nếu không thuần chay ('isVegan': false):
               - Bắt buộc điền 'nonVeganReason' giải thích ngắn gọn bằng tiếng Việt lý do không thuần chay (ví dụ: 'Có nguồn gốc từ động vật: trứng gia cầm', 'Sản phẩm từ sữa bò').
               - Bắt buộc điền 'veganAlternatives' mảng 1 đến 2 phương án thay thế thuần chay tương đương (ví dụ: ['Đậu hũ non', 'Bột hạt lanh'] cho trứng).
            5. Nếu không chắc chắn 100%, bổ sung 1 đến 2 món thay thế gần giống vào mảng 'alternatives' kèm độ tự tin.
            6. Trả về tọa độ bounding box 'box_2d' dạng mảng 4 số nguyên [ymin, xmin, ymax, xmax] theo thang 0 đến 1000.
            
            Trả về DUY NHẤT một JSON hợp lệ tuân theo cấu trúc sau:
            {
              "items": [
                {
                  "label": "Bông cải xanh",
                  "confidence": 0.95,
                  "isVegan": true,
                  "nonVeganReason": null,
                  "veganAlternatives": [],
                  "box_2d": [180, 60, 400, 360],
                  "alternatives": [
                    { "label": "Súp lơ", "confidence": 0.05, "isVegan": true }
                  ]
                }
              ]
            }
            """;

            // Giới hạn thời gian gọi Gemini tối đa 25 giây (mobile timeout 30s)
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(25));

            GeminiVisionRawResponse rawResponse;
            try
            {
                rawResponse = await _geminiClient.GenerateJsonAsync<GeminiVisionRawResponse>(
                    prompt,
                    imageBytes,
                    image.ContentType,
                    taskType: "Vision",
                    userId: currentUserId,
                    scanId: scanId,
                    ct: timeoutCts.Token);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                _logger.LogWarning("Gemini Vision scan bị timeout sau 25s.");
                throw new DomainException("Hệ thống xử lý ảnh mất quá nhiều thời gian (timeout 25s). Vui lòng thử lại với ảnh rõ nét hơn.");
            }

            // 5. Nạp danh mục nguyên liệu và hồ sơ dị ứng để đối soát
            var ingredients = await _ingredientRepo.GetAllAsync();
            var userAllergies = new List<string>();

            if (!string.IsNullOrWhiteSpace(currentUserId))
            {
                var healthProfiles = await _healthProfileRepo.FindAsync(h => h.UserId == currentUserId);
                var healthProfile = healthProfiles.FirstOrDefault();
                if (healthProfile?.Allergies != null)
                {
                    userAllergies = healthProfile.Allergies;
                }
            }

            // 6. Xử lý chuẩn hóa kết quả
            var items = new List<DetectedIngredientDto>();
            int detIndex = 1;

            if (rawResponse?.Items != null)
            {
                foreach (var rawItem in rawResponse.Items)
                {
                    if (string.IsNullOrWhiteSpace(rawItem.Label)) continue;

                    var labelTrimmed = rawItem.Label.Trim();
                    bool? isVegan = rawItem.IsVegan;
                    var nonVeganReason = rawItem.NonVeganReason;
                    var veganAlternatives = rawItem.VeganAlternatives ?? new List<string>();

                    // Đối soát với danh mục nguyên liệu hệ thống
                    var normalized = AllergyMatcher.RemoveDiacritics(labelTrimmed).ToLowerInvariant().Trim();
                    var matchedCatalog = ingredients.FirstOrDefault(i =>
                        i.NormalizedName.Equals(normalized, StringComparison.OrdinalIgnoreCase) ||
                        i.Aliases.Any(a => AllergyMatcher.RemoveDiacritics(a).ToLowerInvariant().Trim().Equals(normalized, StringComparison.OrdinalIgnoreCase)));

                    if (matchedCatalog != null)
                    {
                        // Danh mục chuẩn luôn thắng Gemini
                        isVegan = matchedCatalog.IsVegan;
                    }

                    // Nếu không thuần chay, đảm bảo có lý do và gợi ý thay thế
                    if (isVegan == false)
                    {
                        if (string.IsNullOrWhiteSpace(nonVeganReason))
                        {
                            nonVeganReason = $"Món {labelTrimmed} có nguồn gốc từ động vật hoặc sản phẩm phụ từ động vật.";
                        }
                        if (veganAlternatives.Count == 0)
                        {
                            veganAlternatives = SuggestDefaultVeganAlternatives(labelTrimmed);
                        }
                    }

                    // Xử lý chuyển đổi bounding box [ymin, xmin, ymax, xmax] (thang 0..1000) sang (x, y, w, h trong 0..1)
                    BoundingBoxDto? bbox = null;
                    if (rawItem.Box_2d != null && rawItem.Box_2d.Length == 4)
                    {
                        var ymin = rawItem.Box_2d[0];
                        var xmin = rawItem.Box_2d[1];
                        var ymax = rawItem.Box_2d[2];
                        var xmax = rawItem.Box_2d[3];

                        if (xmax > xmin && ymax > ymin)
                        {
                            bbox = new BoundingBoxDto
                            {
                                X = Math.Clamp(Math.Round(xmin / 1000.0, 4), 0.0, 1.0),
                                Y = Math.Clamp(Math.Round(ymin / 1000.0, 4), 0.0, 1.0),
                                W = Math.Clamp(Math.Round((xmax - xmin) / 1000.0, 4), 0.0, 1.0),
                                H = Math.Clamp(Math.Round((ymax - ymin) / 1000.0, 4), 0.0, 1.0)
                            };
                        }
                    }

                    // Xử lý alternatives
                    var alternatives = rawItem.Alternatives ?? new List<IngredientAlternativeDto>();

                    items.Add(new DetectedIngredientDto
                    {
                        Id = $"det_{detIndex++}",
                        Label = labelTrimmed,
                        Confidence = Math.Clamp(rawItem.Confidence > 0 ? rawItem.Confidence : 0.90, 0.0, 1.0),
                        IsVegan = isVegan,
                        NonVeganReason = nonVeganReason,
                        VeganAlternatives = veganAlternatives,
                        Bbox = bbox,
                        Alternatives = alternatives
                    });
                }
            }

            return new ScanResultDto
            {
                ScanId = scanId,
                Items = items
            };
        }

        private static void CheckRateLimit(string key)
        {
            var now = DateTime.UtcNow;
            var windowStart = now.AddMinutes(-1);

            UserRateLimitTracker.AddOrUpdate(
                key,
                _ => new List<DateTime> { now },
                (_, timestamps) =>
                {
                    lock (timestamps)
                    {
                        timestamps.RemoveAll(t => t < windowStart);
                        if (timestamps.Count >= MaxCallsPerMinute)
                        {
                            throw new TooManyRequestsException("Quá giới hạn quét tủ lạnh (tối đa 10 lần/phút). Vui lòng thử lại sau ít phút.");
                        }
                        timestamps.Add(now);
                        return timestamps;
                    }
                });
        }

        private static List<string> SuggestDefaultVeganAlternatives(string nonVeganLabel)
        {
            var normalized = AllergyMatcher.RemoveDiacritics(nonVeganLabel).ToLowerInvariant();
            if (normalized.Contains("trung"))
            {
                return new List<string> { "Đậu hũ non", "Bột hạt lanh (pha nước)" };
            }
            if (normalized.Contains("sua") || normalized.Contains("bo") || normalized.Contains("pho mai"))
            {
                return new List<string> { "Sữa đậu nành", "Sữa yến mạch", "Phô mai hạt điều" };
            }
            if (normalized.Contains("thit") || normalized.Contains("ga") || normalized.Contains("heo") || normalized.Contains("bo"))
            {
                return new List<string> { "Nấm đùi gà", "Đậu hũ chiên", "Mì căn (Seitan)" };
            }
            if (normalized.Contains("ca") || normalized.Contains("tom") || normalized.Contains("muc") || normalized.Contains("hai san"))
            {
                return new List<string> { "Rong biển cuộn đậu hũ", "Nấm bào ngư" };
            }

            return new List<string> { "Đậu hũ non", "Nấm tươi" };
        }
    }
}

