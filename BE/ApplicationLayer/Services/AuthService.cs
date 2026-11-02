using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
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
    /// </summary>
    public class AuthService : IAuthService
    {
        private readonly IGenericRepository<User> _userRepo;
        private readonly IConfiguration _config;

        // In-memory rate limiter: email -> (failCount, lockUntil)
        private static readonly ConcurrentDictionary<string, (int Count, DateTime? LockUntil)> _failAttempts = new();
        private const int MaxFailAttempts = 5;
        private static readonly TimeSpan LockDuration = TimeSpan.FromMinutes(5);

        // In-memory reset codes: email -> (code, expiresAt, usedResetToken)
        private static readonly ConcurrentDictionary<string, (string Code, DateTime ExpiresAt, string? ResetToken)> _resetCodes = new();
        private static readonly ConcurrentDictionary<string, int> _resetCodeAttempts = new();
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

            // Thử tìm theo EmailNormalized trước, nếu không có mới fallback sang Email.ToLower()
            var user = await _userRepo.FirstOrDefaultAsync(u => u.EmailNormalized == email && !u.IsDeleted)
                       ?? await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

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

            var user = await _userRepo.FirstOrDefaultAsync(u => u.EmailNormalized == email && !u.IsDeleted)
                       ?? await _userRepo.FirstOrDefaultAsync(u => u.Email.ToLower() == email && !u.IsDeleted);

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
        // REFRESH TOKEN (B18)
        // ─────────────────────────────────────────────────────────────────────
        public async Task<AuthResponse> RefreshTokenAsync(RefreshTokenRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.RefreshToken))
                throw new BadRequestException("Refresh token không được để trống.");

            var hashed = HashToken(request.RefreshToken);

            var user = await _userRepo.FirstOrDefaultAsync(u =>
                u.RefreshTokenHash == hashed && !u.IsDeleted);

            if (user == null)
                throw new UnauthorizedException("Refresh token không hợp lệ hoặc đã bị thu hồi.");

            if (!user.RefreshTokenExpiresAt.HasValue || user.RefreshTokenExpiresAt.Value < DateTime.UtcNow)
            {
                user.RefreshTokenHash = null;
                user.RefreshTokenExpiresAt = null;
                await _userRepo.UpdateAsync(user.Id, user);
                throw new UnauthorizedException("Refresh token đã hết hạn. Vui lòng đăng nhập lại.");
            }

            if (user.Status == GeneralEnum.UserStatusEnum.Locked || user.Status == GeneralEnum.UserStatusEnum.Banned)
                throw new AccountLockedException();

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

        // ─────────────────────────────────────────────────────────────────────
        // REGISTER
        // ─────────────────────────────────────────────────────────────────────
        public async Task<AuthResponse> RegisterAsync(RegisterRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            var existing = await _userRepo.FirstOrDefaultAsync(u =>
                (u.EmailNormalized == email || u.Email.ToLower() == email) && !u.IsDeleted);
            if (existing != null)
                throw new ConflictException("Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.");

            var user = new User
            {
                Email           = request.Email.Trim(),
                EmailNormalized = email,
                FullName        = request.FullName.Trim(),
                Phone           = request.Phone?.Trim() ?? string.Empty,
                PasswordHash    = BCrypt.Net.BCrypt.HashPassword(request.Password),
                Role            = "User",
                Status          = GeneralEnum.UserStatusEnum.Active,
                AuthType        = GeneralEnum.AuthTypeEnum.System,
                CreatedAt       = DateTime.UtcNow,
                UpdatedAt       = DateTime.UtcNow
            };

            try
            {
                await _userRepo.CreateAsync(user);
            }
            catch (Exception ex) when (IsDuplicateKeyException(ex))
            {
                throw new ConflictException("Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.");
            }
            return await GenerateAuthResponseWithRefreshTokenAsync(user);
        }

        // ─────────────────────────────────────────────────────────────────────
        // FORGOT PASSWORD
        // ─────────────────────────────────────────────────────────────────────
        public async Task ForgotPasswordAsync(ForgotPasswordRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            // Sinh mã 6 số an toàn bằng RandomNumberGenerator
            var code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString("D6");
            var expiresAt = DateTime.UtcNow.Add(CodeTtl);

            _resetCodes[email] = (code, expiresAt, null);
            _resetCodeAttempts.TryRemove(email, out _);

            // Log mã ra console cho môi trường dev
            Console.WriteLine($"[AUTH DEV] Password reset code for {email}: {code} (expires in 10 mins)");

            await Task.CompletedTask;
        }

        // ─────────────────────────────────────────────────────────────────────
        // VERIFY RESET CODE
        // ─────────────────────────────────────────────────────────────────────
        public async Task<VerifyResetCodeResponse> VerifyResetCodeAsync(VerifyResetCodeRequest request)
        {
            var email = request.Email.Trim().ToLowerInvariant();

            if (!_resetCodes.TryGetValue(email, out var entry))
                throw new BadRequestException("Mã xác thực không hợp lệ hoặc đã hết hạn.", "invalid_code");

            if (DateTime.UtcNow > entry.ExpiresAt)
            {
                _resetCodes.TryRemove(email, out _);
                throw new BadRequestException("Mã xác thực đã hết hạn.", "code_expired");
            }

            if (entry.Code != request.Code)
            {
                var attempts = _resetCodeAttempts.AddOrUpdate(email, 1, (_, count) => count + 1);
                if (attempts >= 5)
                {
                    _resetCodes.TryRemove(email, out _);
                    _resetCodeAttempts.TryRemove(email, out _);
                    throw new BadRequestException("Bạn đã nhập sai mã xác thực quá 5 lần. Vui lòng yêu cầu mã mới.", "too_many_attempts");
                }
                throw new BadRequestException("Mã xác thực không chính xác.", "invalid_code");
            }

            _resetCodeAttempts.TryRemove(email, out _);

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
                throw new BadRequestException("Mã xác thực không hợp lệ.", "invalid_code");

            if (DateTime.UtcNow > entry.Value.ExpiresAt)
            {
                _resetCodes.TryRemove(entry.Key, out _);
                throw new BadRequestException("Mã xác thực đã hết hạn.", "code_expired");
            }

            var email = entry.Key;
            var user = await _userRepo.FirstOrDefaultAsync(u =>
                (u.EmailNormalized == email || u.Email.ToLower() == email) && !u.IsDeleted)
                ?? throw new NotFoundException("Không tìm thấy tài khoản.");

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
            user.RefreshTokenHash = null; // B42: Thu hồi refresh token khi reset password
            user.RefreshTokenExpiresAt = null;
            user.UpdatedAt = DateTime.UtcNow;
            await _userRepo.UpdateAsync(user.Id, user);

            _resetCodes.TryRemove(email, out _);
        }

        // ─────────────────────────────────────────────────────────────────────
        // PRIVATE HELPERS
        // ─────────────────────────────────────────────────────────────────────
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
            using var rng = RandomNumberGenerator.Create();
            rng.GetBytes(bytes);
            return Convert.ToBase64String(bytes).Replace("+", "-").Replace("/", "_").TrimEnd('=');
        }

        private static string HashToken(string token)
        {
            using var sha256 = SHA256.Create();
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

        private static bool IsDuplicateKeyException(Exception ex)
        {
            var typeName = ex.GetType().Name;
            return (typeName == "MongoWriteException" || typeName == "MongoBulkWriteException" || typeName == "MongoDuplicateKeyException")
                && (ex.Message.Contains("11000") || ex.Message.Contains("DuplicateKey") || ex.Message.Contains("duplicate key"));
        }
    }
}
