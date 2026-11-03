using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using InfrastructureLayer.ExternalServices;
using InfrastructureLayer.Repository;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.IdentityModel.Tokens;
using MongoDB.Bson;
using MongoDB.Driver;
using VeganLife.Tests.Fixtures;
using Xunit;
using static VeganLife.Tests.Fixtures.CommerceHarness;

namespace VeganLife.Tests
{
    public sealed class ScriptedGemini : IGeminiClient
    {
        public bool Configured { get; set; } = true;
        public Func<object?>? JsonResult { get; set; }
        public int JsonCalls;
        public string? LastMime;

        public bool IsConfigured => Configured;

        public Task<T> GenerateJsonAsync<T>(string prompt, byte[]? imageBytes = null, string? mimeType = null, string taskType = "Vision", string? userId = null, string? scanId = null, CancellationToken ct = default)
        {
            Interlocked.Increment(ref JsonCalls);
            LastMime = mimeType;
            return Task.FromResult((T)JsonResult!()!);
        }

        public Task<string> GenerateTextAsync(string prompt, string taskType = "General", string? userId = null, CancellationToken ct = default) => throw new NotSupportedException();

        public async IAsyncEnumerable<string> StreamTextAsync(string prompt, string taskType = "Chat", string? userId = null, [EnumeratorCancellation] CancellationToken ct = default, string? systemInstruction = null)
        {
            await Task.Yield();
            yield break;
        }

        public Task<List<float[]>> EmbedAsync(IEnumerable<string> texts, string taskType = "RETRIEVAL_DOCUMENT", CancellationToken ct = default) => throw new NotSupportedException();
    }

    public sealed class FakeVideoReader : IVideoContentReader
    {
        public Exception? Failure { get; set; }

        public Task<(byte[] Bytes, string MimeType)> ReadAsync(string url, long maxBytes, CancellationToken ct = default) =>
            Failure != null ? throw Failure : Task.FromResult((new byte[] { 1, 2, 3 }, "video/mp4"));
    }

    public sealed class FakeGeocoder : IGeocodingClient
    {
        public int Calls;
        public bool IsConfigured => true;

        public Task<List<GeoPlaceResult>> SearchAsync(string query, CancellationToken ct = default)
        {
            Interlocked.Increment(ref Calls);
            return Task.FromResult(new List<GeoPlaceResult> { new("Chợ Bến Thành", "Lê Lợi, Quận 1", "TP. Hồ Chí Minh", 10.7725, 106.698) });
        }

        public Task<GeoPlaceResult?> ReverseAsync(double latitude, double longitude, CancellationToken ct = default)
        {
            Interlocked.Increment(ref Calls);
            return Task.FromResult(latitude > 0 ? new GeoPlaceResult("Chợ Bến Thành", "Lê Lợi, Quận 1", null, latitude, longitude) : null);
        }
    }

    /// <summary>Cấu hình như máy chủ thật khi thiếu Geo:BaseUrl: dùng client thật, không gọi ra ngoài.</summary>
    public class ContentFactory : CommerceWebApplicationFactory
    {
        public ScriptedGemini Gemini { get; } = new();
        public FakeVideoReader Videos { get; } = new();
        protected virtual string AdsLimit => "100000";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new[]
            {
                new KeyValuePair<string, string?>("Videos:WorkerEnabled", "false"),
                new KeyValuePair<string, string?>("Videos:AutoExtract", "true"),
                new KeyValuePair<string, string?>("Geo:BaseUrl", ""),
                new KeyValuePair<string, string?>("Geo:RateLimitPerMinute", "100000"),
                new KeyValuePair<string, string?>("Ads:RateLimitPerMinute", AdsLimit)
            }));
            builder.ConfigureTestServices(services =>
            {
                services.AddSingleton<IGeminiClient>(Gemini);
                services.AddSingleton<IVideoContentReader>(Videos);
            });
        }
    }

    public sealed class GeoConfiguredFactory : ContentFactory
    {
        public FakeGeocoder Geo { get; } = new();

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureTestServices(services => services.AddSingleton<IGeocodingClient>(Geo));
        }
    }

    public sealed class AdsLimitedFactory : ContentFactory
    {
        protected override string AdsLimit => "5";
    }

    internal static class ContentApi
    {
        public static string Token(string userId, string role)
        {
            var key = Encoding.UTF8.GetBytes("VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!");
            var handler = new JwtSecurityTokenHandler();
            return handler.WriteToken(handler.CreateToken(new SecurityTokenDescriptor
            {
                Subject = new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId), new Claim(ClaimTypes.Role, role), new Claim("sub", userId) }),
                Expires = DateTime.UtcNow.AddHours(1),
                Issuer = "VeganLifeTestIssuer",
                Audience = "VeganLifeTestAudience",
                SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
            }));
        }

        public static Task<ApiResult> PatchAsync(this CommerceHarness h, string path, TestUser? user, object body) => h.CallAsync(HttpMethod.Patch, path, user, body);
        public static Task<ApiResult> DeleteAsync(this CommerceHarness h, string path, TestUser? user) => h.CallAsync(HttpMethod.Delete, path, user);

        public static string Id(this ApiResult r) => r.Data.GetProperty("id").GetString()!;
        public static string Str(this JsonElement e, string name) => e.GetProperty(name).GetString()!;
        public static List<string> Ids(this ApiResult r) => r.Data.EnumerateArray().Select(x => x.Str("id")).ToList();

        public static string Bio => new('x', 60);

        public static object Application() => new
        {
            specialties = new[] { "Ẩm thực chay Việt", "Giảm cân" },
            yearsExperience = 7,
            city = "Đà Nẵng",
            bio = "Tôi nấu ăn chay hơn bảy năm và tư vấn thực đơn cho gia đình có người lớn tuổi.",
            certificates = new[] { "Chứng chỉ Dinh dưỡng" }
        };

        public static object Profile(int min = 3, int max = 30, bool accepting = true, long price = 150_000, long feedback = 180_000) => new
        {
            specialty = "Ẩm thực chay Huế",
            bio = "Tôi nấu ăn chay hơn bảy năm và tư vấn thực đơn cho gia đình có người lớn tuổi.",
            pricePerDay = price,
            feedbackPricePerDay = feedback,
            minPlanDays = min,
            maxPlanDays = max,
            acceptingBookings = accepting
        };

        public static async Task<string> ChefWithProfileAsync(this CommerceHarness h, TestUser chef, object? profile = null) =>
            (await h.OkAsync(h.PutAsync("/chefs/me/profile", chef, profile ?? Profile()))).Id();

        public static async Task<string> ApprovedRestaurantAsync(this CommerceHarness h, TestUser admin, TestUser author, string name, string? address = null, double? lat = 10.77, double? lng = 106.70)
        {
            var id = (await h.OkAsync(h.PostAsync("/restaurants", author, new
            {
                name,
                address = address ?? $"123 Đường Thử {ObjectId.GenerateNewId()}",
                latitude = lat,
                longitude = lng
            }))).Id();
            await h.OkAsync(h.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Approve" }));
            return id;
        }

        public static object Ad(string restaurantId, string? city = null, long budget = 500_000, string? start = null, string? end = null) => new
        {
            restaurantId,
            placement = "nearby",
            headline = "Bún riêu chay ngon",
            message = "Tô đầy đặn, nước dùng ngọt từ rau củ.",
            ctaType = "ViewStore",
            targetCity = city,
            startAt = start ?? "2026-09-01T00:00:00Z",
            endAt = end ?? "2026-12-01T00:00:00Z",
            budget
        };
    }

    public class Sprint11_AuthorizationTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_AuthorizationTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private const string AnyId = "507f1f77bcf86cd799439011";

        public static IEnumerable<object[]> AdminRoutes() => new[]
        {
            new object[] { "GET", "/admin/chef-applications" },
            new object[] { "GET", "/admin/chef-applications/counts" },
            new object[] { "POST", $"/admin/chef-applications/{AnyId}/review" },
            new object[] { "GET", "/admin/restaurants" },
            new object[] { "POST", $"/admin/restaurants/{AnyId}/review" },
            new object[] { "PATCH", $"/admin/restaurants/{AnyId}" },
            new object[] { "DELETE", $"/admin/restaurants/{AnyId}" },
            new object[] { "GET", $"/admin/restaurants/{AnyId}/reviews" },
            new object[] { "DELETE", $"/admin/reviews/{AnyId}" },
            new object[] { "GET", "/admin/overview" },
            new object[] { "GET", "/admin/catalog?kind=allergen" },
            new object[] { "POST", "/admin/catalog" },
            new object[] { "PATCH", $"/admin/catalog/{AnyId}" },
            new object[] { "DELETE", $"/admin/catalog/{AnyId}" },
            new object[] { "GET", "/admin/moderation/flags" },
            new object[] { "GET", "/admin/moderation/flags/counts" },
            new object[] { "POST", $"/admin/moderation/flags/{AnyId}/decision" },
            new object[] { "GET", "/admin/ai/telemetry/summary?range=24h" },
            new object[] { "GET", "/admin/ai/logs" },
            new object[] { "GET", $"/admin/ai/logs/{AnyId}" },
            new object[] { "POST", $"/admin/ai/logs/{AnyId}/label" },
            new object[] { "GET", "/admin/ai/models" },
            new object[] { "PATCH", $"/admin/ai/models/{AnyId}" },
            new object[] { "GET", "/admin/ai/metrics?range=24h" },
            new object[] { "GET", "/admin/ads" },
            new object[] { "POST", "/admin/ads" },
            new object[] { "PATCH", $"/admin/ads/{AnyId}" },
            new object[] { "POST", $"/admin/ads/{AnyId}/pause" },
            new object[] { "POST", $"/admin/ads/{AnyId}/resume" },
            new object[] { "DELETE", $"/admin/ads/{AnyId}" }
        };

        [MongoTheory]
        [MemberData(nameof(AdminRoutes))]
        public async Task AdminRoute_GuestGets401_MemberAndChefGet403(string method, string path)
        {
            var http = new HttpMethod(method);
            object? body = method is "POST" or "PATCH" ? new { } : null;
            Assert.Equal(HttpStatusCode.Unauthorized, (await H.CallAsync(http, path, null, body)).Status);
            Assert.Equal(HttpStatusCode.Forbidden, (await H.CallAsync(http, path, await H.UserAsync(), body)).Status);
            Assert.Equal(HttpStatusCode.Forbidden, (await H.CallAsync(http, path, await H.ChefAsync(), body)).Status);
        }

        public static IEnumerable<object[]> MemberRoutes() => new[]
        {
            new object[] { "PUT", "/chefs/me/profile" },
            new object[] { "GET", "/chefs/me/profile" },
            new object[] { "POST", "/chef-applications" },
            new object[] { "GET", "/chef-applications/me" },
            new object[] { "POST", "/restaurants" },
            new object[] { "POST", $"/restaurants/{AnyId}/reviews" },
            new object[] { "GET", "/users/me/restaurant-suggestions" },
            new object[] { "POST", $"/videos/{AnyId}/extraction" }
        };

        [MongoTheory]
        [MemberData(nameof(MemberRoutes))]
        public async Task SignedInRoute_GuestGets401(string method, string path)
        {
            var result = await H.CallAsync(new HttpMethod(method), path, null, method is "POST" or "PUT" ? new { } : null);
            AssertError(result, HttpStatusCode.Unauthorized, "unauthorized");
        }

        [MongoTheory]
        [InlineData("/chefs")]
        [InlineData("/restaurants")]
        [InlineData("/restaurants/suggested?food=bun")]
        [InlineData("/search?q=bun")]
        [InlineData("/search/suggest?q=bun")]
        [InlineData("/search/discover")]
        [InlineData("/ads/feed")]
        public async Task PublicRoute_GuestReads(string path)
        {
            await H.OkAsync(H.GetAsync(path));
        }

        [MongoFact]
        public async Task ChefProfile_NonChefGets403NotChef()
        {
            var member = await H.UserAsync();
            AssertError(await H.GetAsync("/chefs/me/profile", member), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.PutAsync("/chefs/me/profile", member, ContentApi.Profile()), HttpStatusCode.Forbidden, "not_chef");
            AssertError(await H.GetAsync("/chefs/me/profile", await H.AdminAsync()), HttpStatusCode.Forbidden, "not_chef");
        }
    }

    public class Sprint11_ChefTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_ChefTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private Task<ApiResult> Submit(TestUser u) => H.PostAsync("/chef-applications", u, ContentApi.Application());

        [MongoFact]
        public async Task Application_FullLoop_RejectThenApprove_ThenChefIsBookable()
        {
            var member = await H.UserAsync(name: "Minh Anh");
            var admin = await H.AdminAsync();

            var submitted = await Submit(member);
            Assert.Equal(HttpStatusCode.Created, submitted.Status);
            Assert.Equal("pending", submitted.Data.Str("status"));
            Assert.Equal("Minh Anh", submitted.Data.Str("fullName"));
            var firstId = submitted.Id();
            Assert.Equal("Chứng chỉ Dinh dưỡng", submitted.Data.GetProperty("certificates")[0].Str("name"));

            AssertError(await Submit(member), HttpStatusCode.Conflict, "already_pending");
            Assert.Equal("pending", (await H.OkAsync(H.GetAsync("/chef-applications/me", member))).Data.Str("status"));
            Assert.Contains(firstId, (await H.OkAsync(H.GetAsync("/admin/chef-applications?status=pending", admin))).Ids());

            AssertError(await H.PostAsync($"/admin/chef-applications/{firstId}/review", admin, new { decision = "rejected" }), HttpStatusCode.BadRequest, "note_required");
            AssertError(await H.PostAsync($"/admin/chef-applications/{firstId}/review", admin, new { decision = "Approve" }), HttpStatusCode.BadRequest, "validation");

            var rejected = await H.OkAsync(H.PostAsync($"/admin/chef-applications/{firstId}/review", admin, new { decision = "rejected", note = "Thiếu chứng chỉ gốc" }));
            Assert.Equal("rejected", rejected.Data.Str("status"));
            Assert.Equal("Lê Minh Quân", rejected.Data.Str("reviewedBy"));
            var mine = (await H.OkAsync(H.GetAsync("/chef-applications/me", member))).Data;
            Assert.Equal("rejected", mine.Str("status"));
            Assert.Equal("Thiếu chứng chỉ gốc", mine.Str("rejectReason"));

            // App đọc trạng thái ở GET /users/me.
            var me = (await H.OkAsync(H.GetAsync("/users/me", member))).Data.GetProperty("chefApplication");
            Assert.Equal("rejected", me.Str("status"));
            Assert.Equal("Thiếu chứng chỉ gốc", me.Str("rejectReason"));

            Assert.Equal("User", (await H.Db.Users.Find(u => u.Id == member.Id).FirstAsync()).Role);
            AssertError(await H.PostAsync($"/admin/chef-applications/{firstId}/review", admin, new { decision = "approved" }), HttpStatusCode.Conflict, "already_reviewed");

            var secondId = (await Submit(member)).Id();
            var approved = await H.OkAsync(H.PostAsync($"/admin/chef-applications/{secondId}/review", admin, new { decision = "approved", note = "" }));
            Assert.Equal("approved", approved.Data.Str("status"));
            Assert.Equal("Chef", (await H.Db.Users.Find(u => u.Id == member.Id).FirstAsync()).Role);

            // Vai trò đổi: token cũ nhận 401 để app gọi refresh; token mới mang vai trò Chef dùng được ngay, không phải chờ cache.
            Assert.Equal(HttpStatusCode.Unauthorized, (await H.GetAsync("/users/me", member)).Status);
            var chef = new TestUser(member.Id, ContentApi.Token(member.Id, "Chef"), member.Name);
            Assert.Equal("approved", (await H.OkAsync(H.GetAsync("/users/me", chef))).Data.GetProperty("chefApplication").Str("status"));

            // Chưa đặt giá: hiện "Chờ báo giá".
            var listed = (await H.OkAsync(H.GetAsync("/chefs?q=minh anh"))).Data.EnumerateArray().Single();
            Assert.Equal(0, listed.GetProperty("pricePerDay").GetInt64());
            Assert.Equal(member.Id, listed.Str("userId"));
            Assert.Equal("Ẩm thực chay Việt", listed.Str("specialty"));
            Assert.Equal(7, listed.GetProperty("yearsExperience").GetInt32());
            Assert.Equal("Đà Nẵng", listed.Str("city"));
            Assert.False(listed.TryGetProperty("bio", out _));
            Assert.False(listed.TryGetProperty("certificates", out _));

            var detail = (await H.OkAsync(H.GetAsync($"/chefs/{listed.Str("id")}"))).Data;
            Assert.StartsWith("Tôi nấu ăn chay", detail.Str("bio"));
            Assert.Equal("Chứng chỉ Dinh dưỡng", detail.GetProperty("certificates")[0].GetString());

            var saved = await H.OkAsync(H.PutAsync("/chefs/me/profile", chef, ContentApi.Profile()));
            Assert.Equal(listed.Str("id"), saved.Id());
            Assert.Equal(150_000, saved.Data.GetProperty("pricePerDay").GetInt64());

            var booker = await H.UserAsync();
            var created = await H.PostAsync("/bookings", booker, BookingBody(saved.Id()));
            Assert.Equal(HttpStatusCode.Created, created.Status);
            Assert.Equal(member.Id, created.Data.GetProperty("chef").Str("id"));

            var counts = (await H.OkAsync(H.GetAsync("/admin/chef-applications/counts", admin))).Data;
            Assert.True(counts.GetProperty("approved").GetInt64() >= 1);
            Assert.True(counts.GetProperty("rejected").GetInt64() >= 1);

            var overview = (await H.OkAsync(H.GetAsync("/admin/overview", admin))).Data;
            Assert.Contains(overview.GetProperty("recentActions").EnumerateArray(), a => a.Str("action") == "duyệt chuyên gia" && a.Str("target") == "Minh Anh");
        }

        [MongoFact]
        public async Task Application_AdminAndChefCannotApply_AdminNeverDemoted()
        {
            AssertError(await Submit(await H.AdminAsync()), HttpStatusCode.Forbidden, "not_member");
            AssertError(await Submit(await H.ChefAsync()), HttpStatusCode.Conflict, "already_chef");

            // Đơn tạo từ trước khi người này được nâng thành admin.
            var promoted = await H.AdminAsync("Quản trị mới");
            var id = ObjectId.GenerateNewId().ToString();
            await H.Db.Database.GetCollection<ChefApplication>("ChefApplications").InsertOneAsync(new ChefApplication
            {
                Id = id, UserId = promoted.Id, City = "Huế", Bio = ContentApi.Bio, Specialties = new List<string> { "Thực dưỡng" }, YearsExperience = 1
            });
            await H.OkAsync(H.PostAsync($"/admin/chef-applications/{id}/review", await H.AdminAsync(), new { decision = "approved" }));
            Assert.Equal("Admin", (await H.Db.Users.Find(u => u.Id == promoted.Id).FirstAsync()).Role);
        }

        [MongoFact]
        public async Task Application_Validation()
        {
            var member = await H.UserAsync();
            AssertError(await H.PostAsync("/chef-applications", member, new { yearsExperience = 1, city = "Huế", bio = ContentApi.Bio, certificates = new[] { "a" } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/chef-applications", member, new { specialties = new[] { "a" }, yearsExperience = 1, city = "Huế", bio = "ngắn", certificates = new[] { "a" } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/chef-applications", member, new { specialties = new[] { "a" }, yearsExperience = -1, city = "Huế", bio = ContentApi.Bio, certificates = new[] { "a" } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/chef-applications", member, new { specialties = new[] { "a" }, yearsExperience = 1, city = "", bio = ContentApi.Bio, certificates = new[] { "a" } }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/chef-applications", member, new { specialties = new[] { "a" }, yearsExperience = 1, city = "Huế", bio = ContentApi.Bio }), HttpStatusCode.BadRequest, "validation");
            Assert.Equal("none", (await H.OkAsync(H.GetAsync("/chef-applications/me", member))).Data.Str("status"));
        }

        [MongoFact]
        public async Task Application_DoubleSubmit_OnlyOneRow()
        {
            var member = await H.UserAsync();
            var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => Submit(member)));
            Assert.Equal(1, results.Count(r => r.Status == HttpStatusCode.Created));
            Assert.Equal(7, results.Count(r => r.Status == HttpStatusCode.Conflict && r.Code == "already_pending"));
        }

        [MongoFact]
        public async Task Application_TwoAdminsDecideTogether_OneWins()
        {
            var member = await H.UserAsync();
            var id = (await Submit(member)).Id();
            var a = await H.AdminAsync();
            var b = await H.AdminAsync();
            var results = await Task.WhenAll(
                H.PostAsync($"/admin/chef-applications/{id}/review", a, new { decision = "approved" }),
                H.PostAsync($"/admin/chef-applications/{id}/review", b, new { decision = "rejected", note = "Thiếu hồ sơ" }));
            Assert.Single(results, r => r.Status == HttpStatusCode.OK);
            Assert.Single(results, r => r.Status == HttpStatusCode.Conflict && r.Code == "already_reviewed");

            var winner = results.Single(r => r.Status == HttpStatusCode.OK).Data.Str("status");
            var role = (await H.Db.Users.Find(u => u.Id == member.Id).FirstAsync()).Role;
            Assert.Equal(winner == "approved" ? "Chef" : "User", role);
        }

        [MongoFact]
        public async Task Application_LockedOrUnknownApplicant_NotApproved()
        {
            var member = await H.UserAsync();
            var id = (await Submit(member)).Id();
            var admin = await H.AdminAsync();
            await H.Db.Users.UpdateOneAsync(u => u.Id == member.Id, Builders<User>.Update.Set(u => u.Status, DomainLayer.Enums.GeneralEnum.UserStatusEnum.Locked));
            AssertError(await H.PostAsync($"/admin/chef-applications/{id}/review", admin, new { decision = "approved" }), HttpStatusCode.Conflict, "applicant_inactive");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/admin/chef-applications/507f1f77bcf86cd799439011/review", admin, new { decision = "approved" })).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/admin/chef-applications/khong-phai-id/review", admin, new { decision = "approved" })).Status);
        }

        [MongoFact]
        public async Task Profile_MissingIs404_ThenUpsert_ThenValidation()
        {
            var chef = await H.ChefAsync();
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync("/chefs/me/profile", chef)).Status);

            var first = await H.OkAsync(H.PutAsync("/chefs/me/profile", chef, ContentApi.Profile()));
            var second = await H.OkAsync(H.PutAsync("/chefs/me/profile", chef, ContentApi.Profile(min: 5, max: 10)));
            Assert.Equal(first.Id(), second.Id());
            var read = (await H.OkAsync(H.GetAsync("/chefs/me/profile", chef))).Data;
            Assert.Equal(5, read.GetProperty("minPlanDays").GetInt32());
            Assert.Equal(chef.Id, read.Str("userId"));

            foreach (var bad in new object[]
            {
                ContentApi.Profile(min: 2),
                ContentApi.Profile(max: 31),
                ContentApi.Profile(min: 10, max: 5),
                ContentApi.Profile(price: 29_999),
                ContentApi.Profile(feedback: 5_000_001),
                ContentApi.Profile(price: 200_000, feedback: 100_000),
                new { specialty = "", bio = ContentApi.Bio, pricePerDay = 150_000, feedbackPricePerDay = 150_000, minPlanDays = 3, maxPlanDays = 30, acceptingBookings = true },
                new { specialty = "a", bio = "ngắn", pricePerDay = 150_000, feedbackPricePerDay = 150_000, minPlanDays = 3, maxPlanDays = 30, acceptingBookings = true },
                new { specialty = "a", bio = ContentApi.Bio, pricePerDay = 150_000, feedbackPricePerDay = 150_000, minPlanDays = 3, maxPlanDays = 30 }
            })
            {
                AssertError(await H.PutAsync("/chefs/me/profile", chef, bad), HttpStatusCode.BadRequest, "validation");
            }
        }

        [MongoFact]
        public async Task Directory_FiltersIgnoreDiacritics_HidesInactive_StatsAreReal()
        {
            var chef = await H.ChefAsync("Trần Thị Ưng");
            var id = await H.ChefWithProfileAsync(chef);
            var locked = await H.ChefAsync("Người Bị Khoá");
            var lockedProfile = await H.ChefWithProfileAsync(locked);

            Assert.Contains(id, (await H.OkAsync(H.GetAsync("/chefs?q=tran thi ung"))).Ids());
            Assert.Contains(id, (await H.OkAsync(H.GetAsync("/chefs?specialty=am thuc chay hue"))).Ids());
            Assert.DoesNotContain(id, (await H.OkAsync(H.GetAsync("/chefs?specialty=khong co"))).Ids());

            await H.Db.Users.UpdateOneAsync(u => u.Id == locked.Id, Builders<User>.Update.Set(u => u.Status, DomainLayer.Enums.GeneralEnum.UserStatusEnum.Locked));
            Assert.DoesNotContain(lockedProfile, (await H.OkAsync(H.GetAsync("/chefs"))).Ids());
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/chefs/{lockedProfile}")).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync("/chefs/khong-phai-id")).Status);

            var fresh = (await H.OkAsync(H.GetAsync($"/chefs/{id}"))).Data;
            Assert.Equal(0, fresh.GetProperty("rating").GetDouble());
            Assert.Equal(0, fresh.GetProperty("reviewCount").GetInt32());
            Assert.Equal(0, fresh.GetProperty("consultCount").GetInt32());

            await H.Db.Bookings.InsertOneAsync(new ChefBooking
            {
                Id = ObjectId.GenerateNewId().ToString(),
                ChefId = chef.Id,
                MemberId = ObjectId.GenerateNewId().ToString(),
                Status = BookingStatuses.Completed,
                Days = new List<BookingPlanDay>
                {
                    new() { DayIndex = 1, Feedback = new DayFeedback { Rating = 5 } },
                    new() { DayIndex = 2, Feedback = new DayFeedback { Rating = 4 } },
                    new() { DayIndex = 3 }
                }
            });
            var rated = (await H.OkAsync(H.GetAsync($"/chefs/{id}"))).Data;
            Assert.Equal(4.5, rated.GetProperty("rating").GetDouble());
            Assert.Equal(2, rated.GetProperty("reviewCount").GetInt32());
            Assert.Equal(1, rated.GetProperty("consultCount").GetInt32());
        }

        [MongoFact]
        public async Task Booking_ResolvesProfileId_AppliesAcceptingAndDayLimits()
        {
            var chef = await H.ChefAsync("Lê Quang Tâm");
            var profileId = await H.ChefWithProfileAsync(chef, ContentApi.Profile(min: 5, max: 7));
            var member = await H.UserAsync();

            var tooShort = await H.PostAsync("/bookings", member, BookingBody(profileId, days: 4));
            AssertError(tooShort, HttpStatusCode.BadRequest, "validation");
            Assert.Contains("Lê Quang Tâm nhận kế hoạch từ 5 đến 7 ngày", tooShort.Root.Str("message"));
            AssertError(await H.PostAsync("/bookings", member, BookingBody(profileId, days: 8)), HttpStatusCode.BadRequest, "validation");
            // Dùng id user cũng không lách được giới hạn của hồ sơ.
            AssertError(await H.PostAsync("/bookings", member, BookingBody(chef.Id, days: 4)), HttpStatusCode.BadRequest, "validation");

            var ok = await H.PostAsync("/bookings", member, BookingBody(profileId, days: 5));
            Assert.Equal(HttpStatusCode.Created, ok.Status);
            Assert.Equal(chef.Id, ok.Data.GetProperty("chef").Str("id"));

            AssertError(await H.PostAsync("/bookings", chef, BookingBody(profileId, days: 5)), HttpStatusCode.Conflict, "self_booking");

            await H.OkAsync(H.PutAsync("/chefs/me/profile", chef, ContentApi.Profile(min: 5, max: 7, accepting: false)));
            AssertError(await H.PostAsync("/bookings", member, BookingBody(profileId, days: 5)), HttpStatusCode.Conflict, "not_accepting");
            AssertError(await H.PostAsync("/bookings", member, BookingBody(chef.Id, days: 5)), HttpStatusCode.Conflict, "not_accepting");

            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/bookings", member, BookingBody("507f1f77bcf86cd799439011", days: 5))).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/bookings", member, BookingBody("khong-phai-id", days: 5))).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/bookings", member, BookingBody(member.Id, days: 5))).Status);

            await H.Db.Users.UpdateOneAsync(u => u.Id == chef.Id, Builders<User>.Update.Set(u => u.Status, DomainLayer.Enums.GeneralEnum.UserStatusEnum.Banned));
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/bookings", member, BookingBody(profileId, days: 5))).Status);
        }

        [MongoFact]
        public async Task DeliveredPlanDays_ReachMemberSuggestions_OnlyForThatMember()
        {
            var paid = await H.PaidAsync();
            await H.DeliverAllAsync(paid);

            var rows = (await H.OkAsync(H.GetAsync("/meal-plans/chef-suggestions", paid.Member))).Data;
            Assert.True(rows.GetArrayLength() > 0);
            var first = rows[0];
            Assert.Equal(paid.Chef.Id, first.Str("chefId"));
            Assert.Equal(paid.Chef.Name, first.Str("chefName"));
            Assert.True(ObjectId.TryParse(first.Str("id"), out _));
            Assert.False(string.IsNullOrEmpty(first.GetProperty("recipe").Str("name")));

            Assert.Equal(0, (await H.OkAsync(H.GetAsync("/meal-plans/chef-suggestions", await H.UserAsync()))).Data.GetArrayLength());
            Assert.Equal(HttpStatusCode.Unauthorized, (await H.GetAsync("/meal-plans/chef-suggestions")).Status);
        }
    }

    public class Sprint11_RestaurantTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_RestaurantTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private static string Unique(string name) => $"{name} {ObjectId.GenerateNewId().ToString()[^8..]}";

        [MongoFact]
        public async Task Suggestion_VisibleToAuthorAndAdminOnly_UntilApproved()
        {
            var author = await H.UserAsync(name: "Minh Anh");
            var stranger = await H.UserAsync();
            var admin = await H.AdminAsync();
            var name = Unique("Quán Chay An Lạc");

            var created = await H.PostAsync("/restaurants", author, new { name, address = "12 Lê Lợi, Quận 1", latitude = 10.78, longitude = 106.7 });
            Assert.Equal(HttpStatusCode.Created, created.Status);
            var id = created.Id();
            Assert.Equal("Pending", created.Data.Str("status"));
            Assert.False(created.Data.GetProperty("isVeganCertified").GetBoolean());
            Assert.Equal("Minh Anh", created.Data.GetProperty("createdBy").Str("fullName"));
            Assert.Equal(JsonValueKind.Null, created.Data.GetProperty("averageRating").ValueKind);

            Assert.DoesNotContain(id, (await H.OkAsync(H.GetAsync("/restaurants"))).Ids());
            foreach (var path in new[] { $"/restaurants/{id}", $"/restaurants/{id}/media", $"/restaurants/{id}/reviews" })
            {
                Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync(path)).Status);
                Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync(path, stranger)).Status);
                await H.OkAsync(H.GetAsync(path, author));
                await H.OkAsync(H.GetAsync(path, admin));
            }

            AssertError(await H.PostAsync($"/restaurants/{id}/reviews", author, new { rating = 5, comment = "Quán rất ngon và sạch sẽ." }), HttpStatusCode.Conflict, "not_public");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/restaurants/{id}/reviews", stranger, new { rating = 5, comment = "Quán rất ngon và sạch sẽ." })).Status);

            Assert.Equal(id, (await H.OkAsync(H.GetAsync("/users/me/restaurant-suggestions", author))).Ids().Single());
            Assert.Empty((await H.OkAsync(H.GetAsync("/users/me/restaurant-suggestions", stranger))).Ids());

            AssertError(await H.PatchAsync($"/admin/restaurants/{id}", admin, new { isVeganCertified = true }), HttpStatusCode.Conflict, "not_approved");

            var approved = await H.OkAsync(H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Approve" }));
            Assert.Equal("Approved", approved.Data.Str("status"));
            Assert.Equal("Lê Minh Quân", approved.Data.Str("reviewedBy"));

            var pub = (await H.OkAsync(H.GetAsync($"/restaurants/{id}?lat=10.78&lng=106.7"))).Data;
            Assert.Equal(0, pub.GetProperty("distanceKm").GetDouble());
            Assert.Equal(author.Id, pub.Str("createdBy"));
            Assert.Equal("Minh Anh", pub.Str("createdByName"));
            Assert.Contains(id, (await H.OkAsync(H.GetAsync("/restaurants"))).Ids());

            var certified = await H.OkAsync(H.PatchAsync($"/admin/restaurants/{id}", admin, new { isVeganCertified = true }));
            Assert.True(certified.Data.GetProperty("isVeganCertified").GetBoolean());
            Assert.Contains(id, (await H.OkAsync(H.GetAsync("/restaurants?certifiedOnly=true"))).Ids());

            AssertError(await H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Reject" }), HttpStatusCode.BadRequest, "reason_required");
            AssertError(await H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Reject", reason = new string('x', 501) }), HttpStatusCode.BadRequest, "reason_too_long");
            AssertError(await H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Delete" }), HttpStatusCode.BadRequest, "validation");

            var rejected = await H.OkAsync(H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Reject", reason = "Không phải quán chay" }));
            Assert.Equal("Rejected", rejected.Data.Str("status"));
            Assert.Equal("Không phải quán chay", rejected.Data.Str("rejectionReason"));
            Assert.False(rejected.Data.GetProperty("isVeganCertified").GetBoolean());
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/restaurants/{id}")).Status);

            // Duyệt lại được từ bất kỳ trạng thái nào.
            await H.OkAsync(H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Approve" }));
            Assert.Equal(JsonValueKind.Null, (await H.OkAsync(H.GetAsync("/users/me/restaurant-suggestions", author))).Data[0].GetProperty("rejectionReason").ValueKind);
        }

        [MongoFact]
        public async Task Suggestion_Validation()
        {
            var u = await H.UserAsync();
            object Body(string name = "Quán Hợp Lệ", string address = "12 Lê Lợi, Quận 1", double? lat = null, double? lng = null, object? media = null) =>
                new { name, address, latitude = lat, longitude = lng, media };

            AssertError(await H.PostAsync("/restaurants", u, Body(name: "ab")), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(name: new string('x', 121))), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(address: "ngắn")), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(address: new string('x', 256))), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(lat: 10)), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(lat: 91, lng: 106)), HttpStatusCode.BadRequest, "validation");

            var someone = await H.UserAsync();
            await H.Db.MediaAssets.InsertOneAsync(new MediaAsset { Id = ObjectId.GenerateNewId().ToString(), OwnerId = someone.Id, Url = "/uploads/images/nguoi-khac.jpg", PublicId = ObjectId.GenerateNewId().ToString(), MediaType = "Image" });
            AssertError(await H.PostAsync("/restaurants", u, Body(media: new[] { new { mediaType = "Image", mediaUrl = "/uploads/images/nguoi-khac.jpg" } })), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(media: new[] { new { mediaType = "Image", mediaUrl = "https://evil.test/a.jpg" } })), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(media: new[] { new { mediaType = "Audio", mediaUrl = "x" } })), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(media: Enumerable.Range(0, 6).Select(_ => new { mediaType = "Image", mediaUrl = "x" }).ToArray())), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/restaurants", u, Body(media: Enumerable.Range(0, 2).Select(_ => new { mediaType = "Video", mediaUrl = "x" }).ToArray())), HttpStatusCode.BadRequest, "validation");
        }

        [MongoFact]
        public async Task Suggestion_MediaOfCaller_IsStoredAndReturned()
        {
            var u = await H.UserAsync(name: "Minh Anh");
            var admin = await H.AdminAsync();
            const string url = "/uploads/images/cua-toi.jpg";
            await H.Db.MediaAssets.InsertOneAsync(new MediaAsset { Id = ObjectId.GenerateNewId().ToString(), OwnerId = u.Id, Url = url, PublicId = ObjectId.GenerateNewId().ToString(), MediaType = "Image" });

            var id = (await H.OkAsync(H.PostAsync("/restaurants", u, new { name = Unique("Quán Ảnh"), address = "12 Lê Lợi, Quận 1", media = new[] { new { mediaType = "Image", mediaUrl = url } } }))).Id();
            var row = (await H.OkAsync(H.GetAsync("/admin/restaurants?status=Pending", admin))).Data.EnumerateArray().Single(r => r.Str("id") == id);
            var media = row.GetProperty("media")[0];
            Assert.Equal(url, media.Str("mediaUrl"));
            Assert.Equal("Minh Anh", media.GetProperty("uploadedBy").Str("fullName"));
            Assert.True(ObjectId.TryParse(media.Str("id"), out _));

            await H.OkAsync(H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Approve" }));
            Assert.Equal(url, (await H.OkAsync(H.GetAsync($"/restaurants/{id}/media"))).Data[0].Str("mediaUrl"));
        }

        [MongoFact]
        public async Task Duplicate_IgnoresDiacritics_RejectedMayResubmit_ConcurrentOnlyOne()
        {
            var u = await H.UserAsync();
            var admin = await H.AdminAsync();
            var stem = ObjectId.GenerateNewId().ToString()[^8..];
            var id = (await H.OkAsync(H.PostAsync("/restaurants", u, new { name = $"Quán Chay Đại {stem}", address = "12 Lê Lợi, Quận Một" }))).Id();

            AssertError(await H.PostAsync("/restaurants", await H.UserAsync(), new { name = $"quan chay dai {stem}", address = "12 le loi, quan mot" }), HttpStatusCode.Conflict, "duplicate");

            await H.OkAsync(H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Reject", reason = "Thiếu thông tin" }));
            var resent = await H.PostAsync("/restaurants", u, new { name = $"Quán Chay Đại {stem}", address = "12 Lê Lợi, Quận Một" });
            Assert.Equal(HttpStatusCode.Created, resent.Status);

            // Duyệt lại quán cũ khi đã có quán trùng: không được tạo hai quán giống nhau.
            AssertError(await H.PostAsync($"/admin/restaurants/{id}/review", admin, new { decision = "Approve" }), HttpStatusCode.Conflict, "duplicate");

            var name = Unique("Quán Bấm Đúp");
            var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => H.PostAsync("/restaurants", u, new { name, address = "99 Nguyễn Huệ, Quận 1" })));
            Assert.Equal(1, results.Count(r => r.Status == HttpStatusCode.Created));
            Assert.Equal(7, results.Count(r => r.Status == HttpStatusCode.Conflict && r.Code == "duplicate"));

            // Xoá quán xong thì gợi ý lại được.
            var removable = results.Single(r => r.Status == HttpStatusCode.Created).Id();
            await H.OkAsync(H.DeleteAsync($"/admin/restaurants/{removable}", admin));
            Assert.Equal(HttpStatusCode.Created, (await H.PostAsync("/restaurants", u, new { name, address = "99 Nguyễn Huệ, Quận 1" })).Status);
        }

        [MongoFact]
        public async Task Reviews_OnePerMember_RatingIsReal_AdminCanRemove()
        {
            var admin = await H.AdminAsync();
            var author = await H.UserAsync();
            var id = await H.ApprovedRestaurantAsync(admin, author, Unique("Quán Đánh Giá"));
            var a = await H.UserAsync(name: "Khách A");
            var b = await H.UserAsync(name: "Khách B");

            AssertError(await H.PostAsync($"/restaurants/{id}/reviews", a, new { rating = 6, comment = "Quán rất ngon và sạch sẽ." }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/restaurants/{id}/reviews", a, new { rating = 5, comment = "ngắn" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/restaurants/{id}/reviews", a, new { rating = 5, comment = new string('x', 501) }), HttpStatusCode.BadRequest, "validation");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/restaurants/507f1f77bcf86cd799439011/reviews", a, new { rating = 5, comment = "Quán rất ngon và sạch sẽ." })).Status);

            var first = await H.OkAsync(H.PostAsync($"/restaurants/{id}/reviews", a, new { rating = 2, comment = "Bún riêu hơi mặn nhưng ổn." }));
            Assert.Equal(JsonValueKind.Null, first.Data.GetProperty("updatedAt").ValueKind);
            var again = await H.OkAsync(H.PostAsync($"/restaurants/{id}/reviews", a, new { rating = 4, comment = "Quay lại thấy bún riêu ngon hơn." }));
            Assert.Equal(first.Id(), again.Id());
            Assert.NotEqual(JsonValueKind.Null, again.Data.GetProperty("updatedAt").ValueKind);
            Assert.Equal("Khách A", again.Data.GetProperty("user").Str("fullName"));

            var bReview = await H.OkAsync(H.PostAsync($"/restaurants/{id}/reviews", b, new { rating = 5, comment = "Phở chay rất đậm đà." }));
            var detail = (await H.OkAsync(H.GetAsync($"/restaurants/{id}"))).Data;
            Assert.Equal(4.5, detail.GetProperty("averageRating").GetDouble());
            Assert.Equal(2, detail.GetProperty("reviewCount").GetInt32());

            var list = await H.OkAsync(H.GetAsync($"/restaurants/{id}/reviews"));
            Assert.Equal(2, list.Data.GetArrayLength());
            Assert.Equal(2, (await H.OkAsync(H.GetAsync($"/admin/restaurants/{id}/reviews", admin))).Data.GetArrayLength());

            await H.OkAsync(H.DeleteAsync($"/admin/reviews/{bReview.Id()}", admin));
            Assert.Equal(HttpStatusCode.NotFound, (await H.DeleteAsync($"/admin/reviews/{bReview.Id()}", admin)).Status);
            Assert.Equal(4, (await H.OkAsync(H.GetAsync($"/restaurants/{id}"))).Data.GetProperty("averageRating").GetDouble());

            // Bấm đúp vẫn chỉ một đánh giá.
            var c = await H.UserAsync();
            await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => H.PostAsync($"/restaurants/{id}/reviews", c, new { rating = 3, comment = "Bấm liên tục nhiều lần." })));
            Assert.Equal(2, (await H.OkAsync(H.GetAsync($"/restaurants/{id}"))).Data.GetProperty("reviewCount").GetInt32());

            await H.OkAsync(H.DeleteAsync($"/admin/restaurants/{id}", admin));
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/restaurants/{id}")).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.DeleteAsync($"/admin/restaurants/{id}", admin)).Status);
            Assert.DoesNotContain(id, (await H.OkAsync(H.GetAsync("/admin/restaurants", admin))).Ids());
        }

        [MongoFact]
        public async Task PublicList_QueryDistanceRadiusSortAndSuggested()
        {
            var admin = await H.AdminAsync();
            var author = await H.UserAsync();
            var dish = "bunmangkho" + ObjectId.GenerateNewId().ToString()[^6..];
            var near = await H.ApprovedRestaurantAsync(admin, author, Unique("Gần Nhà"), lat: 10.0, lng: 106.0);
            var far = await H.ApprovedRestaurantAsync(admin, author, Unique("Xa Nhà"), lat: 10.5, lng: 106.0);
            var noCoord = await H.ApprovedRestaurantAsync(admin, author, Unique("Không Toạ Độ"), lat: null, lng: null);

            foreach (var (id, rating) in new[] { (near, 3), (far, 5), (noCoord, 4) })
                await H.OkAsync(H.PostAsync($"/restaurants/{id}/reviews", await H.UserAsync(), new { rating, comment = $"Món {dish} ở đây rất được." }));

            var byDistance = (await H.OkAsync(H.GetAsync($"/restaurants?lat=10&lng=106&q={dish}"))).Ids();
            Assert.Equal(new[] { near, far, noCoord }, byDistance);

            var nearRow = (await H.OkAsync(H.GetAsync($"/restaurants?lat=10&lng=106&q={dish}"))).Data[0];
            Assert.Equal(0, nearRow.GetProperty("distanceKm").GetDouble());
            var noCoordRow = (await H.OkAsync(H.GetAsync($"/restaurants?lat=10&lng=106&q={dish}"))).Data[2];
            Assert.Equal(JsonValueKind.Null, noCoordRow.GetProperty("distanceKm").ValueKind);
            Assert.Equal(JsonValueKind.Null, noCoordRow.GetProperty("latitude").ValueKind);

            Assert.Equal(new[] { far, noCoord, near }, (await H.OkAsync(H.GetAsync($"/restaurants?sort=rating&q={dish}"))).Ids());
            Assert.Equal(new[] { near }, (await H.OkAsync(H.GetAsync($"/restaurants?lat=10&lng=106&radiusKm=10&q={dish}"))).Ids());
            Assert.Equal(new[] { far, noCoord }.Length, (await H.OkAsync(H.GetAsync($"/restaurants?sort=rating&limit=2&q={dish}"))).Ids().Count);

            Assert.Equal(new[] { near, far, noCoord }, (await H.OkAsync(H.GetAsync($"/restaurants/suggested?food={dish}&lat=10&lng=106"))).Ids());
            Assert.Equal(2, (await H.OkAsync(H.GetAsync($"/restaurants/suggested?food={dish}&limit=2"))).Ids().Count);
            Assert.Empty((await H.OkAsync(H.GetAsync("/restaurants/suggested"))).Ids());

            AssertError(await H.GetAsync("/restaurants?lat=10"), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.GetAsync("/restaurants?lat=100&lng=10"), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.GetAsync("/restaurants?sort=bogus"), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.GetAsync("/restaurants?radiusKm=-1"), HttpStatusCode.BadRequest, "validation");
        }

        [MongoFact]
        public async Task PublicList_DiacriticsAndAddressShortForms()
        {
            var admin = await H.AdminAsync();
            var stem = ObjectId.GenerateNewId().ToString()[^8..];
            var id = await H.ApprovedRestaurantAsync(admin, await H.UserAsync(), $"Bún Riêu Hạnh Tâm {stem}", address: $"152 Đinh Tiên Hoàng, Q.1 {stem}");
            Assert.Contains(id, (await H.OkAsync(H.GetAsync($"/restaurants?q=bun rieu {stem}"))).Ids());
            Assert.Contains(id, (await H.OkAsync(H.GetAsync($"/restaurants?q=dinh tien hoang quan 1 {stem}"))).Ids());
            Assert.Empty((await H.OkAsync(H.GetAsync($"/restaurants?q=khong khop {stem}"))).Ids());
        }

        [MongoFact]
        public async Task AdminRoutes_UnknownIdIs404_MissingFieldIs400()
        {
            var admin = await H.AdminAsync();
            const string missing = "507f1f77bcf86cd799439011";
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/admin/restaurants/{missing}/review", admin, new { decision = "Approve" })).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PatchAsync($"/admin/restaurants/{missing}", admin, new { isVeganCertified = true })).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/admin/restaurants/{missing}/reviews", admin)).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/admin/restaurants/khong-phai-id/reviews", admin)).Status);
            AssertError(await H.PatchAsync($"/admin/restaurants/{missing}", admin, new { }), HttpStatusCode.BadRequest, "validation");
        }

        [MongoFact]
        public async Task AdminList_Filters()
        {
            var admin = await H.AdminAsync();
            var author = await H.UserAsync(name: "Tác Giả Lọc");
            var stem = ObjectId.GenerateNewId().ToString()[^8..];
            var pending = (await H.OkAsync(H.PostAsync("/restaurants", author, new { name = $"Lọc Chờ {stem}", address = "12 Lê Lợi, Quận 1" }))).Id();
            var approved = await H.ApprovedRestaurantAsync(admin, author, $"Lọc Duyệt {stem}");
            await H.OkAsync(H.PatchAsync($"/admin/restaurants/{approved}", admin, new { isVeganCertified = true }));
            var adminRow = ObjectId.GenerateNewId().ToString();
            await H.Db.Database.GetCollection<Restaurant>("Restaurants").InsertOneAsync(new Restaurant { Id = adminRow, Name = $"Lọc Ban QT {stem}", Address = "Địa chỉ của ban quản trị", Status = RestaurantStatuses.Approved });

            Assert.Equal(3, (await H.OkAsync(H.GetAsync($"/admin/restaurants?search=loc {stem}", admin))).Ids().Count);
            Assert.Equal(new[] { pending }, (await H.OkAsync(H.GetAsync($"/admin/restaurants?status=Pending&search=loc {stem}", admin))).Ids());
            Assert.Equal(new[] { approved }, (await H.OkAsync(H.GetAsync($"/admin/restaurants?certified=certified&search=loc {stem}", admin))).Ids());
            Assert.Equal(new[] { adminRow }, (await H.OkAsync(H.GetAsync($"/admin/restaurants?source=admin&search=loc {stem}", admin))).Ids());
            var row = (await H.OkAsync(H.GetAsync($"/admin/restaurants?source=admin&search=loc {stem}", admin))).Data[0];
            Assert.Equal(JsonValueKind.Null, row.GetProperty("createdBy").ValueKind);
            Assert.Equal(2, (await H.OkAsync(H.GetAsync($"/admin/restaurants?source=user&search=loc {stem}", admin))).Ids().Count);
            AssertError(await H.GetAsync("/admin/restaurants?status=pending", admin), HttpStatusCode.BadRequest, "validation");
        }
    }

    public class Sprint11_GeoTests : IClassFixture<ContentFactory>, IClassFixture<GeoConfiguredFactory>
    {
        private readonly CommerceHarness Off;
        private readonly CommerceHarness On;
        private readonly GeoConfiguredFactory _on;

        public Sprint11_GeoTests(ContentFactory off, GeoConfiguredFactory on)
        {
            Off = new CommerceHarness(off);
            On = new CommerceHarness(on);
            _on = on;
        }

        [MongoFact]
        public async Task NotConfigured_503WithClearMessage_NeverInventsResults()
        {
            var search = await Off.GetAsync("/geo/search?q=ben thanh");
            AssertError(search, HttpStatusCode.ServiceUnavailable, "geo_unavailable");
            Assert.Contains("chưa được cấu hình", search.Root.Str("message"));
            AssertError(await Off.GetAsync("/geo/reverse?lat=10.77&lng=106.69"), HttpStatusCode.ServiceUnavailable, "geo_unavailable");
        }

        [MongoFact]
        public async Task Configured_ProxiesResults_NotFoundAndValidation()
        {
            var rows = (await On.OkAsync(On.GetAsync("/geo/search?q=ben thanh"))).Data;
            Assert.Equal("Chợ Bến Thành", rows[0].Str("name"));
            Assert.Equal(10.7725, rows[0].GetProperty("latitude").GetDouble());

            var before = _on.Geo.Calls;
            await On.OkAsync(On.GetAsync("/geo/search?q=BẾN THÀNH"));
            Assert.Equal(before, _on.Geo.Calls); // Cache: không gọi lại dịch vụ ngoài.

            Assert.Empty((await On.OkAsync(On.GetAsync("/geo/search?q="))).Data.EnumerateArray());

            Assert.Equal("Lê Lợi, Quận 1", (await On.OkAsync(On.GetAsync("/geo/reverse?lat=10.77&lng=106.69"))).Data.Str("address"));
            AssertError(await On.GetAsync("/geo/reverse?lat=-10&lng=106.69"), HttpStatusCode.NotFound, "not_found");
            AssertError(await On.GetAsync("/geo/reverse?lat=100&lng=106.69"), HttpStatusCode.BadRequest, "validation");
            AssertError(await On.GetAsync("/geo/reverse?lat=10"), HttpStatusCode.BadRequest, "validation");
        }
    }

    /// <summary>Client thật với HTTP giả lập: không gọi ra Internet.</summary>
    public class Sprint11_NominatimClientTests
    {
        private sealed class Stub : HttpMessageHandler
        {
            public int Calls;
            public string? LastUrl;
            public string? LastUserAgent;
            public Func<HttpResponseMessage> Respond { get; set; } = () => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("[]") };

            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            {
                Calls++;
                LastUrl = request.RequestUri!.AbsoluteUri;
                LastUserAgent = request.Headers.UserAgent.ToString();
                return Task.FromResult(Respond());
            }
        }

        private static (NominatimGeocodingClient Client, Stub Handler) Build(string? baseUrl)
        {
            var handler = new Stub();
            var config = new ConfigurationBuilder().AddInMemoryCollection(new[] { new KeyValuePair<string, string?>("Geo:BaseUrl", baseUrl) }).Build();
            return (new NominatimGeocodingClient(new HttpClient(handler), config, NullLogger<NominatimGeocodingClient>.Instance), handler);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("khong-phai-url")]
        [InlineData("ftp://geo.test")]
        public async Task NoValidBaseUrl_NeverCallsOut(string? baseUrl)
        {
            var (client, handler) = Build(baseUrl);
            Assert.False(client.IsConfigured);
            await Assert.ThrowsAsync<ServiceUnavailableException>(() => client.SearchAsync("ben thanh"));
            await Assert.ThrowsAsync<ServiceUnavailableException>(() => client.ReverseAsync(10, 106));
            Assert.Equal(0, handler.Calls);
        }

        [Fact]
        public async Task Search_ParsesRows_DropsRowsWithoutCoordinates()
        {
            var (client, handler) = Build("https://geo.test/");
            handler.Respond = () => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""
                    [ { "lat":"10.7725","lon":"106.698","name":"Chợ Bến Thành","display_name":"Chợ Bến Thành, Lê Lợi, Quận 1","address":{"city":"TP. Hồ Chí Minh"} },
                      { "name":"Thiếu toạ độ","display_name":"Không có lat" },
                      { "lat":"10.1","lon":"106.1","name":"","display_name":"Đường A, Huyện B","address":{"state":"Tỉnh C"} } ]
                    """)
            };
            var rows = await client.SearchAsync("bến thành");
            Assert.Equal(2, rows.Count);
            Assert.Equal("Chợ Bến Thành", rows[0].Name);
            Assert.Equal("TP. Hồ Chí Minh", rows[0].City);
            Assert.Equal(10.7725, rows[0].Latitude);
            Assert.Equal("Đường A", rows[1].Name);
            Assert.Equal("Tỉnh C", rows[1].City);
            Assert.StartsWith("https://geo.test/search?", handler.LastUrl);
            Assert.Contains("q=b%E1%BA%BFn%20th%C3%A0nh", handler.LastUrl);
            Assert.False(string.IsNullOrEmpty(handler.LastUserAgent));
        }

        [Fact]
        public async Task Reverse_UnknownPlaceIsNull()
        {
            var (client, handler) = Build("https://geo.test");
            handler.Respond = () => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("""{ "error":"Unable to geocode" }""") };
            Assert.Null(await client.ReverseAsync(0, 0));
            Assert.Contains("/reverse?", handler.LastUrl);
        }

        [Fact]
        public async Task UpstreamFailure_Is503_WithoutLeakingDetails()
        {
            var (client, handler) = Build("https://geo.test");
            handler.Respond = () => new HttpResponseMessage(HttpStatusCode.TooManyRequests);
            var ex = await Assert.ThrowsAsync<ServiceUnavailableException>(() => client.SearchAsync("x"));
            Assert.Equal("geo_unavailable", ex.ErrorCode);
            Assert.DoesNotContain("geo.test", ex.Message);

            handler.Respond = () => throw new HttpRequestException("mất kết nối tới geo.test");
            await Assert.ThrowsAsync<ServiceUnavailableException>(() => client.ReverseAsync(1, 1));

            handler.Respond = () => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("<html>") };
            await Assert.ThrowsAsync<ServiceUnavailableException>(() => client.SearchAsync("x"));
        }
    }

    public class Sprint11_SearchTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_SearchTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private async Task<string> PostAsync(string title, string userId, string status = "Published", string media = "Text", bool deleted = false)
        {
            var id = ObjectId.GenerateNewId().ToString();
            await H.Db.Posts.InsertOneAsync(new Post { Id = id, UserId = userId, Title = title, Body = "Nội dung", Status = status, MediaType = media, IsDeleted = deleted });
            return id;
        }

        [MongoFact]
        public async Task Search_OnlyPublished_SplitsVideos_IgnoresDiacritics()
        {
            var author = await H.UserAsync(name: "Tác Giả");
            var stem = ObjectId.GenerateNewId().ToString()[^8..];
            var published = await PostAsync($"Bún riêu chay {stem}", author.Id);
            var video = await PostAsync($"Video bún riêu {stem}", author.Id, media: "Video");
            await PostAsync($"Chờ duyệt bún riêu {stem}", author.Id, "Pending");
            await PostAsync($"Từ chối bún riêu {stem}", author.Id, "Rejected");
            await PostAsync($"Ẩn bún riêu {stem}", author.Id, "Hidden");
            await PostAsync($"Xoá bún riêu {stem}", author.Id, deleted: true);

            var data = (await H.OkAsync(H.GetAsync($"/search?q=bun rieu {stem}"))).Data;
            Assert.Equal($"bun rieu {stem}", data.Str("query"));
            Assert.Equal(published, data.GetProperty("posts").EnumerateArray().Single().Str("id"));
            Assert.Equal(video, data.GetProperty("videos").EnumerateArray().Single().Str("id"));
            var post = data.GetProperty("posts")[0];
            Assert.Equal("Published", post.Str("status"));
            Assert.Equal("Tác Giả", post.GetProperty("author").Str("fullName"));

            var onlyPosts = (await H.OkAsync(H.GetAsync($"/search?q=bun rieu {stem}&type=post"))).Data;
            Assert.Single(onlyPosts.GetProperty("posts").EnumerateArray());
            Assert.Empty(onlyPosts.GetProperty("videos").EnumerateArray());

            var onlyVideos = (await H.OkAsync(H.GetAsync($"/search?q=bun rieu {stem}&type=video"))).Data;
            Assert.Empty(onlyVideos.GetProperty("posts").EnumerateArray());
            Assert.Single(onlyVideos.GetProperty("videos").EnumerateArray());

            AssertError(await H.GetAsync("/search?q=a&type=bogus"), HttpStatusCode.BadRequest, "validation");
            var empty = (await H.OkAsync(H.GetAsync("/search?q="))).Data;
            Assert.Empty(empty.GetProperty("posts").EnumerateArray());
            Assert.Equal(JsonValueKind.Null, empty.GetProperty("suggestion").ValueKind);
        }

        [MongoFact]
        public async Task Search_PrivateRecipes_OnlyOwnerSees_SuggestionHasRealRows()
        {
            var owner = await H.UserAsync();
            var other = await H.UserAsync();
            var admin = await H.AdminAsync();
            var stem = "monthu" + ObjectId.GenerateNewId().ToString()[^8..];
            var shared = ObjectId.GenerateNewId().ToString();
            var mine = ObjectId.GenerateNewId().ToString();
            await H.Db.Recipes.InsertManyAsync(new[]
            {
                new Recipe { Id = shared, Name = $"Cơm chay {stem}", Calories = 500, IsVegan = true },
                new Recipe { Id = mine, Name = $"Cơm riêng tư {stem}", Calories = 300, IsVegan = true, CreatedBy = owner.Id }
            });
            var related = await PostAsync($"Hướng dẫn cơm chay {stem}", owner.Id);
            var restaurant = await H.ApprovedRestaurantAsync(admin, other, $"Quán {stem}");
            await H.OkAsync(H.PostAsync($"/restaurants/{restaurant}/reviews", other, new { rating = 5, comment = $"Cơm chay {stem} rất ngon." }));

            var guest = (await H.OkAsync(H.GetAsync($"/search?q={stem}"))).Data;
            Assert.Equal(shared, guest.GetProperty("recipes").EnumerateArray().Single().Str("id"));
            Assert.Equal(500, guest.GetProperty("recipes")[0].GetProperty("caloriesCache").GetInt32());
            Assert.True(guest.GetProperty("recipes")[0].GetProperty("isVegan").GetBoolean());

            var suggestion = guest.GetProperty("suggestion");
            Assert.Equal(shared, suggestion.GetProperty("recipe").Str("id"));
            Assert.Equal(related, suggestion.GetProperty("relatedPosts")[0].Str("id"));
            Assert.Equal(restaurant, suggestion.GetProperty("restaurants")[0].Str("id"));
            Assert.Equal(restaurant, guest.GetProperty("restaurants")[0].Str("id"));

            Assert.Equal(2, (await H.OkAsync(H.GetAsync($"/search?q={stem}", owner))).Data.GetProperty("recipes").GetArrayLength());
            Assert.Single((await H.OkAsync(H.GetAsync($"/search?q={stem}", other))).Data.GetProperty("recipes").EnumerateArray());
        }

        [MongoFact]
        public async Task Suggest_KindsAndLimits_NoPrivateRows()
        {
            var owner = await H.UserAsync();
            var stem = "goiy" + ObjectId.GenerateNewId().ToString()[^8..];
            await H.Db.Recipes.InsertOneAsync(new Recipe { Id = ObjectId.GenerateNewId().ToString(), Name = $"Món {stem}", Calories = 100, IsVegan = true });
            await H.Db.Recipes.InsertOneAsync(new Recipe { Id = ObjectId.GenerateNewId().ToString(), Name = $"Riêng {stem}", IsVegan = true, CreatedBy = owner.Id });
            await PostAsync($"Bài {stem}", owner.Id);
            await PostAsync($"Chờ {stem}", owner.Id, "Pending");
            await H.Db.Ingredients.InsertOneAsync(new Ingredient { Id = ObjectId.GenerateNewId().ToString(), Name = $"Nguyên liệu {stem}", NormalizedName = stem });

            var items = (await H.OkAsync(H.GetAsync($"/search/suggest?q={stem}"))).Data.EnumerateArray().ToList();
            Assert.Contains(items, i => i.Str("kind") == "recipe" && i.Str("text") == $"Món {stem}");
            Assert.Contains(items, i => i.Str("kind") == "post");
            Assert.Contains(items, i => i.Str("kind") == "ingredient");
            Assert.DoesNotContain(items, i => i.Str("text").StartsWith("Riêng") || i.Str("text").StartsWith("Chờ"));

            Assert.Single((await H.OkAsync(H.GetAsync($"/search/suggest?q={stem}&limit=1"))).Data.EnumerateArray());
            Assert.Empty((await H.OkAsync(H.GetAsync("/search/suggest?q=a"))).Data.EnumerateArray());
        }

        [MongoFact]
        public async Task Discover_NoInventedTrends_PopularComesFromRealPlans()
        {
            var admin = await H.AdminAsync();
            var data = (await H.OkAsync(H.GetAsync("/search/discover"))).Data;
            Assert.Empty(data.GetProperty("trending").EnumerateArray());
            Assert.Empty(data.GetProperty("seasonal").EnumerateArray());

            var recipe = ObjectId.GenerateNewId().ToString();
            await H.Db.Recipes.InsertOneAsync(new Recipe { Id = recipe, Name = "Món được chọn", IsVegan = true });
            await H.Db.MealPlans.InsertOneAsync(new MealPlan
            {
                Id = ObjectId.GenerateNewId().ToString(),
                UserId = ObjectId.GenerateNewId().ToString(),
                StartDate = "2026-09-28",
                Days = new List<MealPlanDay> { new() { Meals = new Dictionary<string, MealSlotItem> { ["lunch"] = new() { RecipeId = recipe, Name = "Món được chọn" } } } }
            });
            var code = "cat_" + ObjectId.GenerateNewId().ToString()[^8..];
            await H.OkAsync(H.PostAsync("/admin/catalog", admin, new { kind = "category", code, label = "Món chính thử" }));

            var after = (await H.OkAsync(H.GetAsync("/search/discover"))).Data;
            Assert.Equal(recipe, after.GetProperty("popularRecipes")[0].Str("id"));
            var category = after.GetProperty("categories").EnumerateArray().Single(c => c.Str("label") == "Món chính thử");
            Assert.Equal("Món chính thử", category.Str("query"));
        }
    }

    public class Sprint11_AdTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_AdTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private static string Unique(string name) => $"{name} {ObjectId.GenerateNewId().ToString()[^8..]}";

        private async Task<(TestUser Admin, string Restaurant)> SetupAsync()
        {
            var admin = await H.AdminAsync();
            return (admin, await H.ApprovedRestaurantAsync(admin, await H.UserAsync(), Unique("Quán QC")));
        }

        private async Task<JsonElement> CampaignAsync(TestUser admin, string id) =>
            (await H.OkAsync(H.GetAsync("/admin/ads", admin))).Data.EnumerateArray().Single(c => c.Str("id") == id);

        private async Task<bool> InFeedAsync(string id, string query = "") =>
            (await H.OkAsync(H.GetAsync($"/ads/feed?limit=20{query}"))).Ids().Contains(id);

        [MongoFact]
        public async Task Create_ValidatesLikeFe()
        {
            var (admin, restaurant) = await SetupAsync();
            object Input(string? headline = "Bún riêu chay ngon", string? message = "Tô đầy đặn, nước dùng ngọt.", string cta = "ViewStore", string? city = null, long budget = 500_000, string placement = "nearby", string start = "2026-09-01T00:00:00Z", string end = "2026-12-01T00:00:00Z", string? rid = null) =>
                new { restaurantId = rid ?? restaurant, placement, headline, message, ctaType = cta, targetCity = city, startAt = start, endAt = end, budget };

            foreach (var bad in new[]
            {
                Input(headline: "ngắn"), Input(headline: new string('x', 61)), Input(message: "ngắn"), Input(message: new string('x', 141)),
                Input(cta: "Bogus"), Input(city: "Hải Phòng"), Input(budget: 99_999), Input(placement: "feed"),
                Input(start: "2026-12-02T00:00:00Z"), Input(start: "2026-09-01T00:00:00Z", end: "2026-09-15T00:00:00Z")
            })
            {
                AssertError(await H.PostAsync("/admin/ads", admin, bad), HttpStatusCode.BadRequest, "validation");
            }

            AssertError(await H.PostAsync("/admin/ads", admin, Input(rid: "507f1f77bcf86cd799439011")), HttpStatusCode.BadRequest, "restaurant_not_found");

            var pending = (await H.OkAsync(H.PostAsync("/restaurants", await H.UserAsync(), new { name = Unique("Quán Chờ"), address = "12 Lê Lợi, Quận 1" }))).Id();
            AssertError(await H.PostAsync("/admin/ads", admin, Input(rid: pending)), HttpStatusCode.BadRequest, "restaurant_not_approved");

            var created = await H.OkAsync(H.PostAsync("/admin/ads", admin, Input(city: "Hà Nội")));
            Assert.Equal("Running", created.Data.Str("status"));
            Assert.Equal(0, created.Data.GetProperty("spent").GetInt64());
            Assert.Equal(restaurant, created.Data.GetProperty("restaurant").Str("id"));
        }

        [MongoFact]
        public async Task Feed_RunningOnly_CityFolded_NearestFirst_RejectedRestaurantHidden()
        {
            var (admin, restaurant) = await SetupAsync();
            var hanoi = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant, city: "Hà Nội")))).Id();
            var national = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant)))).Id();
            var scheduled = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant, start: "2026-11-01T00:00:00Z")))).Id();
            Assert.Equal("Scheduled", (await CampaignAsync(admin, scheduled)).Str("status"));
            Assert.False(await InFeedAsync(scheduled));

            Assert.True(await InFeedAsync(hanoi, "&city=ha noi"));
            Assert.True(await InFeedAsync(national, "&city=ha noi"));
            Assert.False(await InFeedAsync(hanoi, "&city=" + Uri.EscapeDataString("Đà Nẵng")));
            Assert.True(await InFeedAsync(national, "&city=" + Uri.EscapeDataString("Đà Nẵng")));

            var item = (await H.OkAsync(H.GetAsync("/ads/feed?limit=20&lat=10.77&lng=106.70"))).Data.EnumerateArray().First(i => i.Str("id") == national);
            Assert.Equal("Xem quán", item.Str("ctaLabel"));
            Assert.Equal(0, item.GetProperty("distanceKm").GetDouble());
            Assert.Equal(0, item.GetProperty("restaurant").GetProperty("reviewCount").GetInt32());
            Assert.Equal("nearby", item.Str("placement"));

            Assert.Empty((await H.OkAsync(H.GetAsync("/ads/feed?placement=other"))).Data.EnumerateArray());
            Assert.Single((await H.OkAsync(H.GetAsync("/ads/feed"))).Data.EnumerateArray());

            await H.OkAsync(H.PostAsync($"/admin/restaurants/{restaurant}/review", admin, new { decision = "Reject", reason = "Đóng cửa" }));
            Assert.False(await InFeedAsync(national));
        }

        [MongoFact]
        public async Task Counters_ChargeOnlyWhenRunning_CappedAtBudget_NoLostUpdates()
        {
            var (admin, restaurant) = await SetupAsync();
            var id = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant, budget: 100_000)))).Id();

            Assert.Equal(HttpStatusCode.NoContent, (await H.PostAsync($"/ads/{id}/impression")).Status);
            Assert.Equal(HttpStatusCode.NoContent, (await H.PostAsync($"/ads/{id}/click")).Status);
            var one = await CampaignAsync(admin, id);
            Assert.Equal(1, one.GetProperty("impressions").GetInt64());
            Assert.Equal(1, one.GetProperty("clicks").GetInt64());
            Assert.Equal(40, one.GetProperty("spent").GetInt64());

            await Task.WhenAll(Enumerable.Range(0, 30).Select(_ => H.PostAsync($"/ads/{id}/impression")));
            var many = await CampaignAsync(admin, id);
            Assert.Equal(31, many.GetProperty("impressions").GetInt64());
            Assert.Equal(31 * 40, many.GetProperty("spent").GetInt64());

            await H.OkAsync(H.PostAsync($"/admin/ads/{id}/pause", admin));
            await H.PostAsync($"/ads/{id}/impression");
            await H.PostAsync($"/ads/{id}/click");
            var paused = await CampaignAsync(admin, id);
            Assert.Equal("Paused", paused.Str("status"));
            Assert.Equal(31, paused.GetProperty("impressions").GetInt64());
            Assert.Equal(1, paused.GetProperty("clicks").GetInt64());
            Assert.False(await InFeedAsync(id));

            await H.OkAsync(H.PostAsync($"/admin/ads/{id}/resume", admin));
            Assert.True(await InFeedAsync(id));

            // Gần hết ngân sách: lượt cuối không vượt quá.
            await H.Db.Database.GetCollection<AdCampaign>("AdCampaigns").UpdateOneAsync(a => a.Id == id, Builders<AdCampaign>.Update.Set(a => a.Spent, 99_990L));
            await H.PostAsync($"/ads/{id}/impression");
            var ended = await CampaignAsync(admin, id);
            Assert.Equal(100_000, ended.GetProperty("spent").GetInt64());
            Assert.Equal("Ended", ended.Str("status"));
            Assert.False(await InFeedAsync(id));
            AssertError(await H.PostAsync($"/admin/ads/{id}/resume", admin), HttpStatusCode.Conflict, "ended");

            AssertError(await H.PatchAsync($"/admin/ads/{id}", admin, new { budget = 100_000 - 1 }), HttpStatusCode.BadRequest, "validation");
            var raised = await H.OkAsync(H.PatchAsync($"/admin/ads/{id}", admin, new { budget = 200_000 }));
            Assert.Equal("Running", raised.Data.Str("status"));
            Assert.Equal(32, raised.Data.GetProperty("impressions").GetInt64());

            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/ads/507f1f77bcf86cd799439011/impression")).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/ads/khong-phai-id/click")).Status);
        }

        [MongoFact]
        public async Task Patch_PartialKeepsRest_TargetCityNullMeansNational_DeleteHides()
        {
            var (admin, restaurant) = await SetupAsync();
            var id = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant, city: "Hà Nội")))).Id();

            var renamed = await H.OkAsync(H.PatchAsync($"/admin/ads/{id}", admin, new { headline = "Tiêu đề mới hoàn toàn" }));
            Assert.Equal("Tiêu đề mới hoàn toàn", renamed.Data.Str("headline"));
            Assert.Equal("Hà Nội", renamed.Data.Str("targetCity"));

            var national = await H.CallAsync(HttpMethod.Patch, $"/admin/ads/{id}", admin, new Dictionary<string, object?> { ["targetCity"] = null });
            Assert.Equal(HttpStatusCode.OK, national.Status);
            Assert.Equal(JsonValueKind.Null, national.Data.GetProperty("targetCity").ValueKind);

            AssertError(await H.PatchAsync($"/admin/ads/{id}", admin, new { endAt = "2026-08-01T00:00:00Z" }), HttpStatusCode.BadRequest, "validation");
            Assert.Equal(1, (await H.OkAsync(H.GetAsync($"/admin/ads?search={Uri.EscapeDataString("tieu de moi")}&city=national", admin))).Ids().Count(x => x == id));
            Assert.DoesNotContain(id, (await H.OkAsync(H.GetAsync("/admin/ads?status=Paused", admin))).Ids());

            Assert.Equal(HttpStatusCode.NoContent, (await H.DeleteAsync($"/admin/ads/{id}", admin)).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.DeleteAsync($"/admin/ads/{id}", admin)).Status);
            Assert.False(await InFeedAsync(id));
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/ads/{id}/impression")).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/admin/ads/{id}/pause", admin)).Status);
        }

        [MongoFact]
        public async Task EndDatePassed_IsEnded_ByClock()
        {
            var (admin, restaurant) = await SetupAsync();
            var id = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant, end: "2026-10-02T00:00:00Z")))).Id();
            Assert.True(await InFeedAsync(id));
            H.Clock.Set(new DateTime(2026, 10, 2, 0, 0, 1, DateTimeKind.Utc));
            Assert.False(await InFeedAsync(id));
            Assert.Equal("Ended", (await CampaignAsync(admin, id)).Str("status"));
            await H.PostAsync($"/ads/{id}/impression");
            Assert.Equal(0, (await CampaignAsync(admin, id)).GetProperty("impressions").GetInt64());
        }
    }

    public class Sprint11_AdRateLimitTests : IClassFixture<AdsLimitedFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_AdRateLimitTests(AdsLimitedFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        [MongoFact]
        public async Task PublicCounters_AreRateLimited()
        {
            var admin = await H.AdminAsync();
            var restaurant = await H.ApprovedRestaurantAsync(admin, await H.UserAsync(), "Quán Giới Hạn");
            var id = (await H.OkAsync(H.PostAsync("/admin/ads", admin, ContentApi.Ad(restaurant)))).Id();

            var results = new List<HttpStatusCode>();
            for (var i = 0; i < 12; i++) results.Add((await H.PostAsync($"/ads/{id}/impression")).Status);
            Assert.Contains(HttpStatusCode.TooManyRequests, results);

            var spent = (await H.OkAsync(H.GetAsync("/admin/ads", admin))).Data[0].GetProperty("spent").GetInt64();
            Assert.Equal(results.Count(s => s == HttpStatusCode.NoContent) * 40, spent);
        }
    }

    public class Sprint11_VideoTests : IClassFixture<ContentFactory>
    {
        private readonly ContentFactory _factory;
        private readonly CommerceHarness H;

        public Sprint11_VideoTests(ContentFactory factory)
        {
            _factory = factory;
            _factory.Gemini.Configured = true;
            _factory.Gemini.JsonResult = () => GoodResult();
            _factory.Videos.Failure = null;
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        private static ApplicationLayer.DTOs.Content.VideoExtractionResult GoodResult() => new()
        {
            Summary = "Chả lụa chay từ đậu hũ ky.",
            Servings = 4,
            TotalMinutes = 45,
            KcalPerServing = 210,
            Ingredients = new() { new() { Name = "Đậu hũ ky", Quantity = "200 g", AtSecond = 35, Uncertain = false }, new() { Name = " ", Quantity = "bỏ" } },
            Steps = new() { new() { Index = 9, Text = "Ngâm đậu", AtSecond = 60 } },
            Transcript = new() { new() { AtSecond = 0, Text = "Xin chào" } }
        };

        private async Task<string> VideoPostAsync(TestUser author, string status = "Published", string media = "Video", bool asset = true)
        {
            var id = ObjectId.GenerateNewId().ToString();
            var url = $"/uploads/videos/{id}.mp4";
            await H.Db.Posts.InsertOneAsync(new Post { Id = id, UserId = author.Id, Title = "Chả lụa chay", MediaType = media, MediaUrl = url, Status = status });
            if (asset) await H.Db.MediaAssets.InsertOneAsync(new MediaAsset { Id = ObjectId.GenerateNewId().ToString(), OwnerId = author.Id, Url = url, PublicId = id, MediaType = "Video", DurationSeconds = 724 });
            return id;
        }

        private async Task<bool> RunWorkerAsync()
        {
            using var scope = _factory.Services.CreateScope();
            return await scope.ServiceProvider.GetRequiredService<ApplicationLayer.Interfaces.IVideoService>().RunOnceAsync();
        }

        private async Task<string> CreateVideoPostAsync(TestUser author, string type = "recipe")
        {
            var url = $"https://cdn.test/{ObjectId.GenerateNewId()}.mp4";
            await H.Db.MediaAssets.InsertOneAsync(new MediaAsset { Id = ObjectId.GenerateNewId().ToString(), OwnerId = author.Id, Url = url, PublicId = url, MediaType = "Video", DurationSeconds = 60 });
            var res = await H.OkAsync(H.PostAsync("/posts", author, new { type, title = "Video mới " + url, body = "Nội dung video nấu ăn.", mediaType = "Video", mediaUrl = url }));
            return res.Data.GetProperty("id").GetString()!;
        }

        [MongoFact]
        public async Task NewRecipeVideo_IsQueuedAutomatically_WhenAiIsConfigured()
        {
            var author = await H.UserAsync(name: "Tác Giả Tự Động");
            var id = await CreateVideoPostAsync(author);

            var video = await H.OkAsync(H.GetAsync($"/videos/{id}", author));
            Assert.Equal("queued", video.Data.GetProperty("aiStatus").GetString());
            await H.Db.VideoExtractions().DeleteManyAsync(v => v.PostId == id);
        }

        [MongoFact]
        public async Task NewVideo_WithoutAi_RunsNothing_AndSaysWhy()
        {
            _factory.Gemini.Configured = false;
            try
            {
                var author = await H.UserAsync(name: "Tác Giả Không AI");
                var id = await CreateVideoPostAsync(author);

                var video = await H.OkAsync(H.GetAsync($"/videos/{id}", author));
                Assert.Equal("failed", video.Data.GetProperty("aiStatus").GetString());
                Assert.Contains("chưa được cấu hình", video.Data.GetProperty("failureReason").GetString());
                Assert.Equal(0, await H.Db.VideoExtractions().CountDocumentsAsync(v => v.PostId == id));
            }
            finally
            {
                _factory.Gemini.Configured = true;
            }
        }

        [MongoFact]
        public async Task QnaVideo_IsNotQueued_AndDailyLimitStopsAutoExtraction()
        {
            var author = await H.UserAsync(name: "Tác Giả Hạn Mức");
            var qna = await CreateVideoPostAsync(author, "discussion");
            Assert.Equal("failed", (await H.OkAsync(H.GetAsync($"/videos/{qna}", author))).Data.GetProperty("aiStatus").GetString());

            var within = new List<string>();
            for (var i = 0; i < 3; i++) within.Add(await CreateVideoPostAsync(author));
            var over = await CreateVideoPostAsync(author);

            Assert.Equal("failed", (await H.OkAsync(H.GetAsync($"/videos/{over}", author))).Data.GetProperty("aiStatus").GetString());
            Assert.Equal("queued", (await H.OkAsync(H.PostAsync($"/videos/{over}/extraction", author))).Data.GetProperty("aiStatus").GetString());
            within.Add(over);
            await H.Db.VideoExtractions().DeleteManyAsync(v => within.Contains(v.PostId));
        }

        [MongoFact]
        public async Task NotConfigured_503_NothingQueued_NoFakeExtraction()
        {
            _factory.Gemini.Configured = false;
            var author = await H.UserAsync();
            var id = await VideoPostAsync(author);
            var callsBefore = _factory.Gemini.JsonCalls;

            var result = await H.PostAsync($"/videos/{id}/extraction", author);
            AssertError(result, HttpStatusCode.ServiceUnavailable, "ai_unavailable");
            Assert.Contains("chưa được cấu hình", result.Root.Str("message"));

            var read = (await H.OkAsync(H.GetAsync($"/videos/{id}"))).Data;
            Assert.Equal("failed", read.Str("aiStatus"));
            Assert.Empty(read.GetProperty("ingredients").EnumerateArray());
            Assert.Equal(JsonValueKind.Null, read.GetProperty("summary").ValueKind);
            Assert.False(await RunWorkerAsync());
            Assert.Equal(callsBefore, _factory.Gemini.JsonCalls);
            _factory.Gemini.Configured = true;
        }

        [MongoFact]
        public async Task Permissions_GuestReadsPublished_OnlyAuthorOrAdminRetries_HiddenIs404()
        {
            var author = await H.UserAsync();
            var other = await H.UserAsync();
            var chef = await H.ChefAsync();
            var id = await VideoPostAsync(author);

            await H.OkAsync(H.GetAsync($"/videos/{id}"));
            Assert.Equal(HttpStatusCode.Unauthorized, (await H.PostAsync($"/videos/{id}/extraction")).Status);
            AssertError(await H.PostAsync($"/videos/{id}/extraction", other), HttpStatusCode.Forbidden, "not_author");
            AssertError(await H.PostAsync($"/videos/{id}/extraction", chef), HttpStatusCode.Forbidden, "not_author");

            var pending = await VideoPostAsync(author, "Pending");
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/videos/{pending}")).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/videos/{pending}", other)).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/videos/{pending}/extraction", other)).Status);
            await H.OkAsync(H.GetAsync($"/videos/{pending}", author));
            await H.OkAsync(H.GetAsync($"/videos/{pending}", await H.AdminAsync()));

            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync($"/videos/{await VideoPostAsync(author, media: "Image")}")).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync("/videos/khong-phai-id")).Status);
        }

        [MongoFact]
        public async Task Pipeline_QueuedThenReady_StoresOnlyModelOutput_ThenRetryConflicts()
        {
            var author = await H.UserAsync(name: "Tác Giả Video");
            var id = await VideoPostAsync(author);

            var queued = await H.OkAsync(H.PostAsync($"/videos/{id}/extraction", author));
            Assert.Equal("queued", queued.Data.Str("aiStatus"));

            // Bấm đúp không xếp hàng lần hai.
            await H.OkAsync(H.PostAsync($"/videos/{id}/extraction", author));

            Assert.True(await RunWorkerAsync());
            Assert.False(await RunWorkerAsync());

            var video = (await H.OkAsync(H.GetAsync($"/videos/{id}"))).Data;
            Assert.Equal("ready", video.Str("aiStatus"));
            Assert.Equal("Chả lụa chay", video.Str("title"));
            Assert.Equal("Tác Giả Video", video.GetProperty("author").Str("fullName"));
            Assert.Equal(724, video.GetProperty("durationSeconds").GetInt32());
            Assert.Equal(4, video.GetProperty("servings").GetInt32());
            Assert.Equal(210, video.GetProperty("kcalPerServing").GetInt32());
            var ingredient = video.GetProperty("ingredients").EnumerateArray().Single();
            Assert.Equal("200 g", ingredient.Str("quantity"));
            Assert.Equal(1, video.GetProperty("steps")[0].GetProperty("index").GetInt32());
            Assert.Equal("Xin chào", video.GetProperty("transcript")[0].Str("text"));
            Assert.Equal(JsonValueKind.Null, video.GetProperty("failureReason").ValueKind);
            Assert.Equal("video/mp4", _factory.Gemini.LastMime);

            AssertError(await H.PostAsync($"/videos/{id}/extraction", author), HttpStatusCode.Conflict, "already_ready");
        }

        [MongoFact]
        public async Task Failures_BecomeFailedWithSafeReason_RetryWorks()
        {
            var author = await H.UserAsync();
            var admin = await H.AdminAsync();

            var empty = await VideoPostAsync(author);
            _factory.Gemini.JsonResult = () => new ApplicationLayer.DTOs.Content.VideoExtractionResult();
            await H.OkAsync(H.PostAsync($"/videos/{empty}/extraction", author));
            Assert.True(await RunWorkerAsync());
            Assert.Equal("failed", (await H.OkAsync(H.GetAsync($"/videos/{empty}"))).Data.Str("aiStatus"));

            var boom = await VideoPostAsync(author);
            _factory.Gemini.JsonResult = () => throw new InvalidOperationException("secret-api-key-123");
            await H.OkAsync(H.PostAsync($"/videos/{boom}/extraction", author));
            Assert.True(await RunWorkerAsync());
            var failed = (await H.OkAsync(H.GetAsync($"/videos/{boom}"))).Data;
            Assert.Equal("failed", failed.Str("aiStatus"));
            Assert.DoesNotContain("secret", failed.Str("failureReason"));

            var big = await VideoPostAsync(author);
            _factory.Videos.Failure = new PayloadTooLargeException("to");
            await H.OkAsync(H.PostAsync($"/videos/{big}/extraction", author));
            Assert.True(await RunWorkerAsync());
            Assert.Contains("quá lớn", (await H.OkAsync(H.GetAsync($"/videos/{big}"))).Data.Str("failureReason"));
            _factory.Videos.Failure = null;

            var orphan = await VideoPostAsync(author, asset: false);
            await H.OkAsync(H.PostAsync($"/videos/{orphan}/extraction", author));
            Assert.True(await RunWorkerAsync());
            Assert.Equal("Không tìm thấy tệp video.", (await H.OkAsync(H.GetAsync($"/videos/{orphan}"))).Data.Str("failureReason"));

            // Admin thử lại được và lần này thành công; trang tổng quan đếm số video lỗi thật.
            _factory.Gemini.JsonResult = () => GoodResult();
            var overviewBefore = (await H.OkAsync(H.GetAsync("/admin/overview", admin))).Data.GetProperty("pending").GetProperty("failedVideos").GetInt64();
            Assert.True(overviewBefore >= 4);
            var retried = await H.OkAsync(H.PostAsync($"/videos/{boom}/extraction", admin));
            Assert.Equal("queued", retried.Data.Str("aiStatus"));
            Assert.Equal(JsonValueKind.Null, retried.Data.GetProperty("failureReason").ValueKind);
            Assert.True(await RunWorkerAsync());
            Assert.Equal("ready", (await H.OkAsync(H.GetAsync($"/videos/{boom}"))).Data.Str("aiStatus"));
            Assert.Equal(overviewBefore - 1, (await H.OkAsync(H.GetAsync("/admin/overview", admin))).Data.GetProperty("pending").GetProperty("failedVideos").GetInt64());
        }

        [MongoFact]
        public async Task CrashedJob_IsReclaimedAfterTimeout_AndCapped()
        {
            var author = await H.UserAsync();
            var id = await VideoPostAsync(author);
            await H.OkAsync(H.PostAsync($"/videos/{id}/extraction", author));

            var rows = H.Db.Database.GetCollection<VideoExtraction>("VideoExtractions");
            await rows.UpdateOneAsync(v => v.PostId == id, Builders<VideoExtraction>.Update.Set(v => v.Status, "extracting").Set(v => v.UpdatedAt, T0));
            Assert.False(await RunWorkerAsync()); // Chưa quá hạn: có thể vẫn đang chạy.

            H.Clock.Set(T0.AddMinutes(11));
            Assert.True(await RunWorkerAsync());
            Assert.Equal("ready", (await H.OkAsync(H.GetAsync($"/videos/{id}"))).Data.Str("aiStatus"));

            var second = await VideoPostAsync(author);
            await H.OkAsync(H.PostAsync($"/videos/{second}/extraction", author));
            await rows.UpdateOneAsync(v => v.PostId == second, Builders<VideoExtraction>.Update.Set(v => v.Attempts, 3));
            Assert.True(await RunWorkerAsync());
            Assert.Equal("failed", (await H.OkAsync(H.GetAsync($"/videos/{second}"))).Data.Str("aiStatus"));
        }
    }

    public class Sprint11_AdminOverviewTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_AdminOverviewTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
        }

        [MongoFact]
        public async Task Overview_CountsAreExactlyWhatIsInTheDb()
        {
            var now = new DateTime(2026, 10, 20, 5, 0, 0, DateTimeKind.Utc);
            H.Clock.Set(now);
            var admin = await H.AdminAsync();
            var empty = (await H.OkAsync(H.GetAsync("/admin/overview", admin))).Data;
            var seededUsers = empty.GetProperty("totalUsers").GetInt64();
            Assert.Equal(0, empty.GetProperty("posts24h").GetInt64());
            Assert.Equal(0, empty.GetProperty("aiQueries24h").GetInt64());
            Assert.Equal(0, empty.GetProperty("activeUsers24h").GetInt64());
            Assert.Equal(0, empty.GetProperty("pending").GetProperty("aiFlags").GetInt64());
            Assert.Equal(14, empty.GetProperty("signupsDaily").GetArrayLength());

            var a = ObjectId.GenerateNewId().ToString();
            var b = ObjectId.GenerateNewId().ToString();
            await H.Db.Users.InsertManyAsync(new[]
            {
                new User { Id = a, Email = "a@x.vn", EmailNormalized = "a@x.vn", FullName = "A", Phone = "", CreatedAt = now.AddDays(-1) },
                new User { Id = b, Email = "b@x.vn", EmailNormalized = "b@x.vn", FullName = "B", Phone = "", CreatedAt = now.AddDays(-9) },
                new User { Id = ObjectId.GenerateNewId().ToString(), Email = "c@x.vn", EmailNormalized = "c@x.vn", FullName = "C", Phone = "", CreatedAt = now.AddDays(-1), IsDeleted = true }
            });
            await H.Db.Posts.InsertManyAsync(new[]
            {
                new Post { Id = ObjectId.GenerateNewId().ToString(), UserId = a, Type = "recipe", Status = "Published", CreatedAt = now.AddHours(-2) },
                new Post { Id = ObjectId.GenerateNewId().ToString(), UserId = a, Type = "discussion", Status = "Pending", ReportCount = 2, CreatedAt = now.AddHours(-3) },
                new Post { Id = ObjectId.GenerateNewId().ToString(), UserId = b, Type = "discussion", Status = "Published", CreatedAt = now.AddHours(-30) },
                new Post { Id = ObjectId.GenerateNewId().ToString(), UserId = b, Type = "recipe", Status = "Published", CreatedAt = now.AddHours(-1), IsDeleted = true }
            });
            await H.Db.AiLogs.InsertManyAsync(new[]
            {
                new AiLog { Id = ObjectId.GenerateNewId().ToString(), UserId = b, TaskType = "Chat", CreatedAt = now.AddHours(-1) },
                new AiLog { Id = ObjectId.GenerateNewId().ToString(), TaskType = "Embedding", CreatedAt = now.AddHours(-1) },
                new AiLog { Id = ObjectId.GenerateNewId().ToString(), TaskType = "Vision", CreatedAt = now.AddHours(-30) }
            });

            var d = (await H.OkAsync(H.GetAsync("/admin/overview", admin))).Data;
            Assert.Equal(seededUsers + 2, d.GetProperty("totalUsers").GetInt64());
            Assert.Equal(2, d.GetProperty("posts24h").GetInt64()); // Bài đã xoá không tính.
            Assert.Equal(1, d.GetProperty("postsDelta").GetDouble()); // 2 so với 1 bài kỳ trước.
            Assert.Equal(1, d.GetProperty("aiQueries24h").GetInt64());
            Assert.Equal(0, d.GetProperty("aiQueriesDelta").GetDouble());
            Assert.Equal(2, d.GetProperty("activeUsers24h").GetInt64());
            var pending = d.GetProperty("pending");
            Assert.Equal(1, pending.GetProperty("pendingPosts").GetInt64());
            Assert.Equal(1, pending.GetProperty("reportedContent").GetInt64());
            Assert.Equal(0, pending.GetProperty("chefApplications").GetInt64());
            Assert.Equal(0, pending.GetProperty("failedVideos").GetInt64());

            var mix = d.GetProperty("contentMix").EnumerateArray().ToDictionary(x => x.Str("kind"), x => x.GetProperty("count").GetInt64());
            Assert.Equal(1, mix["recipe"]);
            Assert.Equal(1, mix["discussion"]);

            var signups = d.GetProperty("signupsDaily").EnumerateArray().ToList();
            Assert.Equal("2026-10-20", signups[^1].Str("date"));
            Assert.Equal(1, signups.Single(s => s.Str("date") == "2026-10-19").GetProperty("count").GetInt32());
            Assert.Equal(1, signups.Single(s => s.Str("date") == "2026-10-11").GetProperty("count").GetInt32());
        }
    }

    public class Sprint11_CatalogTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_CatalogTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
        }

        [MongoFact]
        public async Task Crud_Duplicate_InUse_UsageIsReal()
        {
            var admin = await H.AdminAsync();
            AssertError(await H.GetAsync("/admin/catalog", admin), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.GetAsync("/admin/catalog?kind=bogus", admin), HttpStatusCode.BadRequest, "validation");

            var tag = "tag_" + ObjectId.GenerateNewId().ToString()[^8..];
            await H.Db.Recipes.InsertOneAsync(new Recipe { Id = ObjectId.GenerateNewId().ToString(), Name = "Món gắn thẻ", DietTags = new List<string> { tag }, Allergens = new List<string> { "soy" } });

            var tags = (await H.OkAsync(H.GetAsync("/admin/catalog?kind=diet_tag", admin))).Data.EnumerateArray().ToList();
            var used = tags.Single(t => t.Str("code") == tag);
            Assert.Equal(1, used.GetProperty("usageCount").GetInt32());
            Assert.True(ObjectId.TryParse(used.Str("id"), out _));
            Assert.Equal("diet_tag", used.Str("kind"));

            var allergens = (await H.OkAsync(H.GetAsync("/admin/catalog?kind=allergen", admin))).Data.EnumerateArray().ToList();
            Assert.Contains(allergens, x => x.Str("code") == "soy" && x.GetProperty("usageCount").GetInt32() >= 1 && x.Str("label").StartsWith("Đậu nành"));

            var code = "cat_" + ObjectId.GenerateNewId().ToString()[^8..];
            var created = await H.OkAsync(H.PostAsync("/admin/catalog", admin, new { kind = "diet_tag", code, label = "Thẻ mới" }));
            Assert.Equal(0, created.Data.GetProperty("usageCount").GetInt32());
            Assert.True(created.Data.GetProperty("active").GetBoolean());
            AssertError(await H.PostAsync("/admin/catalog", admin, new { kind = "diet_tag", code, label = "Trùng" }), HttpStatusCode.Conflict, "duplicate_code");
            await H.OkAsync(H.PostAsync("/admin/catalog", admin, new { kind = "category", code, label = "Khác nhóm thì được" }));
            AssertError(await H.PostAsync("/admin/catalog", admin, new { kind = "diet_tag", code = "Có Dấu", label = "Sai mã" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/admin/catalog", admin, new { kind = "bogus", code = "ok_code", label = "Sai nhóm" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync("/admin/catalog", admin, new { kind = "diet_tag", code = "ok_code", label = "x" }), HttpStatusCode.BadRequest, "validation");

            var patched = await H.OkAsync(H.PatchAsync($"/admin/catalog/{created.Id()}", admin, new { label = "Đã đổi nhãn", active = false, cvLabel = "tofu" }));
            Assert.Equal("Đã đổi nhãn", patched.Data.Str("label"));
            Assert.False(patched.Data.GetProperty("active").GetBoolean());
            Assert.Equal("tofu", patched.Data.Str("cvLabel"));
            AssertError(await H.PatchAsync($"/admin/catalog/{created.Id()}", admin, new { label = "x" }), HttpStatusCode.BadRequest, "validation");

            // Xem lại danh sách không ghi đè nhãn admin đã sửa.
            var usedId = used.Str("id");
            await H.OkAsync(H.PatchAsync($"/admin/catalog/{usedId}", admin, new { label = "Nhãn tự đặt" }));
            var again = (await H.OkAsync(H.GetAsync("/admin/catalog?kind=diet_tag", admin))).Data.EnumerateArray().ToList();
            Assert.Equal("Nhãn tự đặt", again.Single(t => t.Str("code") == tag).Str("label"));
            Assert.Single(again, t => t.Str("code") == tag);

            AssertError(await H.DeleteAsync($"/admin/catalog/{usedId}", admin), HttpStatusCode.Conflict, "in_use");
            await H.OkAsync(H.DeleteAsync($"/admin/catalog/{created.Id()}", admin));
            Assert.Equal(HttpStatusCode.NotFound, (await H.DeleteAsync($"/admin/catalog/{created.Id()}", admin)).Status);
            Assert.DoesNotContain(code, (await H.OkAsync(H.GetAsync("/admin/catalog?kind=diet_tag", admin))).Data.EnumerateArray().Select(t => t.Str("code")));
        }

        [MongoFact]
        public async Task Specialty_ComesFromRealChefProfiles()
        {
            var admin = await H.AdminAsync();
            var chef = await H.ChefAsync();
            await H.ChefWithProfileAsync(chef);
            var rows = (await H.OkAsync(H.GetAsync("/admin/catalog?kind=specialty", admin))).Data.EnumerateArray().ToList();
            Assert.Contains(rows, r => r.Str("code") == "am_thuc_chay_hue" && r.Str("label") == "Ẩm thực chay Huế" && r.GetProperty("usageCount").GetInt32() >= 1);
        }
    }

    public class Sprint11_ModerationAndAiTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;
        private readonly IMongoCollection<ModerationFlag> _flags;

        public Sprint11_ModerationAndAiTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
            H.Clock.Set(T0);
            _flags = H.Db.Database.GetCollection<ModerationFlag>("ModerationFlags");
        }

        [MongoFact]
        public async Task Flags_NoPipeline_MeansEmptyRealQueue_ThenDecisionWorksOnARealRow()
        {
            var admin = await H.AdminAsync();
            var author = await H.UserAsync(name: "Tác Giả Cờ");
            const string missing = "507f1f77bcf86cd799439011";
            AssertError(await H.PostAsync($"/admin/moderation/flags/{missing}/decision", admin, new { action = "bogus", note = "Đủ mười ký tự rồi" }), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.PostAsync($"/admin/moderation/flags/{missing}/decision", admin, new { action = "reject", note = "ngắn" }), HttpStatusCode.BadRequest, "note_too_short");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync($"/admin/moderation/flags/{missing}/decision", admin, new { action = "reject", note = "Đủ mười ký tự rồi" })).Status);
            AssertError(await H.GetAsync("/admin/moderation/flags?status=bogus", admin), HttpStatusCode.BadRequest, "validation");

            var postId = ObjectId.GenerateNewId().ToString();
            await H.Db.Posts.InsertOneAsync(new Post { Id = postId, UserId = author.Id, Title = "Bài cần xem", Body = "Nội dung", Status = "Published" });
            var flagId = ObjectId.GenerateNewId().ToString();
            await _flags.InsertOneAsync(new ModerationFlag { Id = flagId, PostId = postId, Status = "pending", PrimaryCategory = "toxicity", Confidence = 0.9, Reason = "Từ ngữ thô", CreatedAt = T0.AddMinutes(-30) });

            var row = (await H.OkAsync(H.GetAsync("/admin/moderation/flags?status=pending", admin))).Data.EnumerateArray().Single(f => f.Str("id") == flagId);
            Assert.Equal("Tác Giả Cờ", row.GetProperty("post").GetProperty("author").Str("displayName"));
            Assert.Equal("visible", row.GetProperty("post").Str("visibility"));
            Assert.Contains(flagId, (await H.OkAsync(H.GetAsync("/admin/moderation/flags?category=toxicity&search=tu ngu tho", admin))).Ids());
            Assert.True((await H.OkAsync(H.GetAsync("/admin/moderation/flags/counts", admin))).Data.GetProperty("pending").GetInt64() >= 1);

            await H.OkAsync(H.PostAsync($"/admin/moderation/flags/{flagId}/decision", admin, new { flagId, action = "reject", note = "Vi phạm tiêu chuẩn", notifyAuthor = true }));
            var post = await H.Db.Posts.Find(p => p.Id == postId).FirstAsync();
            Assert.Equal("Rejected", post.Status);
            AssertError(await H.PostAsync($"/admin/moderation/flags/{flagId}/decision", admin, new { action = "approve", note = "Xử lý lại lần hai" }), HttpStatusCode.Conflict, "already_decided");

            var metrics = (await H.OkAsync(H.GetAsync("/admin/ai/metrics?range=24h", admin))).Data.GetProperty("moderation");
            Assert.True(metrics.GetProperty("decided").GetInt32() >= 1);
            Assert.Equal(1, metrics.GetProperty("precision").GetDouble());
            Assert.Equal(30, metrics.GetProperty("medianDecisionMinutes").GetDouble());
        }

        private async Task<string> LogAsync(string task, long latency, bool success = true, int input = 10, int output = 5, DateTime? at = null, string? error = null)
        {
            var id = ObjectId.GenerateNewId().ToString();
            await H.Db.AiLogs.InsertOneAsync(new AiLog { Id = id, TaskType = task, LatencyMs = latency, Success = success, PromptTokens = input, CandidatesTokens = output, CreatedAt = at ?? T0.AddMinutes(-5), Model = "gemini-test", ErrorMessage = error });
            return id;
        }

        [MongoFact]
        public async Task Telemetry_LogsAndLabels_ComeFromRealLogs()
        {
            var admin = await H.AdminAsync();
            // Khoảng thời gian riêng để không lẫn với test khác trong cùng DB.
            var now = new DateTime(2027, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            H.Clock.Set(now);
            var empty = (await H.OkAsync(H.GetAsync("/admin/ai/telemetry/summary?range=1h", admin))).Data;
            Assert.Equal(0, empty.GetProperty("totalCalls").GetInt64());
            Assert.Empty(empty.GetProperty("byTask").EnumerateArray());
            AssertError(await H.GetAsync("/admin/ai/telemetry/summary?range=2d", admin), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.GetAsync("/admin/ai/metrics?range=2d", admin), HttpStatusCode.BadRequest, "validation");
            AssertError(await H.GetAsync("/admin/ai/logs?task=bogus", admin), HttpStatusCode.BadRequest, "validation");

            var chat = await LogAsync("Chat", 100, at: now.AddMinutes(-10));
            await LogAsync("Chat", 300, success: false, at: now.AddMinutes(-9), error: "gọi https://x.test?key=SECRET123 lỗi");
            var vision = await LogAsync("Vision", 200, input: 20, output: 10, at: now.AddMinutes(-8));
            await LogAsync("Vision", 100, at: now.AddMinutes(-70));

            var t = (await H.OkAsync(H.GetAsync("/admin/ai/telemetry/summary?range=1h", admin))).Data;
            Assert.Equal(3, t.GetProperty("totalCalls").GetInt64());
            Assert.Equal(200, t.GetProperty("avgLatencyMs").GetDouble());
            Assert.Equal(300, t.GetProperty("p95LatencyMs").GetDouble());
            Assert.Equal(0.3333, t.GetProperty("errorRate").GetDouble());
            Assert.Equal(60, t.GetProperty("totalTokens").GetInt64());
            Assert.Equal(0, t.GetProperty("flagRate").GetDouble());
            Assert.Equal(2, t.GetProperty("delta").GetProperty("totalCalls").GetDouble());
            var chatRow = t.GetProperty("byTask").EnumerateArray().Single(x => x.Str("task") == "chatbot");
            Assert.Equal(2, chatRow.GetProperty("calls").GetInt64());
            Assert.Equal(0.5, chatRow.GetProperty("errorRate").GetDouble());

            var logs = (await H.OkAsync(H.GetAsync("/admin/ai/logs?task=vision_scan&limit=1", admin))).Data.EnumerateArray().Single();
            Assert.Equal("vision_scan", logs.Str("task"));
            Assert.Equal(20, logs.GetProperty("inputTokens").GetInt32());
            Assert.Equal(JsonValueKind.Null, logs.GetProperty("inputText").ValueKind);

            var errored = (await H.OkAsync(H.GetAsync("/admin/ai/logs?task=chatbot", admin))).Data.EnumerateArray().First(x => x.Str("status") == "error");
            Assert.DoesNotContain("SECRET123", errored.Str("detail"));

            AssertError(await H.PostAsync($"/admin/ai/logs/{chat}/label", admin, new { verdict = "maybe" }), HttpStatusCode.BadRequest, "validation");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PostAsync("/admin/ai/logs/507f1f77bcf86cd799439011/label", admin, new { verdict = "correct" })).Status);
            Assert.Equal(HttpStatusCode.NotFound, (await H.GetAsync("/admin/ai/logs/khong-phai-id", admin)).Status);

            var labeled = await H.OkAsync(H.PostAsync($"/admin/ai/logs/{chat}/label", admin, new { verdict = "incorrect", note = "Trích sai" }));
            Assert.Equal("incorrect", labeled.Data.GetProperty("label").Str("verdict"));
            var relabeled = await H.OkAsync(H.PostAsync($"/admin/ai/logs/{chat}/label", admin, new { verdict = "correct" }));
            Assert.Equal("Lê Minh Quân", relabeled.Data.GetProperty("label").Str("by"));
            Assert.Equal("correct", (await H.OkAsync(H.GetAsync($"/admin/ai/logs/{chat}", admin))).Data.GetProperty("label").Str("verdict"));
            await H.OkAsync(H.PostAsync($"/admin/ai/logs/{vision}/label", admin, new { verdict = "incorrect" }));

            var labels = (await H.OkAsync(H.GetAsync("/admin/ai/metrics?range=1h", admin))).Data.GetProperty("labeled").EnumerateArray().ToDictionary(x => x.Str("task"));
            Assert.Equal(1, labels["chatbot"].GetProperty("labeled").GetInt32());
            Assert.Equal(1, labels["chatbot"].GetProperty("accuracy").GetDouble());
            Assert.Equal(0, labels["vision_scan"].GetProperty("correct").GetInt32());
        }

        [MongoFact]
        public async Task Models_ReflectConfig_PatchIsAudited_AndSayWhatIsEnforced()
        {
            var admin = await H.AdminAsync();
            var models = (await H.OkAsync(H.GetAsync("/admin/ai/models", admin))).Data.EnumerateArray().ToDictionary(m => m.Str("task"));
            Assert.Equal(4, models.Count);
            Assert.Equal(models.Count, (await H.OkAsync(H.GetAsync("/admin/ai/models", admin))).Data.GetArrayLength());
            Assert.False(models["moderation"].GetProperty("enabled").GetBoolean());
            Assert.Equal("rule-based", models["meal_plan"].Str("activeVersion"));
            Assert.True(models["chatbot"].GetProperty("runtimeEnforced").GetBoolean());
            Assert.True(models["vision_scan"].GetProperty("runtimeEnforced").GetBoolean());
            Assert.True(models["meal_plan"].GetProperty("runtimeEnforced").GetBoolean());
            Assert.False(models["moderation"].GetProperty("runtimeEnforced").GetBoolean(), "kiểm duyệt AI chưa có pipeline");

            var chat = models["chatbot"].Str("id");
            var vision = models["vision_scan"].Str("id");
            var moderation = models["moderation"].Str("id");
            AssertError(await H.PatchAsync($"/admin/ai/models/{chat}", admin, new { enabled = false }), HttpStatusCode.BadRequest, "note_too_short");
            AssertError(await H.PatchAsync($"/admin/ai/models/{moderation}", admin, new { enabled = true, note = "Bật thử kiểm duyệt" }), HttpStatusCode.Conflict, "no_pipeline");
            AssertError(await H.PatchAsync($"/admin/ai/models/{chat}", admin, new { threshold = 0.8, note = "Đổi ngưỡng chatbot" }), HttpStatusCode.BadRequest, "threshold_not_supported");
            AssertError(await H.PatchAsync($"/admin/ai/models/{vision}", admin, new { threshold = 0.1, note = "Đổi ngưỡng quét ảnh" }), HttpStatusCode.BadRequest, "invalid_threshold");
            AssertError(await H.PatchAsync($"/admin/ai/models/{chat}", admin, new { activeVersion = "gpt-9", note = "Đổi phiên bản lạ" }), HttpStatusCode.BadRequest, "invalid_version");
            Assert.Equal(HttpStatusCode.NotFound, (await H.PatchAsync("/admin/ai/models/507f1f77bcf86cd799439011", admin, new { note = "Không có mô hình này" })).Status);

            var patched = await H.OkAsync(H.PatchAsync($"/admin/ai/models/{vision}", admin, new { threshold = 0.7, enabled = false, note = "Giảm tải trong giờ cao điểm" }));
            Assert.Equal(0.7, patched.Data.GetProperty("threshold").GetDouble());
            Assert.False(patched.Data.GetProperty("enabled").GetBoolean());
            Assert.Equal("Lê Minh Quân", patched.Data.Str("updatedBy"));
            Assert.False((await H.OkAsync(H.GetAsync("/admin/ai/models", admin))).Data.EnumerateArray().Single(m => m.Str("task") == "vision_scan").GetProperty("enabled").GetBoolean());

            var actions = (await H.OkAsync(H.GetAsync("/admin/overview", admin))).Data.GetProperty("recentActions").EnumerateArray();
            Assert.Contains(actions, a => a.Str("action") == "đổi cấu hình mô hình AI");
        }
    }

    /// <summary>Đọc tệp video thật trong thư mục tạm, không gọi Internet.</summary>
    public class Sprint11_VideoContentReaderTests
    {
        private sealed class Stub : HttpMessageHandler
        {
            public int Calls;
            public byte[] Body = new byte[10];
            public long? DeclaredLength;

            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            {
                Calls++;
                var content = new ByteArrayContent(Body);
                content.Headers.ContentLength = DeclaredLength ?? Body.Length;
                content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("video/webm");
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
            }
        }

        private static string VideosDir()
        {
            var dir = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "uploads", "videos");
            Directory.CreateDirectory(dir);
            return dir;
        }

        [Fact]
        public async Task LocalFile_ReadsWithinLimit_RefusesLargerAndTraversal()
        {
            var name = $"{Guid.NewGuid():N}.mov";
            var path = Path.Combine(VideosDir(), name);
            await File.WriteAllBytesAsync(path, new byte[100]);
            try
            {
                var stub = new Stub();
                var reader = new VideoContentReader(new HttpClient(stub));
                var (bytes, mime) = await reader.ReadAsync($"/uploads/videos/{name}", 100);
                Assert.Equal(100, bytes.Length);
                Assert.Equal("video/quicktime", mime);
                await Assert.ThrowsAsync<PayloadTooLargeException>(() => reader.ReadAsync($"/uploads/videos/{name}", 99));
                await Assert.ThrowsAsync<NotFoundException>(() => reader.ReadAsync("/uploads/videos/../../appsettings.json", 1000));
                Assert.Equal(0, stub.Calls);
            }
            finally
            {
                File.Delete(path);
            }
        }

        [Theory]
        [InlineData("http://res.cloudinary.com/a.mp4")]
        [InlineData("file:///etc/passwd")]
        [InlineData("/etc/passwd")]
        public async Task OtherSources_AreRefusedWithoutCallingOut(string url)
        {
            var stub = new Stub();
            await Assert.ThrowsAsync<BadRequestException>(() => new VideoContentReader(new HttpClient(stub)).ReadAsync(url, 1000));
            Assert.Equal(0, stub.Calls);
        }

        [Fact]
        public async Task Remote_ChecksDeclaredAndActualSize()
        {
            var ok = new Stub();
            var (bytes, mime) = await new VideoContentReader(new HttpClient(ok)).ReadAsync("https://res.cloudinary.com/a.mp4", 10);
            Assert.Equal(10, bytes.Length);
            Assert.Equal("video/webm", mime);

            await Assert.ThrowsAsync<PayloadTooLargeException>(() =>
                new VideoContentReader(new HttpClient(new Stub { Body = new byte[11] })).ReadAsync("https://res.cloudinary.com/a.mp4", 10));
        }
    }

    public class Sprint11_SwaggerTests : IClassFixture<ContentFactory>
    {
        private readonly CommerceHarness H;

        public Sprint11_SwaggerTests(ContentFactory factory)
        {
            H = new CommerceHarness(factory);
        }

        [MongoFact]
        public async Task SwaggerDocument_StillGenerates_AndListsNewRoutes()
        {
            var (status, body) = await H.RawGetAsync("/swagger/v1/swagger.json");
            Assert.Equal(HttpStatusCode.OK, status);
            foreach (var route in new[] { "/api/v1/chefs/{id}", "/api/v1/admin/chef-applications/counts", "/api/v1/restaurants/suggested", "/api/v1/geo/search", "/api/v1/search/discover", "/api/v1/ads/feed", "/api/v1/videos/{id}/extraction", "/api/v1/admin/overview", "/api/v1/admin/ai/metrics" })
            {
                Assert.Contains($"\"{route}\"", body);
            }
        }
    }
}
