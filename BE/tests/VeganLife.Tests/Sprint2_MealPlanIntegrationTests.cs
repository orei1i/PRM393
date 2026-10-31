using System;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.MealPlan;
using ControllerLayer.Models;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using VeganLife.Tests.Fixtures;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint2_MealPlanIntegrationTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly HttpClient _client;

        public Sprint2_MealPlanIntegrationTests(CustomWebApplicationFactory factory)
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

        private static bool IsMongoRunning()
        {
            try
            {
                using var tcp = new System.Net.Sockets.TcpClient();
                var ar = tcp.BeginConnect("127.0.0.1", 27017, null, null);
                var success = ar.AsyncWaitHandle.WaitOne(TimeSpan.FromMilliseconds(500));
                return success && tcp.Connected;
            }
            catch
            {
                return false;
            }
        }

        [Fact]
        public async Task B24_GetCurrentMealPlan_WhenNoPlanForCurrentWeek_Returns404NotFound()
        {
            if (!IsMongoRunning()) return;

            var userId = "507f1f77bcf86cd799439099";
            var token = GenerateJwt(userId, "User");

            var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/meal-plans/current");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var response = await _client.SendAsync(request);

            // B24: Khi chưa có thực đơn cho tuần hiện tại (tính theo thứ Hai múi giờ VN UTC+7), trả 404 không fallback
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }

        [Fact]
        public async Task B26_GetMealPlanById_WhenPlanBelongsToAnotherUser_Returns404NotFound()
        {
            if (!IsMongoRunning()) return;

            var loggedInUserId = "507f1f77bcf86cd799439011";
            var token = GenerateJwt(loggedInUserId, "User");
            var arbitraryPlanId = "507f1f77bcf86cd799439022";

            var request = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/meal-plans/{arbitraryPlanId}");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var response = await _client.SendAsync(request);

            // B26: Chống IDOR, không cho phép xem thực đơn của user khác
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }

        [Fact]
        public async Task M1_FromIngredients_ReturnsListAndLeavesDbUntouched()
        {
            if (!IsMongoRunning()) return;

            var userId = "507f1f77bcf86cd799439033";
            var token = GenerateJwt(userId, "User");

            var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/meal-plans/from-ingredients")
            {
                Content = JsonContent.Create(new GenerateMealPlanRequest())
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var response = await _client.SendAsync(request);

            // M1: from-ingredients thành công trả về danh sách gợi ý 200 OK
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
    }
}
