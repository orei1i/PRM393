using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Media;
using ApplicationLayer.Interfaces;
using CloudinaryDotNet;
using CloudinaryDotNet.Actions;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace ApplicationLayer.Services
{
    public class MediaService : IMediaService
    {
        private readonly Cloudinary _cloudinary;
        private readonly IGenericRepository<MediaAsset> _mediaAssetRepo;
        private readonly ILogger<MediaService> _logger;

        private const long MaxImageBytes = 10 * 1024 * 1024;    // 10 MB
        private const long MaxVideoBytes = 100 * 1024 * 1024;  // 100 MB (Cloudinary Free limit)

        private static readonly string[] AllowedImageExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".heic" };
        private static readonly string[] AllowedVideoExtensions = { ".mp4", ".mov", ".webm" };

        public MediaService(
            Cloudinary cloudinary,
            IGenericRepository<MediaAsset> mediaAssetRepo,
            ILogger<MediaService> logger)
        {
            _cloudinary = cloudinary;
            _mediaAssetRepo = mediaAssetRepo;
            _logger = logger;
        }

        public async Task<UploadedImageResponse> UploadImageAsync(IFormFile file, string userId)
        {
            if (file == null || file.Length == 0)
            {
                throw new BadRequestException("Tệp tải lên không được để trống.");
            }

            if (file.Length > MaxImageBytes)
            {
                throw new PayloadTooLargeException("Ảnh vượt quá dung lượng tối đa 10 MB.");
            }

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!AllowedImageExtensions.Contains(ext))
            {
                throw new UnsupportedMediaTypeException("Định dạng ảnh không được hỗ trợ. Chỉ chấp nhận JPG, PNG, WEBP, HEIC.");
            }

            await using var stream = file.OpenReadStream();
            if (!IsValidImageHeader(stream, ext))
            {
                throw new UnsupportedMediaTypeException("Tệp hình ảnh không hợp lệ hoặc đã bị đổi phần mở rộng.");
            }
            stream.Position = 0;

            string finalUrl;
            int? width = null;
            int? height = null;
            long sizeBytes = file.Length;
            string publicId = $"{Guid.NewGuid():N}";

            if (IsDummyCloudinary())
            {
                var uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "uploads", "images");
                Directory.CreateDirectory(uploadsFolder);
                var fileName = $"{publicId}{ext}";
                var filePath = Path.Combine(uploadsFolder, fileName);
                await using (var fs = new FileStream(filePath, FileMode.Create))
                {
                    await stream.CopyToAsync(fs);
                }
                finalUrl = $"/uploads/images/{fileName}";
                width = 800;
                height = 600;
                _logger.LogInformation("[DEV] Cloudinary key chưa cấu hình thật, đã lưu ảnh tại cục bộ: {Url}", finalUrl);
            }
            else
            {
                var uploadParams = new ImageUploadParams
                {
                    File = new FileDescription(file.FileName, stream),
                    Folder = "veganlife/images",
                    PublicId = publicId,
                    Format = ext == ".heic" ? "jpg" : null
                };

                ImageUploadResult result;
                try
                {
                    result = await _cloudinary.UploadAsync(uploadParams);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Lỗi kết nối khi upload ảnh lên Cloudinary");
                    throw new ServerFailureException("Không thể tải ảnh lên dịch vụ lưu trữ. Vui lòng thử lại sau.");
                }

                if (result.Error != null)
                {
                    _logger.LogError("Cloudinary upload image error: {Error}", result.Error.Message);
                    throw new ServerFailureException($"Lỗi lưu trữ hình ảnh: {result.Error.Message}");
                }

                finalUrl = result.SecureUrl?.ToString() ?? result.Url?.ToString() ?? string.Empty;
                width = result.Width;
                height = result.Height;
                sizeBytes = result.Bytes > 0 ? result.Bytes : file.Length;
                publicId = result.PublicId;
            }

            var asset = new MediaAsset
            {
                OwnerId = userId,
                PublicId = publicId,
                Url = finalUrl,
                MediaType = "Image",
                SizeBytes = sizeBytes,
                Width = width,
                Height = height,
                CreatedAt = DateTime.UtcNow
            };

            await _mediaAssetRepo.CreateAsync(asset);

            return new UploadedImageResponse
            {
                MediaUrl = asset.Url,
                SizeBytes = asset.SizeBytes,
                Width = asset.Width,
                Height = asset.Height
            };
        }

        public async Task<UploadedVideoResponse> UploadVideoAsync(IFormFile file, string userId)
        {
            if (file == null || file.Length == 0)
            {
                throw new BadRequestException("Tệp video không được để trống.");
            }

            if (file.Length > MaxVideoBytes)
            {
                throw new PayloadTooLargeException("Video vượt quá dung lượng tối đa 100 MB.");
            }

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!AllowedVideoExtensions.Contains(ext))
            {
                throw new UnsupportedMediaTypeException("Định dạng video không được hỗ trợ. Chỉ chấp nhận MP4, MOV, WEBM.");
            }

            await using var stream = file.OpenReadStream();
            if (!IsValidVideoHeader(stream, ext))
            {
                throw new UnsupportedMediaTypeException("Tệp video không hợp lệ hoặc đã bị đổi phần mở rộng.");
            }
            stream.Position = 0;

            string finalUrl;
            int? duration = null;
            long sizeBytes = file.Length;
            string publicId = $"{Guid.NewGuid():N}";

            if (IsDummyCloudinary())
            {
                var uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "uploads", "videos");
                Directory.CreateDirectory(uploadsFolder);
                var fileName = $"{publicId}{ext}";
                var filePath = Path.Combine(uploadsFolder, fileName);
                await using (var fs = new FileStream(filePath, FileMode.Create))
                {
                    await stream.CopyToAsync(fs);
                }
                finalUrl = $"/uploads/videos/{fileName}";
                _logger.LogInformation("[DEV] Cloudinary key chưa cấu hình thật, đã lưu video tại cục bộ: {Url}", finalUrl);
            }
            else
            {
                var uploadParams = new VideoUploadParams
                {
                    File = new FileDescription(file.FileName, stream),
                    Folder = "veganlife/videos",
                    PublicId = publicId
                };

                VideoUploadResult result;
                try
                {
                    // Dùng UploadLargeAsync hỗ trợ chunked upload cho video lớn
                    result = await _cloudinary.UploadLargeAsync<VideoUploadResult>(uploadParams, bufferSize: 20 * 1024 * 1024, cancellationToken: System.Threading.CancellationToken.None);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Lỗi kết nối khi upload video lên Cloudinary");
                    throw new ServerFailureException("Không thể tải video lên dịch vụ lưu trữ. Vui lòng kiểm tra lại cấu hình Cloudinary.");
                }

                if (result.Error != null)
                {
                    _logger.LogError("Cloudinary upload video error: {Error}", result.Error.Message);
                    throw new ServerFailureException($"Lỗi lưu trữ video: {result.Error.Message}");
                }

                finalUrl = result.SecureUrl?.ToString() ?? result.Url?.ToString() ?? string.Empty;
                duration = (int)Math.Round(result.Duration);
                sizeBytes = result.Bytes > 0 ? result.Bytes : file.Length;
                publicId = result.PublicId;
            }

            var asset = new MediaAsset
            {
                OwnerId = userId,
                PublicId = publicId,
                Url = finalUrl,
                MediaType = "Video",
                SizeBytes = sizeBytes,
                DurationSeconds = duration,
                CreatedAt = DateTime.UtcNow
            };

            await _mediaAssetRepo.CreateAsync(asset);

            return new UploadedVideoResponse
            {
                MediaUrl = asset.Url,
                DurationSeconds = asset.DurationSeconds,
                SizeBytes = asset.SizeBytes
            };
        }

        private bool IsDummyCloudinary()
        {
            var cloud = _cloudinary?.Api?.Account?.Cloud;
            return string.IsNullOrWhiteSpace(cloud) ||
                   string.Equals(cloud, "dummy_cloud_name", StringComparison.OrdinalIgnoreCase);
        }

        public async Task<bool> ValidateOwnerAsync(string mediaUrl, string userId)
        {
            if (string.IsNullOrWhiteSpace(mediaUrl)) return false;
            var asset = await _mediaAssetRepo.FirstOrDefaultAsync(x => x.Url == mediaUrl && x.OwnerId == userId && !x.IsDeleted);
            return asset != null;
        }

        private static bool IsValidImageHeader(Stream stream, string ext)
        {
            var header = new byte[12];
            var read = stream.Read(header, 0, header.Length);
            if (read < 4) return false;

            return ext switch
            {
                ".jpg" or ".jpeg" => header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF,
                ".png" => header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47,
                ".webp" => read >= 12 && header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
                                      && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50,
                ".heic" => read >= 12 && header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70, // ftyp
                _ => false
            };
        }

        private static bool IsValidVideoHeader(Stream stream, string ext)
        {
            var header = new byte[12];
            var read = stream.Read(header, 0, header.Length);
            if (read < 4) return false;

            return ext switch
            {
                ".mp4" or ".mov" => read >= 8 && header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70, // ftyp
                ".webm" => header[0] == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3, // EBML ID
                _ => false
            };
        }
    }
}
