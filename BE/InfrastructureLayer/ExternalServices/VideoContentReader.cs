using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;

namespace InfrastructureLayer.ExternalServices
{
    /// <summary>
    /// Đọc video đã tải lên. Đầu vào luôn là URL lấy từ MediaAssets do chính máy chủ ghi, không phải chuỗi của client.
    /// </summary>
    public class VideoContentReader : IVideoContentReader
    {
        private readonly HttpClient _http;

        public VideoContentReader(HttpClient http)
        {
            _http = http;
            _http.Timeout = TimeSpan.FromSeconds(60);
        }

        public async Task<(byte[] Bytes, string MimeType)> ReadAsync(string url, long maxBytes, CancellationToken ct = default)
        {
            if (url.StartsWith("/uploads/videos/", StringComparison.Ordinal))
            {
                // Chỉ lấy tên tệp: chuỗi có ".." không ra khỏi được thư mục video.
                var path = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "uploads", "videos", Path.GetFileName(url));
                if (!File.Exists(path)) throw new NotFoundException("Không tìm thấy tệp video.");
                if (new FileInfo(path).Length > maxBytes) throw new PayloadTooLargeException("Video quá lớn để trích xuất tự động.");
                return (await File.ReadAllBytesAsync(path, ct), MimeOf(path));
            }

            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
                throw new BadRequestException("Nguồn video không hợp lệ.");

            using var response = await _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > maxBytes) throw new PayloadTooLargeException("Video quá lớn để trích xuất tự động.");

            await using var body = await response.Content.ReadAsStreamAsync(ct);
            await using var buffer = new MemoryStream();
            var chunk = new byte[81920];
            int read;
            while ((read = await body.ReadAsync(chunk, ct)) > 0)
            {
                if (buffer.Length + read > maxBytes) throw new PayloadTooLargeException("Video quá lớn để trích xuất tự động.");
                await buffer.WriteAsync(chunk.AsMemory(0, read), ct);
            }
            return (buffer.ToArray(), response.Content.Headers.ContentType?.MediaType ?? MimeOf(uri.AbsolutePath));
        }

        private static string MimeOf(string path) => Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".mov" => "video/quicktime",
            ".webm" => "video/webm",
            _ => "video/mp4"
        };
    }
}
