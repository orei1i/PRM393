using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using ApplicationLayer.DTOs.Auth;
using UserResponse = ApplicationLayer.DTOs.Users.UserResponse;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Enums;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace ApplicationLayer.Services
{
    /// <summary>
    /// Xử lý authentication: login, register, forgot/verify/reset-password.
    /// Rate limiting và reset codes lưu in-memory (đủ cho MVP).
    /// Production: chuyển sang Redis (package StackExchange.Redis đã cài sẵn).
    /// </summary>
    public class AuthService : IAuthService
    {
        private readonly IGenericRepository<User> _userRepo;
        private readonly IConfiguration _config;

        // ─── In-memory rate limiter: email → (failCount, lockUntil) ──────────
        private static readonly ConcurrentDictionary<string, (int Count, DateTime? LockUntil)> _failAttempts = new();
        private const int MaxFailAttempts = 5;
        private static readonly TimeSpan LockDuration = TimeSpan.FromMinutes(5);

        // ─── In-memory reset codes: email → (code, expiresAt, usedResetToken) ─
        private static readonly ConcurrentDictionary<string, (string Code, DateTime ExpiresAt, string? ResetToken)> _resetCodes = new();
        private static readonly TimeSpan CodeTtl = TimeSpan.FromMinutes(10);

        public AuthService(IGenericRepository<User> userRepo, IConfiguration config)
        {
            _userRepo = userRepo;
            _config   = config;
        }

        // ─────────────────────────────────────────────────────────────────────
        // LOGIN
        // ─────────────────────────────────────────────────────────────────────
        public async Task<AuthResponse> LoginAsync(LoginRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            // Rate limit check
            if (_failAttempts.TryGetValue(email, out var attempt) && attempt.LockUntil.HasValue)
            {
                if (DateTime.UtcNow < attempt.LockUntil.Value)
                    throw new TooManyRequestsException();
                // Lock expired — reset
                _failAttempts.TryRemove(email, out _);
            }

            var user = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

            // Kiểm tra credentials
            if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                RecordFailedAttempt(email);
                throw new UnauthorizedException("Email hoặc mật khẩu không đúng.");
            }

            // Admin không được login qua Mobile
            if (user.Role == "Admin")
                throw new ForbiddenException("Tài khoản quản trị chỉ dùng trên web quản trị.");

            // Kiểm tra status
            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException();

            // Đăng nhập thành công — xóa fail attempts
            _failAttempts.TryRemove(email, out _);

            return BuildAuthResponse(user);
        }

        // ─────────────────────────────────────────────────────────────────────
        // REGISTER
        // ─────────────────────────────────────────────────────────────────────
        public async Task<AuthResponse> RegisterAsync(RegisterRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            var existing = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);
            if (existing != null)
                throw new ConflictException("Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.");

            var user = new User
            {
                Email        = request.Email.Trim(),
                FullName     = request.FullName.Trim(),
                Phone        = request.Phone?.Trim() ?? string.Empty,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
                Role         = "User",
                Status       = GeneralEnum.UserStatusEnum.Active,
                AuthType     = GeneralEnum.AuthTypeEnum.System,
                CreatedAt    = DateTime.UtcNow,
                UpdatedAt    = DateTime.UtcNow
            };

            await _userRepo.CreateAsync(user);
            return BuildAuthResponse(user);
        }

        // ─────────────────────────────────────────────────────────────────────
        // FORGOT PASSWORD — luôn trả 204 (không tiết lộ email tồn tại)
        // ─────────────────────────────────────────────────────────────────────
        public async Task ForgotPasswordAsync(ForgotPasswordRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();
            var user  = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

            if (user != null)
            {
                // Tạo mã 6 số ngẫu nhiên
                var code    = Random.Shared.Next(100000, 999999).ToString();
                var expires = DateTime.UtcNow.Add(CodeTtl);
                _resetCodes[email] = (code, expires, null);

                // TODO: gửi email thật qua IEmailService (MailKit — out of scope, package đã cài)
                // Hiện tại: log ra console cho dev test
                Console.WriteLine($"[DEV] Reset code for {email}: {code}");
            }
            // Nếu user không tồn tại → vẫn trả về bình thường (không lộ thông tin)
            await Task.CompletedTask;
        }

        // ─────────────────────────────────────────────────────────────────────
        // VERIFY RESET CODE
        // ─────────────────────────────────────────────────────────────────────
        public async Task<VerifyResetCodeResponse> VerifyResetCodeAsync(VerifyResetCodeRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            if (!_resetCodes.TryGetValue(email, out var entry))
                throw new ArgumentException("invalid_code");

            if (DateTime.UtcNow > entry.ExpiresAt)
            {
                _resetCodes.TryRemove(email, out _);
                throw new ArgumentException("code_expired");
            }

            if (entry.Code != request.Code)
                throw new ArgumentException("invalid_code");

            // Tạo một-lần-dùng resetToken
            var resetToken = Guid.NewGuid().ToString("N");
            _resetCodes[email] = (entry.Code, entry.ExpiresAt, resetToken);

            return await Task.FromResult(new VerifyResetCodeResponse { ResetToken = resetToken });
        }

        // ─────────────────────────────────────────────────────────────────────
        // RESET PASSWORD
        // ─────────────────────────────────────────────────────────────────────
        public async Task ResetPasswordAsync(ResetPasswordRequest request)
        {
            // Tìm entry có resetToken khớp
            var entry = _resetCodes.FirstOrDefault(kv => kv.Value.ResetToken == request.ResetToken);
            if (entry.Key == null)
                throw new ArgumentException("invalid_code");

            if (DateTime.UtcNow > entry.Value.ExpiresAt)
            {
                _resetCodes.TryRemove(entry.Key, out _);
                throw new ArgumentException("code_expired");
            }

            var email = entry.Key;
            var user  = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted)
                        ?? throw new DomainException("Không tìm thấy tài khoản.");

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            user.UpdatedAt    = DateTime.UtcNow;
            await _userRepo.UpdateAsync(user.Id, user);

            _resetCodes.TryRemove(email, out _);
        }

        // ─────────────────────────────────────────────────────────────────────
        // PRIVATE HELPERS
        // ─────────────────────────────────────────────────────────────────────
        private AuthResponse BuildAuthResponse(User user)
        {
            var (token, expiresAt) = GenerateJwtToken(user);
            return new AuthResponse
            {
                AccessToken = token,
                ExpiresAt   = expiresAt,
                User        = MapToUserResponse(user)
            };
        }

        private (string Token, DateTime ExpiresAt) GenerateJwtToken(User user)
        {
            var jwt    = _config.GetSection("JwtSettings");
            var key    = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["SecretKey"]!));
            var creds  = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
            var expiry = int.TryParse(jwt["ExpiryMinutes"], out var m) ? m : 60;

            var claims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Sub,   user.Id),
                new Claim(JwtRegisteredClaimNames.Email, user.Email),
                new Claim(ClaimTypes.Name,               user.FullName),
                new Claim(ClaimTypes.Role,               user.Role),
                new Claim(JwtRegisteredClaimNames.Jti,   Guid.NewGuid().ToString())
            };

            var expiresAt = DateTime.UtcNow.AddMinutes(expiry);
            var tokenObj  = new JwtSecurityToken(
                issuer:             jwt["Issuer"],
                audience:           jwt["Audience"],
                claims:             claims,
                expires:            expiresAt,
                signingCredentials: creds
            );

            return (new JwtSecurityTokenHandler().WriteToken(tokenObj), expiresAt);
        }

        private static UserResponse MapToUserResponse(User user) => new()
        {
            Id        = user.Id,
            Email     = user.Email,
            FullName  = user.FullName,
            Phone     = user.Phone,
            Role      = user.Role,
            Status    = user.Status,
            AuthType  = user.AuthType,
            CreatedAt = user.CreatedAt
        };

        private static void RecordFailedAttempt(string email)
        {
            _failAttempts.AddOrUpdate(
                email,
                _ => (1, null),
                (_, old) =>
                {
                    var count = old.Count + 1;
                    var lockUntil = count >= MaxFailAttempts ? (DateTime?)DateTime.UtcNow.Add(LockDuration) : null;
                    return (count, lockUntil);
                });
        }
    }
}
