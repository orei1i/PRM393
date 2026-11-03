using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Database;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using MongoDB.Bson;
using MongoDB.Driver;
using Xunit;

namespace VeganLife.Tests.Fixtures
{
    public sealed class FakeClock : IClock
    {
        private long _ticks = new DateTime(2026, 10, 1, 3, 0, 0, DateTimeKind.Utc).Ticks;
        public DateTime UtcNow => new(Interlocked.Read(ref _ticks), DateTimeKind.Utc);
        public void Set(DateTime utc) => Interlocked.Exchange(ref _ticks, DateTime.SpecifyKind(utc, DateTimeKind.Utc).Ticks);
        public void Advance(TimeSpan by) => Interlocked.Add(ref _ticks, by.Ticks);
    }

    public sealed class SimulatedCrashException : Exception
    {
        public SimulatedCrashException(string point) : base($"Mô phỏng máy chủ chết tại {point}") { }
    }

    /// <summary>Ném lỗi đúng một lần tại điểm đã đặt: phần việc phía sau điểm đó không chạy, y như máy chủ chết.</summary>
    public sealed class TestFailpoints : ICommerceFailpoints
    {
        private readonly object _gate = new();
        private string? _armed;

        public void Arm(string name)
        {
            lock (_gate) _armed = name;
        }

        public void Hit(string name)
        {
            lock (_gate)
            {
                if (_armed != name) return;
                _armed = null;
            }
            throw new SimulatedCrashException(name);
        }
    }

    /// <summary>Test cần Mongo thật: không có Mongo thì báo Skipped chứ không lặng lẽ tính là pass.</summary>
    public sealed class MongoFactAttribute : FactAttribute
    {
        public MongoFactAttribute()
        {
            if (!MongoProbe.IsRunning) Skip = "Cần MongoDB ở localhost:27017 để chạy test tích hợp tiền.";
        }
    }

    public sealed class MongoTheoryAttribute : TheoryAttribute
    {
        public MongoTheoryAttribute()
        {
            if (!MongoProbe.IsRunning) Skip = "Cần MongoDB ở localhost:27017 để chạy test tích hợp tiền.";
        }
    }

    public static class MongoProbe
    {
        private static readonly Lazy<bool> Running = new(() =>
        {
            try
            {
                using var tcp = new System.Net.Sockets.TcpClient();
                var ar = tcp.BeginConnect("127.0.0.1", 27017, null, null);
                return ar.AsyncWaitHandle.WaitOne(TimeSpan.FromMilliseconds(800)) && tcp.Connected;
            }
            catch (Exception)
            {
                return false;
            }
        });

        public static bool IsRunning => Running.Value;
    }

    /// <summary>Giữ lại mọi dòng log của máy chủ để kiểm tra không có bí mật nào lọt vào.</summary>
    public sealed class CapturingLoggerProvider : ILoggerProvider
    {
        public ConcurrentQueue<string> Lines { get; } = new();

        public ILogger CreateLogger(string categoryName) => new CapturingLogger(Lines);

        public void Dispose()
        {
        }

        private sealed class CapturingLogger : ILogger
        {
            private readonly ConcurrentQueue<string> _lines;
            public CapturingLogger(ConcurrentQueue<string> lines) => _lines = lines;
            public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
            public bool IsEnabled(LogLevel logLevel) => true;
            public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
                _lines.Enqueue($"{formatter(state, exception)} {exception}");
        }
    }

    public class CommerceWebApplicationFactory : CustomWebApplicationFactory
    {
        public FakeClock Clock { get; } = new();
        public TestFailpoints Failpoints { get; } = new();
        public CapturingLoggerProvider Logs { get; } = new();

        protected virtual string? PaymentProvider => "Sandbox";
        protected virtual bool JobEnabled => false;

        protected virtual bool SelfConfirm => false;

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new[]
                {
                    new KeyValuePair<string, string?>("Payment:Provider", PaymentProvider),
                    new KeyValuePair<string, string?>("Payment:SandboxSelfConfirm", SelfConfirm ? "true" : "false"),
                    new KeyValuePair<string, string?>("Commerce:SettlementEnabled", JobEnabled ? "true" : "false"),
                    new KeyValuePair<string, string?>("Commerce:SettlementIntervalSeconds", "1")
                });
            });
            builder.ConfigureTestServices(services =>
            {
                services.AddSingleton<IClock>(Clock);
                services.AddSingleton<ICommerceFailpoints>(Failpoints);
                services.AddSingleton<ILoggerProvider>(Logs);
            });
        }
    }

    public sealed class SelfConfirmFactory : CommerceWebApplicationFactory
    {
        protected override bool SelfConfirm => true;
    }

    public sealed class NoProviderFactory : CommerceWebApplicationFactory
    {
        protected override string? PaymentProvider => null;
    }

    public sealed class JobOnFactory : CommerceWebApplicationFactory
    {
        protected override bool JobEnabled => true;
    }

    public record TestUser(string Id, string Token, string Name);

    public record ApiResult(HttpStatusCode Status, JsonElement Root)
    {
        public JsonElement Data => Root.GetProperty("data");
        public string? Code => Root.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString() : null;
    }

    public record PaidBooking(string Id, string OrderId, string EscrowId, string PaymentId, TestUser Member, TestUser Chef, TestUser Admin, long Price, string StartDate, string EndDate);

    /// <summary>Gọi API thật qua HTTP, đọc DB thật. Mỗi người dùng là một id mới nên các test không đụng nhau.</summary>
    public sealed class CommerceHarness
    {
        private readonly CommerceWebApplicationFactory _factory;
        private readonly HttpClient _client;

        public CommerceHarness(CommerceWebApplicationFactory factory)
        {
            _factory = factory;
            _client = factory.CreateClient();
        }

        public FakeClock Clock => _factory.Clock;
        public TestFailpoints Failpoints => _factory.Failpoints;
        public MongoDbContext Db => _factory.Services.GetRequiredService<MongoDbContext>();

        /// <summary>Giờ Việt Nam đổi ra UTC.</summary>
        public static DateTime Vn(int year, int month, int day, int hour = 0, int minute = 0, int second = 0) =>
            new DateTime(year, month, day, hour, minute, second, DateTimeKind.Utc).AddHours(-7);

        public static readonly DateTime T0 = new(2026, 10, 1, 3, 0, 0, DateTimeKind.Utc);

        public async Task<TestUser> UserAsync(string role = "User", string? name = null)
        {
            var id = ObjectId.GenerateNewId().ToString();
            var fullName = name ?? $"{role} {id[^6..]}";
            var email = $"{id}@test.vn";
            await Db.Users.InsertOneAsync(new User
            {
                Id = id,
                Email = email,
                EmailNormalized = email,
                FullName = fullName,
                Phone = "0900000000",
                Role = role
            });
            return new TestUser(id, Jwt(id, role), fullName);
        }

        public Task<TestUser> ChefAsync(string? name = null) => UserAsync("Chef", name);
        public Task<TestUser> AdminAsync(string? name = null) => UserAsync("Admin", name ?? "Lê Minh Quân");

        private static string Jwt(string userId, string role)
        {
            var key = Encoding.UTF8.GetBytes("VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!");
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
                SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
            }));
        }

        public async Task<ApiResult> CallAsync(HttpMethod method, string path, TestUser? user = null, object? body = null)
        {
            using var request = new HttpRequestMessage(method, $"/api/v1{path}");
            if (user != null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", user.Token);
            if (body != null) request.Content = JsonContent.Create(body);
            using var response = await _client.SendAsync(request);
            var text = await response.Content.ReadAsStringAsync();
            var root = string.IsNullOrWhiteSpace(text) ? default : JsonDocument.Parse(text).RootElement.Clone();
            return new ApiResult(response.StatusCode, root);
        }

        public IEnumerable<string> ServerLogs => _factory.Logs.Lines;

        /// <summary>Đường dẫn ngoài /api/v1, ví dụ tài liệu Swagger.</summary>
        public async Task<(HttpStatusCode Status, string Body)> RawGetAsync(string path)
        {
            using var response = await _client.GetAsync(path);
            return (response.StatusCode, await response.Content.ReadAsStringAsync());
        }

        public Task<ApiResult> GetAsync(string path, TestUser? user = null) => CallAsync(HttpMethod.Get, path, user);
        public Task<ApiResult> PostAsync(string path, TestUser? user = null, object? body = null) => CallAsync(HttpMethod.Post, path, user, body);
        public Task<ApiResult> PutAsync(string path, TestUser? user = null, object? body = null) => CallAsync(HttpMethod.Put, path, user, body);

        public async Task<ApiResult> OkAsync(Task<ApiResult> call)
        {
            var result = await call;
            Assert.True(result.Status is HttpStatusCode.OK or HttpStatusCode.Created, $"Mong đợi thành công, nhận {(int)result.Status}: {result.Root}");
            Assert.True(result.Root.GetProperty("success").GetBoolean());
            return result;
        }

        public static void AssertError(ApiResult result, HttpStatusCode status, string code)
        {
            Assert.True(result.Status == status, $"Mong đợi {(int)status} {code}, nhận {(int)result.Status}: {result.Root}");
            Assert.Equal(code, result.Code);
            Assert.False(result.Root.GetProperty("success").GetBoolean());
        }

        public async Task RunJobAsync()
        {
            using var scope = _factory.Services.CreateScope();
            await scope.ServiceProvider.GetRequiredService<IBookingEngine>().RunOnceAsync();
        }

        /* ---------------------------------------------------------------- dựng dữ liệu qua API */

        public static object BookingBody(string chefId, string type = "OneShot", int days = 3, string start = "2026-10-10") => new
        {
            chefId,
            bookingType = type,
            planDays = days,
            startDate = start,
            audience = "Self",
            goal = "lose_weight",
            allergies = new[] { "peanut" },
            mealPattern = new[] { "breakfast", "dinner" },
            budgetPerDay = 80000,
            needs = "Mình muốn giảm khoảng 3 kg trong tháng, bữa sáng cần làm nhanh.",
            shareHealthProfile = true
        };

        public async Task<string> RequestAsync(TestUser member, TestUser chef, string type = "OneShot", int days = 3, string start = "2026-10-10")
        {
            var created = await OkAsync(PostAsync("/bookings", member, BookingBody(chef.Id, type, days, start)));
            Assert.Equal(HttpStatusCode.Created, created.Status);
            return created.Data.GetProperty("id").GetString()!;
        }

        public async Task<string> AgreeAsync(string bookingId, TestUser member, TestUser chef, long price, string type = "OneShot", int days = 3, string start = "2026-10-10")
        {
            var offered = await OkAsync(PostAsync($"/bookings/{bookingId}/offers", chef, new { price, planDays = days, bookingType = type, startDate = start, note = "Giá đã thống nhất" }));
            var offerId = offered.Data.GetProperty("currentOffer").GetProperty("id").GetString()!;
            var accepted = await OkAsync(PostAsync($"/bookings/{bookingId}/offers/{offerId}/accept", member));
            return accepted.Data.GetProperty("paymentOrderId").GetString()!;
        }

        public async Task<string> OpenQrAsync(string bookingId, TestUser member)
        {
            var order = await OkAsync(PostAsync($"/bookings/{bookingId}/payments", member));
            return order.Data.GetProperty("payment").GetProperty("id").GetString()!;
        }

        public async Task<PaidBooking> PaidAsync(long price = 900_000, string type = "OneShot", int days = 3, string start = "2026-10-10", TestUser? member = null, TestUser? chef = null, TestUser? admin = null)
        {
            member ??= await UserAsync();
            chef ??= await ChefAsync();
            admin ??= await AdminAsync();
            var id = await RequestAsync(member, chef, type, days, start);
            var orderId = await AgreeAsync(id, member, chef, price, type, days, start);
            var paymentId = await OpenQrAsync(id, member);
            await OkAsync(PostAsync($"/payments/{paymentId}/sandbox-confirm", admin, new { success = true }));
            var booking = await OkAsync(GetAsync($"/bookings/{id}", member));
            Assert.Equal("Active", booking.Data.GetProperty("status").GetString());
            return new PaidBooking(id, orderId, booking.Data.GetProperty("escrow").GetProperty("id").GetString()!, paymentId, member, chef, admin, price, start,
                booking.Data.GetProperty("contract").GetProperty("endDate").GetString()!);
        }

        public async Task SaveDayAsync(string id, TestUser chef, int day) =>
            await OkAsync(PutAsync($"/chefs/me/bookings/{id}/plan/days/{day}", chef, new
            {
                chefNote = "Uống đủ nước",
                meals = new[]
                {
                    new { slot = "breakfast", recipe = new { name = "Yến mạch chuối", calories = 350 }, note = (string?)null },
                    new { slot = "dinner", recipe = new { name = "Đậu hũ sốt cà", calories = 520 }, note = (string?)"Ít muối" }
                }
            }));

        public async Task DeliverAllAsync(PaidBooking b, int days = 3, string type = "OneShot")
        {
            for (var d = 1; d <= days; d++) await SaveDayAsync(b.Id, b.Chef, d);
            if (type == "OneShot")
            {
                await OkAsync(PostAsync($"/chefs/me/bookings/{b.Id}/plan/send", b.Chef));
            }
            else
            {
                for (var d = 1; d <= days; d++) await OkAsync(PostAsync($"/chefs/me/bookings/{b.Id}/plan/days/{d}/send", b.Chef));
            }
        }

        public async Task<JsonElement> BookingAsync(string id, TestUser user) => (await OkAsync(GetAsync($"/bookings/{id}", user))).Data;

        public async Task<(long Available, long Processing, long Withdrawn)> FiguresAsync(TestUser user)
        {
            var wallet = (await OkAsync(GetAsync("/users/me/wallet", user))).Data;
            return (wallet.GetProperty("available").GetInt64(), wallet.GetProperty("processing").GetInt64(), wallet.GetProperty("withdrawn").GetInt64());
        }

        public async Task<long> AvailableAsync(TestUser user) => (await FiguresAsync(user)).Available;

        public async Task SaveBankAsync(TestUser user) =>
            await OkAsync(PutAsync("/users/me/bank-account", user, new { bankName = "Vietcombank", accountNumber = "0071000456789", accountHolder = "Nguyen Van A" }));

        /// <summary>Cho ví của thành viên có tiền: trả sandbox rồi huỷ khi chưa giao ngày nào.</summary>
        public async Task FundWalletAsync(TestUser member, long amount)
        {
            var b = await PaidAsync(amount, member: member);
            await OkAsync(PostAsync($"/bookings/{b.Id}/cancel", member, new { reason = "Đổi kế hoạch cá nhân" }));
        }

        /// <summary>Ghi một khoản vào ví qua đúng dịch vụ sổ cái, cho test không có đường nào khác để nạp tiền.</summary>
        public async Task CreditAsync(TestUser user, long amount)
        {
            using var scope = _factory.Services.CreateScope();
            var key = $"test:{ObjectId.GenerateNewId()}:credit";
            await scope.ServiceProvider.GetRequiredService<IWalletLedgerService>().PostCreditAsync(new WalletLedgerEntry
            {
                Id = WalletLedgerEntry.IdForKey(key),
                IdempotencyKey = key,
                UserId = user.Id,
                Kind = "test_credit",
                Type = "Refund",
                DeltaAvailable = amount,
                OccurredAt = Clock.UtcNow,
                CreatedAt = Clock.UtcNow
            });
        }

        /// <summary>
        /// Sổ cái khớp số dư: mỗi ví đúng bằng tổng các bút toán đã áp dụng, không id nào lặp, không âm,
        /// không bút toán đã đánh dấu áp dụng nào nằm ngoài ví.
        /// </summary>
        public async Task AssertBooksBalanceAsync(params TestUser[] users)
        {
            foreach (var user in users)
            {
                var wallet = await Db.Wallets.Find(w => w.Id == user.Id).FirstOrDefaultAsync();
                var entries = await Db.WalletLedger.Find(e => e.UserId == user.Id).ToListAsync();
                var appliedIds = wallet?.AppliedEntryIds ?? new List<string>();
                Assert.Equal(appliedIds.Count, appliedIds.Distinct().Count());
                var applied = entries.Where(e => appliedIds.Contains(e.Id)).ToList();
                Assert.Equal(appliedIds.Count, applied.Count);
                Assert.Equal(applied.Sum(e => e.DeltaAvailable), wallet?.Available ?? 0);
                Assert.Equal(applied.Sum(e => e.DeltaProcessing), wallet?.Processing ?? 0);
                Assert.Equal(applied.Sum(e => e.DeltaWithdrawn), wallet?.Withdrawn ?? 0);
                Assert.True((wallet?.Available ?? 0) >= 0 && (wallet?.Processing ?? 0) >= 0);
                foreach (var e in entries.Where(e => e.Applied)) Assert.Contains(e.Id, appliedIds);
            }
        }
    }
}
