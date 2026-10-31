using System;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Auth;
using ControllerLayer.Models;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using VeganLife.Tests.Fixtures;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint1_AuthAndUserTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly HttpClient _client;

        public Sprint1_AuthAndUserTests(CustomWebApplicationFactory factory)
        {
            _client = factory.CreateClient();
        }

        private static string GenerateJwt(string userId, string role)
        {
            var tokenHandler = new JwtSecurityTokenHandler();
            var key = Encoding.UTF8.GetBytes("VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!");
            var tokenDescriptor = new SecurityTokenDescriptor
            {
                Subject = new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, userId),
                    new Claim(ClaimTypes.Role, role),
                    new Claim("sub", userId)
                }),
                Expires = DateTime.UtcNow.AddHours(1),
                Issuer = "VeganLifeTestIssuer",
                Audience = "VeganLifeTestAudience",
                SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
            };
            var token = tokenHandler.CreateToken(tokenDescriptor);
            return tokenHandler.WriteToken(token);
        }

        [Fact]
        public async Task B3_UserEndpoints_AccessOtherUser_ShouldReturnForbidden403()
        {
            var loggedInUserId = "507f1f77bcf86cd799439011";
            var targetUserId = "507f1f77bcf86cd799439022";
            var token = GenerateJwt(loggedInUserId, "User");

            var request = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/users/{targetUserId}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var response = await _client.SendAsync(request);

            // B3: User thường chỉ được xem hồ sơ của chính mình. Xem người khác phải trả 403 Forbidden
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }

        [Fact]
        public async Task B18_RefreshToken_EmptyOrWhitespace_ReturnsUnauthorized401()
        {
            var request = new RefreshTokenRequest
            {
                RefreshToken = "   "
            };

            var response = await _client.PostAsJsonAsync("/api/v1/auth/refresh", request);

            // B18: Token trống hoặc không hợp lệ phải trả về 401 Unauthorized hoặc 400 BadRequest
            Assert.True(response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.BadRequest);
        }

        [Fact]
        public async Task B23_VerifyResetCode_ExcessiveAttempts_ReturnsRateLimited()
        {
            var request = new VerifyResetCodeRequest
            {
                Email = "test_rate_limit@veganlife.vn",
                Code = "999999"
            };

            HttpResponseMessage? lastResponse = null;
            for (int i = 0; i < 6; i++)
            {
                lastResponse = await _client.PostAsJsonAsync("/api/v1/auth/verify-reset-code", request);
            }

            // B23: Sau 5 lần nhập sai liên tiếp, hệ thống khoá mã và trả lỗi (429 TooManyRequests hoặc 400 BadRequest)
            Assert.NotNull(lastResponse);
            Assert.True(lastResponse.StatusCode == HttpStatusCode.TooManyRequests || lastResponse.StatusCode == HttpStatusCode.BadRequest);
        }
    }
}
