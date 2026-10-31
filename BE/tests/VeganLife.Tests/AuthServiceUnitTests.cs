using System;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Auth;
using ApplicationLayer.Services;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Configuration;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class AuthServiceUnitTests
    {
        private readonly Mock<IGenericRepository<User>> _userRepoMock;
        private readonly IConfiguration _config;
        private readonly AuthService _authService;

        public AuthServiceUnitTests()
        {
            _userRepoMock = new Mock<IGenericRepository<User>>();
            var inMemorySettings = new System.Collections.Generic.Dictionary<string, string?>
            {
                { "JwtSettings:SecretKey", "VerySecretKeyForTestingSprint1Auth_32CharsMinimum!" },
                { "JwtSettings:Issuer", "VeganLifeAuthService" },
                { "JwtSettings:Audience", "VeganLifeClients" },
                { "JwtSettings:ExpiryMinutes", "60" }
            };
            _config = new ConfigurationBuilder().AddInMemoryCollection(inMemorySettings).Build();
            _authService = new AuthService(_userRepoMock.Object, _config);
        }

        [Fact]
        public async Task B2_AdminLoginAsync_WhenUserIsNotAdmin_ThrowsForbiddenException()
        {
            var regularUser = new User
            {
                Id = "507f1f77bcf86cd799439011",
                Email = "minhanh.nguyen@gmail.com",
                Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Password123!"),
                Status = DomainLayer.Enums.GeneralEnum.UserStatusEnum.Active
            };

            _userRepoMock
                .Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<User, bool>>>()))
                .ReturnsAsync(regularUser);

            var request = new LoginRequest
            {
                Email = "minhanh.nguyen@gmail.com",
                Password = "Password123!"
            };

            // B2: Tài khoản role không phải Admin khi đăng nhập route admin/login phải bị từ chối 403 Forbidden
            await Assert.ThrowsAsync<ForbiddenException>(() => _authService.AdminLoginAsync(request));
        }

        [Fact]
        public async Task B2_AdminLoginAsync_WhenUserIsAdmin_ReturnsTokens()
        {
            var adminUser = new User
            {
                Id = "507f1f77bcf86cd799439099",
                Email = "admin@veganlife.vn",
                FullName = "Admin VeganLife",
                Role = "Admin",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Password123!"),
                Status = DomainLayer.Enums.GeneralEnum.UserStatusEnum.Active
            };

            _userRepoMock
                .Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<User, bool>>>()))
                .ReturnsAsync(adminUser);

            var request = new LoginRequest
            {
                Email = "admin@veganlife.vn",
                Password = "Password123!"
            };

            var result = await _authService.AdminLoginAsync(request);

            Assert.NotNull(result);
            Assert.NotEmpty(result.AccessToken);
            Assert.NotEmpty(result.RefreshToken);
            Assert.Equal("admin@veganlife.vn", result.User.Email);
            Assert.Equal("Admin", result.User.Role);
        }

        [Fact]
        public async Task B18_RefreshTokenAsync_WhenUserNotFoundOrTokenMismatch_ThrowsUnauthorizedException()
        {
            _userRepoMock
                .Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<User, bool>>>()))
                .ReturnsAsync((User?)null);

            var request = new RefreshTokenRequest
            {
                RefreshToken = "some-tampered-or-expired-token"
            };

            // B18: Refresh token không khớp hoặc đã bị thu hồi ném UnauthorizedException
            await Assert.ThrowsAsync<UnauthorizedException>(() => _authService.RefreshTokenAsync(request));
        }

        [Fact]
        public async Task B18_LogoutAsync_RevokesRefreshToken()
        {
            var user = new User
            {
                Id = "507f1f77bcf86cd799439099",
                Email = "admin@veganlife.vn",
                RefreshTokenHash = "some_hash_string",
                RefreshTokenExpiresAt = DateTime.UtcNow.AddDays(7)
            };

            _userRepoMock.Setup(r => r.FindByIdAsync("507f1f77bcf86cd799439099")).ReturnsAsync(user);

            await _authService.LogoutAsync("507f1f77bcf86cd799439099");

            Assert.Null(user.RefreshTokenHash);
            Assert.Null(user.RefreshTokenExpiresAt);
            _userRepoMock.Verify(r => r.UpdateAsync(user.Id, user), Times.Once);
        }
    }
}
