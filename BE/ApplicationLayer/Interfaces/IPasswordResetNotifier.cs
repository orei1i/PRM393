using System.Collections.Concurrent;
using System.Threading.Tasks;

namespace ApplicationLayer.Interfaces
{
    /// <summary>Nơi mã đặt lại mật khẩu được gửi đi. Khi có dịch vụ email thật thì thay ở đây.</summary>
    public interface IPasswordResetNotifier
    {
        /// <summary>false: chưa có kênh gửi nào, người dùng sẽ không nhận được mã.</summary>
        bool CanDeliver { get; }

        Task SendAsync(string email, string code);
    }

    /// <summary>Chưa cấu hình gửi email: không gửi và không ghi mã ra log.</summary>
    public sealed class NoPasswordResetNotifier : IPasswordResetNotifier
    {
        public bool CanDeliver => false;

        public Task SendAsync(string email, string code) => Task.CompletedTask;
    }

    /// <summary>
    /// Chỉ dùng khi phát triển (Development và Auth:DevResetCodes = true): giữ mã trong bộ nhớ để lấy qua
    /// GET /api/v1/dev/auth/reset-code. Môi trường khác không bao giờ dùng lớp này, xem Program.cs.
    /// </summary>
    public sealed class DevResetCodeOutbox : IPasswordResetNotifier
    {
        private readonly ConcurrentDictionary<string, string> _codes = new();

        public bool CanDeliver => true;

        public Task SendAsync(string email, string code)
        {
            _codes[email] = code;
            return Task.CompletedTask;
        }

        public string? Peek(string email) => _codes.TryGetValue(email, out var code) ? code : null;
    }
}
