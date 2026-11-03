using System;
using System.Globalization;
using System.Threading.Tasks;
using ApplicationLayer.Interfaces;
using DomainLayer.Constants;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MongoDB.Bson;

namespace ApplicationLayer.Services
{
    public class SystemClock : IClock
    {
        // Mongo lưu đến mili giây: cắt sẵn để giá trị trong bộ nhớ và giá trị đọc lại luôn bằng nhau.
        public DateTime UtcNow
        {
            get
            {
                var now = DateTime.UtcNow;
                return new DateTime(now.Ticks - now.Ticks % TimeSpan.TicksPerMillisecond, DateTimeKind.Utc);
            }
        }
    }

    public class NoCommerceFailpoints : ICommerceFailpoints
    {
        public void Hit(string name)
        {
        }
    }

    /// <summary>
    /// CỔNG THỬ NGHIỆM: không có tiền thật đi qua và không gọi ra ngoài. Chỉ bật khi Payment:Provider=Sandbox và
    /// không phải môi trường Production. Xác nhận trả tiền qua route sandbox-confirm dành cho Admin.
    /// </summary>
    public class SandboxPaymentProvider : IPaymentProvider
    {
        public bool IsConfigured => true;
        public string Name => PaymentProviderNames.Sandbox;

        public Task<PaymentSession> OpenAsync(string orderId, long amount, DateTime expiresAt)
        {
            var reference = $"SBX{VnTime.DateOf(expiresAt).Replace("-", string.Empty).Substring(2)}{CommerceText.RefSuffix()}";
            // Không có ảnh QR thật: app tự vẽ mã giả từ transactionRef khi qrCodeUrl là null.
            return Task.FromResult(new PaymentSession(reference, null));
        }
    }

    /// <summary>Chưa cấu hình cổng nào: route thanh toán báo 503, thanh toán bằng ví vẫn dùng được.</summary>
    public class UnconfiguredPaymentProvider : IPaymentProvider
    {
        public bool IsConfigured => false;
        public string Name => "None";

        public Task<PaymentSession> OpenAsync(string orderId, long amount, DateTime expiresAt) =>
            throw new ServiceUnavailableException(CommerceMessages.NoPaymentProvider, "payment_unavailable");
    }

    public static class PaymentProviderFactory
    {
        public static IPaymentProvider Create(IConfiguration configuration, IHostEnvironment environment, ILogger logger)
        {
            var name = configuration["Payment:Provider"];
            if (string.IsNullOrWhiteSpace(name)) return new UnconfiguredPaymentProvider();

            if (name.Equals(PaymentProviderNames.Sandbox, StringComparison.OrdinalIgnoreCase))
            {
                if (environment.IsProduction())
                {
                    logger.LogError("Payment:Provider=Sandbox bị bỏ qua trên Production: cổng thử nghiệm không được chạy với người dùng thật.");
                    return new UnconfiguredPaymentProvider();
                }
                logger.LogWarning("Đang dùng cổng thanh toán THỬ NGHIỆM: không có tiền thật đi qua.");
                return new SandboxPaymentProvider();
            }

            logger.LogWarning("Payment:Provider không được hỗ trợ, coi như chưa cấu hình cổng thanh toán.");
            return new UnconfiguredPaymentProvider();
        }
    }

    public static class CommerceMessages
    {
        public const string NoPaymentProvider = "Cổng thanh toán chưa được cấu hình nên chưa tạo được mã QR. Bạn có thể thanh toán bằng ví VeganLife nếu đủ số dư.";
        public const string BookingNotFound = "Không tìm thấy yêu cầu đặt chuyên gia.";
        public const string OrderNotFound = "Không tìm thấy đơn hàng.";
        public const string PaymentNotFound = "Không tìm thấy giao dịch.";
    }

    public static class CommerceText
    {
        /// <summary>"Nguyễn Đức" → "nguyen duc": tìm kiếm không phân biệt dấu.</summary>
        public static string Fold(string? text) =>
            AllergyMatcher.RemoveDiacritics(text ?? string.Empty).Replace('Đ', 'D').Replace('đ', 'd').ToLower(CultureInfo.InvariantCulture);

        public static string MaskAccount(string number) => number.Length <= 4 ? number : $"•••• {number[^4..]}";

        public static bool IsHttpUrl(string? value) =>
            Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);

        /// <summary>Ảnh do chính máy chủ lưu có thể là đường dẫn tương đối.</summary>
        public static bool IsMediaUrl(string? value) => IsHttpUrl(value) || (value?.Trim().StartsWith("/uploads/", StringComparison.Ordinal) ?? false);

        /// <summary>6 chữ số lấy từ bộ đếm của ObjectId: không trùng trong thực tế, không cần thêm bảng đếm.</summary>
        public static string RefSuffix() => (System.Convert.ToInt64(ObjectId.GenerateNewId().ToString()[18..], 16) % 1_000_000).ToString("D6");

        public static string NewTransactionRef(DateTime utc) =>
            $"VL{VnTime.DateOf(utc).Replace("-", string.Empty).Substring(2)}{CommerceText.RefSuffix()}";
    }
}
