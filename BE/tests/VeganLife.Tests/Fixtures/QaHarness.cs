using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using DomainLayer.Entities;
using InfrastructureLayer.Database;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using MongoDB.Bson;
using Xunit;

namespace VeganLife.Tests.Fixtures
{
    /// <summary>Máy chủ thật trên DB ngẫu nhiên, cho test gọi API của bài viết, người dùng, công thức, thực đơn.</summary>
    public class QaFactory : CustomWebApplicationFactory
    {
        public CapturingLoggerProvider Logs { get; } = new();

        protected virtual IEnumerable<KeyValuePair<string, string?>> Settings => new[]
        {
            new KeyValuePair<string, string?>("Auth:DevResetCodes", "true"),
            new KeyValuePair<string, string?>("Commerce:SettlementEnabled", "false")
        };

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(Settings));
            builder.ConfigureTestServices(services => services.AddSingleton<ILoggerProvider>(Logs));
        }
    }

    public sealed class RequireApprovalFactory : QaFactory
    {
        protected override IEnumerable<KeyValuePair<string, string?>> Settings =>
            base.Settings.Append(new KeyValuePair<string, string?>("Posts:RequireApproval", "true"));
    }

    /// <summary>Development nhưng không bật lối đọc mã.</summary>
    public sealed class NoDevCodesFactory : QaFactory
    {
        protected override IEnumerable<KeyValuePair<string, string?>> Settings => new[]
        {
            new KeyValuePair<string, string?>("Commerce:SettlementEnabled", "false")
        };
    }

    /// <summary>Chạy như production: dù có bật Auth:DevResetCodes cũng không được có lối đọc mã.</summary>
    public sealed class ProductionFactory : QaFactory
    {
        private const string NotPlaceholder = "VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseSetting("JwtSettings:SecretKey", NotPlaceholder);
            builder.UseSetting("FranchiseOnboarding:DefaultManagerPassword", "not-a-real-value-for-tests");
            base.ConfigureWebHost(builder);
            builder.UseEnvironment("Production");
        }
    }

    public record QaUser(string Id, string Token, string Name, string Email);

    public record QaResult(HttpStatusCode Status, JsonElement Root, string Text)
    {
        public JsonElement Data => Root.GetProperty("data");
        public string? Code => Root.ValueKind == JsonValueKind.Object && Root.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString() : null;
        public string? Message => Root.ValueKind == JsonValueKind.Object && Root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString() : null;
        public string Str(string name) => Data.GetProperty(name).GetString() ?? string.Empty;
        public bool HasDetail => Root.ValueKind == JsonValueKind.Object && Root.TryGetProperty("detail", out var d) && d.ValueKind != JsonValueKind.Null;
    }

    public sealed class Qa
    {
        public const string Password = "MatKhauTest123!";
        private const string JwtKey = "VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!";

        private readonly QaFactory _factory;
        private readonly HttpClient _client;

        public Qa(QaFactory factory)
        {
            _factory = factory;
            _client = factory.CreateClient();
        }

        public MongoDbContext Db => _factory.Services.GetRequiredService<MongoDbContext>();
        public IEnumerable<string> Logs => _factory.Logs.Lines;

        public async Task<QaUser> UserAsync(string role = "User", string? name = null)
        {
            var id = ObjectId.GenerateNewId().ToString();
            var email = $"{id}@test.vn";
            var fullName = name ?? $"{role} {id[^6..]}";
            await Db.Users.InsertOneAsync(new User
            {
                Id = id,
                Email = email,
                EmailNormalized = email,
                FullName = fullName,
                Phone = "0900000000",
                Role = role,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(Password, 4),
                Status = DomainLayer.Enums.GeneralEnum.UserStatusEnum.Active,
                CreatedAt = DateTime.UtcNow
            });
            return new QaUser(id, Jwt(id, role), fullName, email);
        }

        public Task<QaUser> AdminAsync() => UserAsync("Admin");

        public static string Jwt(string userId, string role)
        {
            var handler = new JwtSecurityTokenHandler();
            return handler.WriteToken(handler.CreateToken(new SecurityTokenDescriptor
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
                SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(JwtKey)), SecurityAlgorithms.HmacSha256Signature)
            }));
        }

        public async Task<QaResult> CallAsync(HttpMethod method, string path, QaUser? user = null, object? body = null, string? rawJson = null, string? token = null)
        {
            using var request = new HttpRequestMessage(method, path.StartsWith("/api/") || path.StartsWith("/vision") ? path : $"/api/v1{path}");
            var bearer = token ?? user?.Token;
            if (bearer != null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            if (rawJson != null) request.Content = new StringContent(rawJson, Encoding.UTF8, "application/json");
            else if (body != null) request.Content = JsonContent.Create(body);
            using var response = await _client.SendAsync(request);
            var text = await response.Content.ReadAsStringAsync();
            JsonElement root = default;
            if (!string.IsNullOrWhiteSpace(text))
            {
                try { root = JsonDocument.Parse(text).RootElement.Clone(); }
                catch (JsonException) { /* giữ text */ }
            }
            return new QaResult(response.StatusCode, root, text);
        }

        public Task<QaResult> GetAsync(string path, QaUser? user = null) => CallAsync(HttpMethod.Get, path, user);
        public Task<QaResult> PostAsync(string path, QaUser? user = null, object? body = null) => CallAsync(HttpMethod.Post, path, user, body);
        public Task<QaResult> PutAsync(string path, QaUser? user = null, object? body = null) => CallAsync(HttpMethod.Put, path, user, body);
        public Task<QaResult> PatchAsync(string path, QaUser? user = null, object? body = null) => CallAsync(HttpMethod.Patch, path, user, body);
        public Task<QaResult> DeleteAsync(string path, QaUser? user = null, object? body = null) => CallAsync(HttpMethod.Delete, path, user, body);

        public static void Is(HttpStatusCode expected, QaResult result, string? code = null)
        {
            Assert.True(result.Status == expected, $"Mong đợi {(int)expected}, nhận {(int)result.Status}: {result.Text}");
            if (code != null) Assert.Equal(code, result.Code);
        }

        public static void IsOk(QaResult result) => Assert.True(
            result.Status is HttpStatusCode.OK or HttpStatusCode.Created or HttpStatusCode.NoContent,
            $"Mong đợi thành công, nhận {(int)result.Status}: {result.Text}");

        public static object PostBody(string title = "Bài thử", string body = "Nội dung bài thử") => new { type = "discussion", title, body, mediaType = "Text" };

        public async Task<string> NewPostAsync(QaUser author, string title = "Bài thử")
        {
            var created = await PostAsync("/posts", author, PostBody(title));
            IsOk(created);
            return created.Str("id");
        }

        public async Task<string> NewCommentAsync(QaUser author, string postId, string content = "Bình luận thử", string? parentId = null)
        {
            var created = await PostAsync($"/posts/{postId}/comments", author, new { content, parentId });
            IsOk(created);
            return created.Str("id");
        }

        public static object ProfileBody(object[]? allergies = null, string? goal = "maintain", double weightKg = 66, string? activityLevel = "moderate") => new
        {
            heightCm = 170,
            weightKg,
            goal,
            gender = "Female",
            birthYear = 1998,
            activityLevel,
            allergies = allergies ?? Array.Empty<object>()
        };

        public async Task<string> SystemRecipeIdAsync()
        {
            var catalog = await GetAsync("/recipes?limit=1");
            IsOk(catalog);
            return catalog.Data.GetProperty("items")[0].GetProperty("id").GetString()!;
        }

        public async Task<string> OwnRecipeAsync(QaUser user, string name = "Rau xào của tôi")
        {
            var created = await PostAsync("/recipes", user, new { name, calories = 300, prepMinutes = 10, ingredients = new[] { "Rau" }, instructions = new[] { "Nấu" } });
            IsOk(created);
            return created.Str("id");
        }

        public static string ThisMonday()
        {
            var today = DateTime.UtcNow.AddHours(7).Date;
            var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
            return today.AddDays(-diff).ToString("yyyy-MM-dd");
        }

        public static string Today() => DateTime.UtcNow.AddHours(7).ToString("yyyy-MM-dd");
    }
}
