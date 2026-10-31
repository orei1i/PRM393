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
    /// Xá»­ lÃ½ authentication: login, register, forgot/verify/reset-password.
    /// Rate limiting vÃ  reset codes lÆ°u in-memory (Ä‘á»§ cho MVP).
    /// Production: chuyá»ƒn sang Redis (package StackExchange.Redis Ä‘Ã£ cÃ i sáºµn).
    /// </summary>
    public class AuthService : IAuthService
    {
        private readonly IGenericRepository<User> _userRepo;
        private readonly IConfiguration _config;

        // â”€â”€â”€ In-memory rate limiter: email â†’ (failCount, lockUntil) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        private static readonly ConcurrentDictionary<string, (int Count, DateTime? LockUntil)> _failAttempts = new();
        private const int MaxFailAttempts = 5;
        private static readonly TimeSpan LockDuration = TimeSpan.FromMinutes(5);

        // â”€â”€â”€ In-memory reset codes: email â†’ (code, expiresAt, usedResetToken) â”€
        private static readonly ConcurrentDictionary<string, (string Code, DateTime ExpiresAt, string? ResetToken)> _resetCodes = new();
        private static readonly ConcurrentDictionary<string, int> _resetCodeAttempts = new();
        private static readonly TimeSpan CodeTtl = TimeSpan.FromMinutes(10);

        public AuthService(IGenericRepository<User> userRepo, IConfiguration config)
        {
            _userRepo = userRepo;
            _config   = config;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // LOGIN
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        public async Task<AuthResponse> LoginAsync(LoginRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            // Rate limit check
            if (_failAttempts.TryGetValue(email, out var attempt) && attempt.LockUntil.HasValue)
            {
                if (DateTime.UtcNow < attempt.LockUntil.Value)
                    throw new TooManyRequestsException();
                // Lock expired â€” reset
                _failAttempts.TryRemove(email, out _);
            }

            var user = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

            // Kiá»ƒm tra credentials
            if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                RecordFailedAttempt(email);
                throw new UnauthorizedException("Email hoáº·c máº­t kháº©u khÃ´ng Ä‘Ãºng.");
            }

            // Admin khÃ´ng Ä‘Æ°á»£c login qua Mobile
            if (user.Role == "Admin")
                throw new ForbiddenException("TÃ i khoáº£n quáº£n trá»‹ chá»‰ dÃ¹ng trÃªn web quáº£n trá»‹.");

            // Kiá»ƒm tra status
            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException();

            // ÄÄƒng nháº­p thÃ nh cÃ´ng â€” xÃ³a fail attempts
            _failAttempts.TryRemove(email, out _);

            return await GenerateAuthResponseWithRefreshTokenAsync(user);
        }

        // ─────────────────────────────────────────────────────────────────────
        // ADMIN LOGIN
        // ─────────────────────────────────────────────────────────────────────
        public async Task<AuthResponse> AdminLoginAsync(LoginRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            if (_failAttempts.TryGetValue(email, out var attempt) && attempt.LockUntil.HasValue)
            {
                if (DateTime.UtcNow < attempt.LockUntil.Value)
                    throw new TooManyRequestsException();
                _failAttempts.TryRemove(email, out _);
            }

            var user = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

            if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                RecordFailedAttempt(email);
                throw new UnauthorizedException("Email hoặc mật khẩu không đúng.");
            }

            if (user.Role != "Admin")
                throw new ForbiddenException("Chỉ tài khoản Quản trị viên mới được đăng nhập vào hệ thống quản trị.");

            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException();

            _failAttempts.TryRemove(email, out _);

            return await GenerateAuthResponseWithRefreshTokenAsync(user);
        }

        // ─────────────────────────────────────────────────────────────────────
        // REFRESH TOKEN
        // ─────────────────────────────────────────────────────────────────────
        public async Task<AuthResponse> RefreshTokenAsync(RefreshTokenRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.RefreshToken))
                throw new UnauthorizedException("Refresh token không được để trống.");

            var tokenHash = HashToken(request.RefreshToken);
            var user = await _userRepo.FirstOrDefaultAsync(u => u.RefreshTokenHash == tokenHash && !u.IsDeleted);

            if (user == null)
                throw new UnauthorizedException("Refresh token không hợp lệ hoặc đã bị thu hồi.");

            if (!user.RefreshTokenExpiresAt.HasValue || user.RefreshTokenExpiresAt.Value < DateTime.UtcNow)
                throw new UnauthorizedException("Refresh token đã hết hạn.");

            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException();

            // Xoay vòng token
            return await GenerateAuthResponseWithRefreshTokenAsync(user);
        }

        // ─────────────────────────────────────────────────────────────────────
        // LOGOUT
        // ─────────────────────────────────────────────────────────────────────
        public async Task LogoutAsync(string userId)
        {
            var user = await _userRepo.FindByIdAsync(userId);
            if (user != null)
            {
                user.RefreshTokenHash = null;
                user.RefreshTokenExpiresAt = null;
                await _userRepo.UpdateAsync(user.Id, user);
            }
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // REGISTER
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        public async Task<AuthResponse> RegisterAsync(RegisterRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            var existing = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);
            if (existing != null)
                throw new ConflictException("Email nÃ y Ä‘Ã£ cÃ³ tÃ i khoáº£n. ÄÄƒng nháº­p hoáº·c dÃ¹ng email khÃ¡c.");

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
            return await GenerateAuthResponseWithRefreshTokenAsync(user);
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // FORGOT PASSWORD â€” luÃ´n tráº£ 204 (khÃ´ng tiáº¿t lá»™ email tá»“n táº¡i)
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        public async Task ForgotPasswordAsync(ForgotPasswordRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();
            var user  = await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

            if (user != null)
            {
                // Táº¡o mÃ£ 6 sá»‘ ngáº«u nhiÃªn
                var code    = Random.Shared.Next(100000, 999999).ToString();
                var expires = DateTime.UtcNow.Add(CodeTtl);
                _resetCodes[email] = (code, expires, null);

                // TODO: gá»­i email tháº­t qua IEmailService (MailKit â€” out of scope, package Ä‘Ã£ cÃ i)
                // Hiá»‡n táº¡i: log ra console cho dev test
                Console.WriteLine($"[DEV] Reset code for {email}: {code}");
            }
            // Náº¿u user khÃ´ng tá»“n táº¡i â†’ váº«n tráº£ vá» bÃ¬nh thÆ°á»ng (khÃ´ng lá»™ thÃ´ng tin)
            await Task.CompletedTask;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // VERIFY RESET CODE
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        public async Task<VerifyResetCodeResponse> VerifyResetCodeAsync(VerifyResetCodeRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            if (!_resetCodes.TryGetValue(email, out var entry))
                throw new BadRequestException("Mã xác thực không hợp lệ hoặc đã hết hạn.");

            if (DateTime.UtcNow > entry.ExpiresAt)
            {
                _resetCodes.TryRemove(email, out _);
                throw new BadRequestException("Mã xác thực đã hết hạn.");
            }

            if (entry.Code != request.Code)
            {
                var attempts = _resetCodeAttempts.AddOrUpdate(email, 1, (_, count) => count + 1);
                if (attempts >= 5)
                {
                    _resetCodes.TryRemove(email, out _);
                    _resetCodeAttempts.TryRemove(email, out _);
                    throw new BadRequestException("Bạn đã nhập sai mã xác thực quá 5 lần. Vui lòng yêu cầu mã mới.");
                }
                throw new BadRequestException("Mã xác thực không chính xác.");
            }

            _resetCodeAttempts.TryRemove(email, out _);

            // Tạo một-lần-dùng resetToken
            var resetToken = Guid.NewGuid().ToString("N");
            _resetCodes[email] = (entry.Code, entry.ExpiresAt, resetToken);

            return await Task.FromResult(new VerifyResetCodeResponse { ResetToken = resetToken });
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // RESET PASSWORD
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        public async Task ResetPasswordAsync(ResetPasswordRequest request)
        {
            // TÃ¬m entry cÃ³ resetToken khá»›p
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
                        ?? throw new DomainException("KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n.");

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            user.UpdatedAt    = DateTime.UtcNow;
            await _userRepo.UpdateAsync(user.Id, user);

            _resetCodes.TryRemove(email, out _);
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // PRIVATE HELPERS
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        private async Task<AuthResponse> GenerateAuthResponseWithRefreshTokenAsync(User user)
        {
            var (token, expiresAt) = GenerateJwtToken(user);
            var rawRefreshToken = GenerateRefreshTokenString();
            user.RefreshTokenHash = HashToken(rawRefreshToken);
            user.RefreshTokenExpiresAt = DateTime.UtcNow.AddDays(7);
            await _userRepo.UpdateAsync(user.Id, user);

            return new AuthResponse
            {
                AccessToken  = token,
                RefreshToken = rawRefreshToken,
                ExpiresAt    = expiresAt,
                User         = MapToUserResponse(user)
            };
        }

        private static string GenerateRefreshTokenString()
        {
            var bytes = new byte[32];
            using var rng = System.Security.Cryptography.RandomNumberGenerator.Create();
            rng.GetBytes(bytes);
            return Convert.ToBase64String(bytes).Replace("+", "-").Replace("/", "_").TrimEnd('=');
        }

        private static string HashToken(string token)
        {
            using var sha256 = System.Security.Cryptography.SHA256.Create();
            var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(token));
            return Convert.ToHexString(hashBytes).ToLowerInvariant();
        }

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
                new Claim(ClaimTypes.Name,               user.FullName ?? user.Email),
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
