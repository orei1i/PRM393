using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace InfrastructureLayer.ExternalServices
{
    /// <summary>
    /// Gọi Nominatim (hoặc máy chủ tương thích) qua Geo:BaseUrl. Không có Geo:BaseUrl thì không gọi ra ngoài.
    /// Nominatim công khai yêu cầu User-Agent nhận diện được và tối đa 1 yêu cầu/giây, nên route có giới hạn và cache.
    /// </summary>
    public class NominatimGeocodingClient : IGeocodingClient
    {
        public const string NotConfiguredMessage = "Dịch vụ định vị địa chỉ chưa được cấu hình trên máy chủ. Bạn có thể nhập địa chỉ thủ công.";
        private const string UpstreamFailedMessage = "Dịch vụ định vị địa chỉ tạm thời không phản hồi. Thử lại sau ít phút.";

        private readonly HttpClient _http;
        private readonly ILogger<NominatimGeocodingClient> _logger;
        private readonly string? _baseUrl;
        private readonly string _countryCodes;

        public NominatimGeocodingClient(HttpClient http, IConfiguration configuration, ILogger<NominatimGeocodingClient> logger)
        {
            _http = http;
            _logger = logger;
            var raw = configuration["Geo:BaseUrl"]?.Trim().TrimEnd('/');
            _baseUrl = Uri.TryCreate(raw, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" ? raw : null;
            _countryCodes = configuration["Geo:CountryCodes"] ?? "vn";
            _http.Timeout = TimeSpan.FromSeconds(8);
            _http.DefaultRequestHeaders.UserAgent.ParseAdd(configuration["Geo:UserAgent"] ?? "VeganLife-Backend/1.0");
            _http.DefaultRequestHeaders.AcceptLanguage.Add(new StringWithQualityHeaderValue("vi"));
        }

        public bool IsConfigured => _baseUrl != null;

        public async Task<List<GeoPlaceResult>> SearchAsync(string query, CancellationToken ct = default)
        {
            var url = $"{RequireBase()}/search?format=jsonv2&addressdetails=1&limit=8&countrycodes={Uri.EscapeDataString(_countryCodes)}&q={Uri.EscapeDataString(query)}";
            using var doc = await GetAsync(url, ct);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return new List<GeoPlaceResult>();
            return doc.RootElement.EnumerateArray().Select(Parse).Where(p => p != null).Select(p => p!).ToList();
        }

        public async Task<GeoPlaceResult?> ReverseAsync(double latitude, double longitude, CancellationToken ct = default)
        {
            var url = $"{RequireBase()}/reverse?format=jsonv2&addressdetails=1&lat={latitude.ToString(CultureInfo.InvariantCulture)}&lon={longitude.ToString(CultureInfo.InvariantCulture)}";
            using var doc = await GetAsync(url, ct);
            return doc.RootElement.ValueKind == JsonValueKind.Object ? Parse(doc.RootElement) : null;
        }

        private string RequireBase() =>
            _baseUrl ?? throw new ServiceUnavailableException(NotConfiguredMessage, "geo_unavailable");

        private async Task<JsonDocument> GetAsync(string url, CancellationToken ct)
        {
            try
            {
                using var response = await _http.GetAsync(url, ct);
                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogWarning("Dịch vụ định vị trả mã {Status}.", (int)response.StatusCode);
                    throw new ServiceUnavailableException(UpstreamFailedMessage, "geo_unavailable");
                }
                await using var body = await response.Content.ReadAsStreamAsync(ct);
                return await JsonDocument.ParseAsync(body, cancellationToken: ct);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException && !ct.IsCancellationRequested)
            {
                _logger.LogWarning("Không gọi được dịch vụ định vị ({ErrorType}).", ex.GetType().Name);
                throw new ServiceUnavailableException(UpstreamFailedMessage, "geo_unavailable");
            }
        }

        /// <summary>Thiếu toạ độ thì bỏ cả dòng: app coi 0,0 là vị trí thật.</summary>
        private static GeoPlaceResult? Parse(JsonElement row)
        {
            if (!TryDouble(row, "lat", out var lat) || !TryDouble(row, "lon", out var lon)) return null;
            var display = row.TryGetProperty("display_name", out var d) && d.ValueKind == JsonValueKind.String ? d.GetString() ?? string.Empty : string.Empty;
            if (display.Length == 0) return null;

            var name = row.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : null;
            if (string.IsNullOrWhiteSpace(name)) name = display.Split(',')[0].Trim();

            string? city = null;
            if (row.TryGetProperty("address", out var address) && address.ValueKind == JsonValueKind.Object)
            {
                foreach (var key in new[] { "city", "town", "municipality", "province", "state" })
                {
                    if (address.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
                    {
                        city = value.GetString();
                        break;
                    }
                }
            }
            return new GeoPlaceResult(name!, display, city, lat, lon);
        }

        private static bool TryDouble(JsonElement row, string name, out double value)
        {
            value = 0;
            return row.TryGetProperty(name, out var raw)
                   && raw.ValueKind == JsonValueKind.String
                   && double.TryParse(raw.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out value);
        }
    }
}
