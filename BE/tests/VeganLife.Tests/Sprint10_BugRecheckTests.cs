using System.Net;
using System.Text.Json;
using ApplicationLayer.DTOs.Auth;
using ApplicationLayer.Interfaces;
using ApplicationLayer.Services;
using ControllerLayer.Middlewares;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using InfrastructureLayer.Seed;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging.Abstractions;
using MongoDB.Driver;
using Moq;
using VeganLife.Tests.Fixtures;
using Xunit;

namespace VeganLife.Tests
{
    /// <summary>Kiểm lại danh sách lỗi trong BE_API_VA_LOI.md mục 3, 4 bằng cách gọi API thật. Tên test mang số lỗi.</summary>
    public class Sprint10_BugRecheckTests : IClassFixture<QaFactory>
    {
        private readonly Qa _qa;

        public Sprint10_BugRecheckTests(QaFactory factory) => _qa = new Qa(factory);

        private async Task<(QaResult Auth, string Email)> RegisterAsync()
        {
            var email = $"qa{Guid.NewGuid():N}@test.vn";
            var res = await _qa.PostAsync("/auth/register", null, new { fullName = "Người Thử", email, password = Qa.Password, phone = "0912345678" });
            Qa.Is(HttpStatusCode.Created, res);
            return (res, email);
        }

        private Task<QaResult> LoginAsync(string email, string password = Qa.Password) =>
            _qa.PostAsync("/auth/login", null, new { email, password });

        private Task<QaResult> RefreshAsync(string token) =>
            _qa.PostAsync("/auth/refresh", null, new { refreshToken = token });

        /* ------------------------------------------------------------ bảo mật --- */

        [MongoFact]
        public async Task B42_Reset_password_revokes_every_refresh_token_and_the_old_password()
        {
            var (auth, email) = await RegisterAsync();
            var second = await LoginAsync(email);

            Qa.IsOk(await _qa.PostAsync("/auth/forgot-password", null, new { email }));
            var code = (await _qa.GetAsync($"/dev/auth/reset-code?email={Uri.EscapeDataString(email)}")).Str("code");
            var verified = await _qa.PostAsync("/auth/verify-reset-code", null, new { email, code });
            Qa.IsOk(await _qa.PostAsync("/auth/reset-password", null, new { resetToken = verified.Str("resetToken"), newPassword = "MatKhauMoi456!" }));

            Qa.Is(HttpStatusCode.Unauthorized, await RefreshAsync(auth.Str("refreshToken")));
            Qa.Is(HttpStatusCode.Unauthorized, await RefreshAsync(second.Str("refreshToken")));
            Qa.Is(HttpStatusCode.Unauthorized, await LoginAsync(email));
            Qa.IsOk(await LoginAsync(email, "MatKhauMoi456!"));
        }

        [MongoFact]
        public async Task B23_Reset_code_never_reaches_the_logs()
        {
            var (_, email) = await RegisterAsync();
            var original = Console.Out;
            using var captured = new StringWriter();
            Console.SetOut(captured);
            try
            {
                Qa.IsOk(await _qa.PostAsync("/auth/forgot-password", null, new { email }));
            }
            finally
            {
                Console.SetOut(original);
            }

            var code = (await _qa.GetAsync($"/dev/auth/reset-code?email={Uri.EscapeDataString(email)}")).Str("code");
            Assert.Matches("^[0-9]{6}$", code);
            Assert.DoesNotContain(code, captured.ToString());
            Assert.DoesNotContain(_qa.Logs, line => line.Contains(code));
        }

        [MongoFact]
        public async Task B23_Forgot_password_answers_the_same_for_an_unknown_email()
        {
            var unknown = await _qa.PostAsync("/auth/forgot-password", null, new { email = $"khong{Guid.NewGuid():N}@test.vn" });
            Qa.Is(HttpStatusCode.NoContent, unknown);
        }

        [MongoFact]
        public async Task B54_Deleted_account_is_cut_off_at_once()
        {
            var admin = await _qa.AdminAsync();
            var victim = await _qa.UserAsync();
            Qa.Is(HttpStatusCode.Created, await _qa.PostAsync("/posts", victim, Qa.PostBody()));

            Qa.IsOk(await _qa.DeleteAsync($"/users/{victim.Id}", admin));

            Qa.Is(HttpStatusCode.Unauthorized, await _qa.PostAsync("/posts", victim, Qa.PostBody()));
            Qa.Is(HttpStatusCode.Unauthorized, await _qa.GetAsync("/users/me", victim));
        }

        [MongoFact]
        public async Task B55_Each_device_keeps_its_own_session_and_refresh_rotates_only_that_one()
        {
            var (first, email) = await RegisterAsync();
            var second = await LoginAsync(email);
            var firstToken = first.Str("refreshToken");
            var secondToken = second.Str("refreshToken");

            var rotated = await RefreshAsync(firstToken);
            Qa.IsOk(rotated);
            Qa.Is(HttpStatusCode.Unauthorized, await RefreshAsync(firstToken));

            var secondRotated = await RefreshAsync(secondToken);
            Qa.IsOk(secondRotated);

            // Đăng xuất máy một không đá máy hai.
            Qa.Is(HttpStatusCode.NoContent, await _qa.CallAsync(HttpMethod.Post, "/auth/logout", token: rotated.Str("accessToken")));
            Qa.Is(HttpStatusCode.Unauthorized, await RefreshAsync(rotated.Str("refreshToken")));
            Qa.IsOk(await RefreshAsync(secondRotated.Str("refreshToken")));
        }

        [MongoFact]
        public async Task B55_Rows_from_before_the_change_still_refresh_once()
        {
            var user = await _qa.UserAsync();
            using var sha = System.Security.Cryptography.SHA256.Create();
            var raw = $"legacy-{Guid.NewGuid():N}";
            var hash = Convert.ToHexString(sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(raw))).ToLowerInvariant();
            await _qa.Db.Users.UpdateOneAsync(u => u.Id == user.Id, MongoDB.Driver.Builders<User>.Update
                .Set(u => u.RefreshTokenHash, hash)
                .Set(u => u.RefreshTokenExpiresAt, DateTime.UtcNow.AddDays(1)));

            Qa.IsOk(await RefreshAsync(raw));
            Qa.Is(HttpStatusCode.Unauthorized, await RefreshAsync(raw));
        }

        [Fact]
        public async Task B62_Unexpected_errors_keep_their_text_out_of_production()
        {
            foreach (var thrown in new Exception[]
            {
                new Exception("noi dung noi bo rat bi mat"),
                new ServerFailureException("noi dung noi bo rat bi mat"),
                new KeyNotFoundException("noi dung noi bo rat bi mat"),
                new UnauthorizedAccessException("noi dung noi bo rat bi mat"),
                new InvalidOperationException("noi dung noi bo rat bi mat"),
                new ArgumentException("noi dung noi bo rat bi mat")
            })
            {
                var body = await RunMiddlewareAsync(thrown, "Production");
                Assert.DoesNotContain("noi dung noi bo", body);
                Assert.DoesNotContain("   at ", body);
                using var doc = JsonDocument.Parse(body);
                Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("detail").ValueKind);
            }

            var dev = await RunMiddlewareAsync(new Exception("noi dung noi bo"), "Development");
            Assert.Contains("noi dung noi bo", dev);
        }

        private static async Task<string> RunMiddlewareAsync(Exception thrown, string environment)
        {
            var env = new Mock<IWebHostEnvironment>();
            env.SetupGet(e => e.EnvironmentName).Returns(environment);
            var middleware = new ExceptionHandlingMiddleware(_ => throw thrown, NullLogger<ExceptionHandlingMiddleware>.Instance, env.Object);
            var context = new DefaultHttpContext();
            context.Response.Body = new MemoryStream();
            await middleware.InvokeAsync(context);
            context.Response.Body.Position = 0;
            return await new StreamReader(context.Response.Body).ReadToEndAsync();
        }

        [MongoFact]
        public async Task B35_B66_Errors_are_readable_and_carry_a_code()
        {
            var (_, email) = await RegisterAsync();
            var wrong = await LoginAsync(email, "SaiMatKhau!!");
            Qa.Is(HttpStatusCode.Unauthorized, wrong, "unauthorized");
            Assert.Equal("Email hoặc mật khẩu không đúng.", wrong.Message);
            Assert.DoesNotMatch("Ã|áº|á»|Ä‘", wrong.Message!);
        }

        [MongoFact]
        public async Task B63_Framework_errors_use_the_envelope()
        {
            var noToken = await _qa.GetAsync("/users");
            Qa.Is(HttpStatusCode.Unauthorized, noToken, "unauthorized");
            Assert.False(noToken.Root.GetProperty("success").GetBoolean());

            var noRoute = await _qa.GetAsync("/admin/overview-khong-co", await _qa.AdminAsync());
            Qa.Is(HttpStatusCode.NotFound, noRoute, "not_found");

            var forbidden = await _qa.GetAsync("/users", await _qa.UserAsync());
            Qa.Is(HttpStatusCode.Forbidden, forbidden, "forbidden");

            var wrongMethod = await _qa.CallAsync(HttpMethod.Put, "/auth/login", null, new { });
            Qa.Is(HttpStatusCode.MethodNotAllowed, wrongMethod, "method_not_allowed");
        }

        [MongoFact]
        public async Task B64_Broken_json_is_answered_in_Vietnamese_without_parser_text()
        {
            var res = await _qa.CallAsync(HttpMethod.Post, "/auth/admin/login", rawJson: "{bad");
            Qa.Is(HttpStatusCode.BadRequest, res, "invalid_json");
            Assert.DoesNotContain("invalid start", res.Text);
            Assert.Contains("JSON", res.Message);
        }

        [MongoFact]
        public async Task A_user_cannot_read_the_private_recipe_of_another_through_a_meal_swap()
        {
            var owner = await _qa.UserAsync();
            var thief = await _qa.UserAsync();
            var secret = await _qa.OwnRecipeAsync(owner, "Công thức riêng của tôi");

            Qa.IsOk(await _qa.PutAsync("/health-profile/me", thief, Qa.ProfileBody()));
            var plan = await _qa.PostAsync("/meal-plans/generate", thief, new { startDate = Qa.ThisMonday() });
            Qa.IsOk(plan);

            var swap = await _qa.PatchAsync($"/meal-plans/{plan.Str("id")}/meals", thief, new { date = Qa.Today(), slot = "lunch", recipeId = secret });
            Qa.Is(HttpStatusCode.NotFound, swap);
            Assert.DoesNotContain(secret, swap.Message);
        }

        [MongoFact]
        public async Task Other_people_rows_are_not_found_on_the_routes_that_take_an_id()
        {
            var owner = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", owner, Qa.ProfileBody()));
            var planId = (await _qa.PostAsync("/meal-plans/generate", owner, new { startDate = Qa.ThisMonday() })).Str("id");
            var fridge = await _qa.PostAsync("/users/me/ingredients", owner, new { items = new[] { new { ingredient = "Đậu hũ" } } });
            var rowId = fridge.Data[0].GetProperty("id").GetString();
            var today = Qa.Today();

            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/meal-plans/{planId}", other));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/meal-plans/{planId}/swap-suggestions?date={today}&slot=lunch", other));
            Qa.Is(HttpStatusCode.NotFound, await _qa.DeleteAsync($"/meal-plans/{planId}/meals?date={today}&slot=lunch", other));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/users/me/ingredients/{rowId}", other, new { quantity = 5 }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.DeleteAsync($"/users/me/ingredients/{rowId}", other));
            Qa.Is(HttpStatusCode.Forbidden, await _qa.GetAsync($"/users/{owner.Id}", other));
            Qa.Is(HttpStatusCode.Forbidden, await _qa.PutAsync($"/users/{owner.Id}", other, new { fullName = "Tên lạ" }));
            Qa.Is(HttpStatusCode.Forbidden, await _qa.DeleteAsync($"/users/{owner.Id}", other));
            Assert.Equal(1, (await _qa.GetAsync("/users/me/ingredients", owner)).Data.GetArrayLength());
        }

        [MongoFact]
        public async Task B41_Meal_pattern_takes_real_slots_only()
        {
            var user = await _qa.UserAsync();
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync("/health-profile/me", user, new { heightCm = 170, weightKg = 66, goal = "maintain", gender = "Female", birthYear = 1998, mealPattern = new[] { "lunch", "khong-co" } }), "invalid_slot");
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, new { heightCm = 170, weightKg = 66, goal = "maintain", gender = "Female", birthYear = 1998, mealPattern = new[] { "snack_am", "lunch", "snack_late" } }));
        }

        /* ------------------------------------------------------------ hồ sơ --- */

        [MongoFact]
        public async Task B36_Metrics_are_checked_and_need_a_profile()
        {
            var user = await _qa.UserAsync();
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync("/health-profile/me/metrics", user, new { weightKg = 70 }));

            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody()));
            foreach (var body in new object[] { new { weightKg = -5 }, new { weightKg = 0 }, new { weightKg = 301 }, new { waistCm = -3 }, new { bodyFatPct = 500 }, new { } })
            {
                Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/health-profile/me/metrics", user, body));
            }
            var profile = await _qa.GetAsync("/health-profile/me", user);
            Assert.Equal(66, profile.Data.GetProperty("weightKg").GetDouble());
        }

        [MongoFact]
        public async Task B37_Metrics_move_the_target_and_keep_the_source()
        {
            var user = await _qa.UserAsync();
            var before = await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody());
            var created = await _qa.PostAsync("/health-profile/me/metrics", user, new { weightKg = 90, source = "check_in" });
            Qa.Is(HttpStatusCode.Created, created);
            Assert.Equal("check_in", created.Str("source"));

            var after = await _qa.GetAsync("/health-profile/me", user);
            Assert.True(after.Data.GetProperty("targetCalories").GetInt32() > before.Data.GetProperty("targetCalories").GetInt32());

            var rows = await _qa.GetAsync("/health-profile/me/metrics", user);
            Assert.Equal("check_in", rows.Data[0].GetProperty("source").GetString());
            Assert.Equal("profile", rows.Data[1].GetProperty("source").GetString());

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/health-profile/me/metrics", user, new { weightKg = 90, source = "khong-co" }));
        }

        [MongoFact]
        public async Task B43_Old_goals_are_migrated_and_read_right_even_before_that()
        {
            var user = await _qa.UserAsync();
            await _qa.Db.HealthProfiles.InsertOneAsync(new HealthProfile
            {
                UserId = user.Id, Goal = "lose", Gender = "Female", BirthYear = 1998, HeightCm = 170, WeightKg = 70,
                ActivityLevel = "light", TargetCalories = 1500, Allergies = new List<string>(), MealPattern = new List<string> { "lunch" }
            });
            Assert.Equal("lose_weight", (await _qa.GetAsync("/health-profile/me", user)).Str("goal"));

            Assert.True(await LegacyDataMigrations.MigrateGoalsAsync(_qa.Db) >= 1);
            Assert.Equal(0, await LegacyDataMigrations.MigrateGoalsAsync(_qa.Db));

            var stored = await MongoDB.Driver.IAsyncCursorSourceExtensions.FirstAsync(
                MongoDB.Driver.IMongoCollectionExtensions.Find(_qa.Db.HealthProfiles, p => p.UserId == user.Id));
            Assert.Equal("lose_weight", stored.Goal);
            Assert.Equal(1500, stored.TargetCalories);
        }

        [MongoFact]
        public async Task B9_B67_B68_Profile_keeps_activity_refuses_other_gender_and_matches_allergies_by_whole_words()
        {
            var user = await _qa.UserAsync();
            var body = new { heightCm = 170, weightKg = 66, goal = "maintain", gender = "Female", birthYear = 1998, activityLevel = "active" };
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, body));
            var kept = await _qa.PutAsync("/health-profile/me", user, new { heightCm = 170, weightKg = 66, goal = "maintain", gender = "Female", birthYear = 1998 });
            Assert.Equal("active", kept.Str("activityLevel"));

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync("/health-profile/me", user, new { heightCm = 170, weightKg = 66, goal = "maintain", gender = "Other", birthYear = 1998 }));

            var withAllergies = await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody(new object[] { new { name = "Đậu nành" }, new { name = "lá lốt" }, new { name = "Cá" }, new { name = "Me" } }));
            var ids = withAllergies.Data.GetProperty("allergies").EnumerateArray().Select(a => a.GetProperty("allergenId").ValueKind == JsonValueKind.Null ? null : a.GetProperty("allergenId").GetString()).ToList();
            Assert.Equal(new[] { "soy", null, null, null }, ids);
        }

        /* ------------------------------------------------------------ tủ lạnh --- */

        private async Task<JsonElement> AddToFridgeAsync(QaUser user, string name, double? quantity = null, string? unit = null)
        {
            var res = await _qa.PostAsync("/users/me/ingredients", user, new { items = new[] { new { ingredient = name, quantity, unit } } });
            Qa.IsOk(res);
            return res.Data.ValueKind == JsonValueKind.Array ? res.Data[0] : res.Data;
        }

        [MongoTheory]
        [InlineData("Gelatin", false)]
        [InlineData("Sườn non", false)]
        [InlineData("Dê", false)]
        [InlineData("Whey", false)]
        [InlineData("Hải sản", false)]
        [InlineData("Tiết canh", false)]
        [InlineData("Cá sốt cà chua", false)]
        [InlineData("Trứng chiên cà chua", false)]
        [InlineData("Dầu hào", false)]
        [InlineData("Sữa chua dừa", true)]
        [InlineData("Phô mai hạt điều", true)]
        [InlineData("Bơ", true)]
        [InlineData("Quả bơ", true)]
        [InlineData("Rau chân vịt", true)]
        [InlineData("Đậu gà", true)]
        public async Task B13_Fridge_verdict(string name, bool vegan)
        {
            var row = await AddToFridgeAsync(await _qa.UserAsync(), name);
            Assert.Equal(vegan, row.GetProperty("isVegan").GetBoolean());
        }

        [MongoFact]
        public async Task B38_Adding_again_without_an_amount_keeps_it()
        {
            var user = await _qa.UserAsync();
            await AddToFridgeAsync(user, "Cà chua", 300, "g");
            var again = await AddToFridgeAsync(user, "ca chua");
            Assert.Equal(300, again.GetProperty("quantity").GetDouble());
            Assert.Equal("g", again.GetProperty("unit").GetString());
        }

        [MongoFact]
        public async Task B14_B70_Names_that_differ_only_by_accent_are_two_rows_when_short()
        {
            var user = await _qa.UserAsync();
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody(new object[] { new { allergenId = "sesame", name = "Mè" } })));

            var tamarind = await AddToFridgeAsync(user, "Me");
            Assert.Equal(JsonValueKind.Null, tamarind.GetProperty("allergyWarning").ValueKind);

            var sesame = await AddToFridgeAsync(user, "Mè");
            Assert.Equal("Mè", sesame.GetProperty("ingredient").GetString());
            Assert.Equal("Cảnh báo dị ứng: Mè", sesame.GetProperty("allergyWarning").GetString());

            var rows = await _qa.GetAsync("/users/me/ingredients", user);
            Assert.Equal(2, rows.Data.GetArrayLength());
        }

        [Fact]
        public void B13_Every_seeded_ingredient_and_recipe_name_stays_vegan_without_the_catalog()
        {
            var names = IngredientSeedData.GetSeeds().SelectMany(i => new[] { i.Name }.Concat(i.Aliases))
                .Concat(RecipeSeedData.GetSeeds().SelectMany(r => new[] { r.Name }.Concat(r.Ingredients)));
            Assert.Empty(names.Where(n => !VeganClassifier.IsVegan(n)).Distinct());
        }

        [Theory]
        [InlineData("Không chay", false)]
        [InlineData("Thịt bò không chay", false)]
        [InlineData("Chân vịt", false)]
        [InlineData("Hạt óc chó", true)]
        [InlineData("Sữa óc chó", true)]
        [InlineData("Nấm sò", true)]
        [InlineData("Rau diếp cá", true)]
        [InlineData("Bánh bò", true)]
        [InlineData("Trái cây", true)]
        [InlineData("thit bo", false)]
        [InlineData("ca chua", true)]
        [InlineData("trai cay", true)]
        [InlineData("sua chua dua", true)]
        [InlineData("sua bo", false)]
        public void B13_Classifier_edges(string name, bool vegan) => Assert.Equal(vegan, VeganClassifier.IsVegan(name));

        /* ------------------------------------------------------------ bài viết --- */

        [MongoFact]
        public async Task B69_A_post_off_the_feed_behaves_as_not_found_unless_author_or_admin()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var id = await _qa.NewPostAsync(author);
            var commentId = await _qa.NewCommentAsync(author, id);
            Qa.IsOk(await _qa.PostAsync($"/posts/{id}/comments", other, new { content = "Phản hồi", parentId = commentId }));

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "hide", reason = "Vi phạm" }));

            foreach (var who in new QaUser?[] { other, null })
            {
                Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{id}", who));
                Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{id}/comments", who));
                Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{id}/comments/{commentId}/replies", who));
                Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/comments/{commentId}/replies", who));
            }
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{id}/like", other));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{id}/comments", other, new { content = "Sau khi ẩn" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{id}/reports", other, new { reason = "spam" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{id}/save", other));

            var seen = await _qa.GetAsync($"/posts/{id}", author);
            Qa.IsOk(seen);
            Assert.Equal(1, seen.Data.GetProperty("likeCount").GetInt32() + 1);
            foreach (var who in new[] { author, admin })
            {
                Qa.IsOk(await _qa.GetAsync($"/posts/{id}/comments", who));
                Qa.IsOk(await _qa.PostAsync($"/posts/{id}/like", who));
                Qa.IsOk(await _qa.PostAsync($"/posts/{id}/comments", who, new { content = "Vẫn được" }));
            }
        }

        [MongoTheory]
        [InlineData("Pending")]
        [InlineData("Rejected")]
        public async Task B69_Pending_and_rejected_posts_are_closed_too(string status)
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var id = await _qa.NewPostAsync(author);
            Qa.IsOk(await _qa.PatchAsync($"/admin/posts/{id}/status", admin, new { status }));

            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{id}/like", other));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{id}/comments"));
            Qa.IsOk(await _qa.PostAsync($"/posts/{id}/like", author));
        }

        [MongoFact]
        public async Task B71_Not_found_messages_do_not_echo_the_id()
        {
            var user = await _qa.UserAsync();
            var id = await _qa.NewPostAsync(user);
            Qa.IsOk(await _qa.DeleteAsync($"/posts/{id}", user));

            foreach (var res in new[]
            {
                await _qa.GetAsync($"/posts/{id}"),
                await _qa.DeleteAsync($"/posts/{id}", user),
                await _qa.PostAsync($"/posts/{id}/like", user),
                await _qa.GetAsync($"/posts/{id}/comments"),
                await _qa.GetAsync($"/meal-plans/{id}", user),
                await _qa.GetAsync($"/recipes/{id}"),
                await _qa.DeleteAsync($"/users/me/ingredients/{id}", user),
                await _qa.GetAsync($"/ingredients/{id}"),
                await _qa.GetAsync($"/comments/{id}/replies")
            })
            {
                Qa.Is(HttpStatusCode.NotFound, res);
                Assert.DoesNotContain(id, res.Message);
            }
            Assert.Equal("Không tìm thấy bài viết.", (await _qa.GetAsync($"/posts/{id}")).Message);
        }

        [MongoFact]
        public async Task B17_B39_B40_Replies_flatten_stay_on_their_post_and_have_no_updated_at_until_edited()
        {
            var user = await _qa.UserAsync();
            var post = await _qa.NewPostAsync(user);
            var elsewhere = await _qa.NewPostAsync(user);
            var root = await _qa.NewCommentAsync(user, post);
            var reply = await _qa.NewCommentAsync(user, post, "Phản hồi", root);
            var nested = await _qa.PostAsync($"/posts/{post}/comments", user, new { content = "Phản hồi lồng", parentId = reply });
            Assert.Equal(root, nested.Str("parentId"));

            var list = await _qa.GetAsync($"/posts/{post}/comments", user);
            Assert.Equal(JsonValueKind.Null, list.Data[0].GetProperty("updatedAt").ValueKind);
            Assert.Equal(2, list.Data[0].GetProperty("replyCount").GetInt32());

            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{elsewhere}/comments/{root}/replies"));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{elsewhere}/comments", user, new { content = "Sai bài", parentId = root }));

            Qa.IsOk(await _qa.DeleteAsync($"/comments/{root}", user));
            Assert.Equal(0, (await _qa.GetAsync($"/posts/{post}", user)).Data.GetProperty("commentCount").GetInt32());
        }

        [MongoFact]
        public async Task B61_Post_type_and_media_type_are_checked()
        {
            var user = await _qa.UserAsync();
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/posts", user, new { type = "XYZ", title = "T", body = "B", mediaType = "Text" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/posts", user, new { type = "discussion", title = "T", body = "B", mediaType = "Foo" }));
        }

        /* ------------------------------------------------------------ kiểm duyệt --- */

        [MongoTheory]
        [InlineData("/review", "decision")]
        [InlineData("/actions", "action")]
        [InlineData("/status", "status")]
        public async Task B44_B46_Moderation_routes_need_their_own_values(string route, string field)
        {
            var admin = await _qa.AdminAsync();
            var id = await _qa.NewPostAsync(await _qa.UserAsync());
            var method = route == "/status" ? HttpMethod.Patch : HttpMethod.Post;

            Qa.Is(HttpStatusCode.BadRequest, await _qa.CallAsync(method, $"/admin/posts/{id}{route}", admin, new { }));

            var wrong = route == "/actions" ? "Approve" : "delete";
            Qa.Is(HttpStatusCode.BadRequest, await _qa.CallAsync(method, $"/admin/posts/{id}{route}", admin, new Dictionary<string, string> { [field] = wrong }));

            Assert.Equal("Published", (await _qa.GetAsync($"/posts/{id}")).Str("status"));
        }

        [MongoFact]
        public async Task B47_A_deleted_post_cannot_be_brought_back()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync();
            var id = await _qa.NewPostAsync(author);
            Qa.IsOk(await _qa.DeleteAsync($"/posts/{id}", author));

            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Approve" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "unhide" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{id}"));
        }

        [MongoFact]
        public async Task B45_B48_B50_Reject_through_status_keeps_its_state_and_reaches_the_author()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync();
            var id = await _qa.NewPostAsync(author);

            Qa.IsOk(await _qa.PatchAsync($"/admin/posts/{id}/status", admin, new { status = "Rejected" }));
            Qa.Is(HttpStatusCode.Conflict, await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "hide" }));

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Reject", reason = "Sai chủ đề" }).ContinueWith(_ => _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Approve" })).Unwrap());
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Reject", reason = "Sai chủ đề" }));

            var own = await _qa.GetAsync($"/posts/{id}", author);
            Assert.Equal("Rejected", own.Str("status"));
            Assert.Equal("Sai chủ đề", own.Str("rejectionReason"));
        }

        [MongoFact]
        public async Task B49_B52_B53_Admin_list_has_the_fields_filters_by_status_and_admin_reads_any_post()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync();
            var title = $"Tiêu đề riêng {Guid.NewGuid():N}";
            var id = await _qa.NewPostAsync(author, title);
            Qa.IsOk(await _qa.PatchAsync($"/admin/posts/{id}/status", admin, new { status = "Pending" }));

            var list = await _qa.GetAsync($"/admin/posts?status=pending&pageSize=50&search={Uri.EscapeDataString(title.ToUpperInvariant())}", admin);
            Qa.IsOk(list);
            var row = list.Data.GetProperty("items").EnumerateArray().Single(p => p.GetProperty("id").GetString() == id);
            Assert.True(row.TryGetProperty("reportCount", out _));
            Assert.True(row.TryGetProperty("rejectionReason", out _));

            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/admin/posts?status=Nope", admin));
            Assert.Equal("Pending", (await _qa.GetAsync($"/posts/{id}", admin)).Str("status"));
        }

        [MongoFact]
        public async Task B51_After_an_approve_a_reporter_can_report_again()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync();
            var id = await _qa.NewPostAsync(author);
            var reporters = new[] { await _qa.UserAsync(), await _qa.UserAsync(), await _qa.UserAsync() };
            foreach (var r in reporters) Qa.IsOk(await _qa.PostAsync($"/posts/{id}/reports", r, new { reason = "spam" }));
            Assert.Equal("Pending", (await _qa.GetAsync($"/posts/{id}", author)).Str("status"));

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Approve" }));

            Qa.IsOk(await _qa.PostAsync($"/posts/{id}/reports", reporters[0], new { reason = "vẫn spam" }));
            Qa.Is(HttpStatusCode.Conflict, await _qa.PostAsync($"/posts/{id}/reports", reporters[0], new { reason = "lần nữa" }));
            Assert.Equal(1, (await _qa.GetAsync($"/posts/{id}", author)).Data.GetProperty("reportCount").GetInt32());
        }

        [MongoTheory]
        [InlineData("Published", true)]
        [InlineData("Rejected", true)]
        [InlineData("Hidden", false)]
        public async Task Moderation_status_pending_has_a_defined_transition(string from, bool allowed)
        {
            var admin = await _qa.AdminAsync();
            var id = await _qa.NewPostAsync(await _qa.UserAsync());
            if (from == "Rejected") Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Reject", reason = "Lý do" }));
            if (from == "Hidden") Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "hide" }));

            var res = await _qa.PatchAsync($"/admin/posts/{id}/status", admin, new { status = "Pending" });

            if (allowed)
            {
                Qa.IsOk(res);
                Assert.Equal("Pending", res.Str("status"));
                Assert.Equal(JsonValueKind.Null, res.Data.GetProperty("rejectionReason").ValueKind);
            }
            else
            {
                Qa.Is(HttpStatusCode.Conflict, res);
            }
        }

        [MongoFact]
        public async Task Hide_stores_its_reason_and_unhide_clears_it()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync();
            var id = await _qa.NewPostAsync(author);

            var hidden = await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "hide", reason = "Vi phạm" });
            Assert.Equal("Hidden", hidden.Str("status"));
            Assert.Equal("Vi phạm", hidden.Str("rejectionReason"));
            Assert.Equal("Vi phạm", (await _qa.GetAsync($"/posts/{id}", author)).Str("rejectionReason"));

            var back = await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "unhide" });
            Assert.Equal("Published", back.Str("status"));
            Assert.Equal(JsonValueKind.Null, back.Data.GetProperty("rejectionReason").ValueKind);
        }

        /* ------------------------------------------------------------ thực đơn, công thức --- */

        [MongoFact]
        public async Task B41_Writes_are_checked()
        {
            var user = await _qa.UserAsync();
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", user, new { name = "Rau xào", calories = -100, prepMinutes = 5, ingredients = new[] { "Rau" }, instructions = new[] { "Nấu" } }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", user, new { name = "Rau xào", calories = 100, prepMinutes = -5, ingredients = new[] { "Rau" }, instructions = new[] { "Nấu" } }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", user, new { name = "Thịt bò xào", calories = 100 }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", user, new { name = "Rau xào", calories = 100, ingredients = new[] { "Rau", "Gelatin" } }));

            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody()));
            var plan = await _qa.PostAsync("/meal-plans/generate", user, new { startDate = Qa.ThisMonday() });
            var planId = plan.Str("id");
            var today = Qa.Today();

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/meals", user, new { date = today, slot = "khong-co", name = "Rau", calories = 100 }), "invalid_slot");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/meals", user, new { date = today, slot = "lunch", name = "Thịt bò", calories = 100 }), "not_vegan");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/meals", user, new { date = today, slot = "lunch", name = "Rau", calories = 100, source = "khong-co" }), "invalid_source");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/meals", user, new { date = today, slot = "lunch", name = "Rau", calories = -1 }));

            var batch = await _qa.PostAsync("/meal-plans/current/meals/batch", user, new
            {
                meals = new object[]
                {
                    new { date = today, slot = "khong-co", name = "Rau", calories = 100 },
                    new { date = today, slot = "dinner", name = "Thịt bò", calories = 100 },
                    new { date = today, slot = "dinner", name = "Rau luộc", calories = 100 }
                }
            });
            Assert.Equal(1, batch.Data.GetProperty("placed").GetInt32());
            Assert.Equal(2, batch.Data.GetProperty("skipped").GetInt32());

            var suggestion = await _qa.GetAsync($"/meal-plans/{planId}/swap-suggestions?date={today}&slot=lunch&limit=1", user);
            var recipeId = suggestion.Data[0].GetProperty("id").GetString();
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/meal-plans/{planId}/meals", user, new { date = today, slot = "lunch", recipeId, source = "khong-co-nguon-nay" }), "invalid_source");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/meal-plans/{planId}/meals", user, new { date = today, slot = "khong-co", recipeId }), "invalid_slot");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/meal-plans/{planId}/meals", user, new { date = today, slot = "lunch", recipeId, portion = 99 }), "invalid_portion");
            Qa.IsOk(await _qa.PatchAsync($"/meal-plans/{planId}/meals", user, new { date = today, slot = "lunch", recipeId, source = "recipe" }));
        }

        [MongoFact]
        public async Task B31_B33_Portions_follow_a_high_target_and_prep_minutes_are_not_invented()
        {
            var user = await _qa.UserAsync();
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, new { heightCm = 190, weightKg = 110, goal = "gain_weight", gender = "Male", birthYear = 1998, activityLevel = "active" }));
            var plan = await _qa.PostAsync("/meal-plans/generate", user, new { startDate = Qa.ThisMonday() });
            var target = plan.Data.GetProperty("dailyTargets").GetProperty("calories").GetInt32();
            foreach (var day in plan.Data.GetProperty("days").EnumerateArray())
            {
                Assert.InRange(day.GetProperty("totalCalories").GetInt32(), target * 0.8, target * 1.2);
            }

            var added = await _qa.PostAsync("/meal-plans/current/meals", user, new { date = Qa.Today(), slot = "snack_pm", name = "Chuối", calories = 100 });
            Assert.Equal(JsonValueKind.Null, added.Data.GetProperty("meals").GetProperty("snack_pm").GetProperty("prepMinutes").ValueKind);

            var recipe = await _qa.PostAsync("/recipes", user, new { name = "Rau không ghi giờ", calories = 100 });
            Assert.Equal(JsonValueKind.Null, recipe.Data.GetProperty("prepMinutes").ValueKind);
        }

        /* ------------------------------------------------------------ người dùng --- */

        [MongoFact]
        public async Task B56_B57_B58_B59_B60_User_edits_and_deletes_are_guarded()
        {
            var admin = await _qa.AdminAsync();
            var user = await _qa.UserAsync();

            // PUT không đổi được role, status, email (đổi qua PATCH, xem test của 5.10).
            var edited = await _qa.PutAsync($"/users/{user.Id}", user, new { fullName = "Tên mới", role = "Admin", status = 2, email = "khac@test.vn" });
            Qa.IsOk(edited);
            Assert.Equal("User", edited.Str("role"));
            Assert.Equal(user.Email, edited.Str("email"));
            Assert.Equal("Active", edited.Str("status"));

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/users/{user.Id}", user, new { fullName = new string('a', 4000) }));

            var noPhone = await _qa.PutAsync($"/users/{user.Id}", user, new { fullName = "Tên mới", phone = "" });
            Qa.IsOk(noPhone);
            Assert.Equal("", noPhone.Str("phone"));

            var self = await _qa.DeleteAsync($"/users/{admin.Id}", admin);
            Qa.Is(HttpStatusCode.BadRequest, self, "self_action");

            // Bài của người đã xoá không lộ tên thật.
            var author = await _qa.UserAsync(name: "Tên Thật Của Tác Giả");
            var postId = await _qa.NewPostAsync(author);
            Qa.IsOk(await _qa.DeleteAsync($"/users/{author.Id}", admin));
            Assert.Equal("Thành viên", (await _qa.GetAsync($"/posts/{postId}")).Data.GetProperty("author").GetProperty("fullName").GetString());
        }
    }

    /// <summary>Lối đọc mã đặt lại mật khẩu chỉ tồn tại khi vừa ở Development, vừa bật cấu hình.</summary>
    public class Sprint10_ResetCodeGateTests
    {
        [MongoFact]
        public async Task Without_the_flag_there_is_no_way_to_read_a_code()
        {
            using var factory = new NoDevCodesFactory();
            var qa = new Qa(factory);
            var user = await qa.UserAsync();
            Qa.Is(HttpStatusCode.NoContent, await qa.PostAsync("/auth/forgot-password", null, new { email = user.Email }));
            Qa.Is(HttpStatusCode.NotFound, await qa.GetAsync($"/dev/auth/reset-code?email={Uri.EscapeDataString(user.Email)}"));
        }

        [MongoFact]
        public async Task In_production_there_is_no_way_to_read_a_code_even_with_the_flag_and_errors_carry_no_detail()
        {
            using var factory = new ProductionFactory();
            var qa = new Qa(factory);
            var user = await qa.UserAsync();
            Qa.Is(HttpStatusCode.NoContent, await qa.PostAsync("/auth/forgot-password", null, new { email = user.Email }));
            Qa.Is(HttpStatusCode.NotFound, await qa.GetAsync($"/dev/auth/reset-code?email={Uri.EscapeDataString(user.Email)}"));

            var refused = await qa.PostAsync("/auth/refresh", null, new { refreshToken = "nope" });
            Qa.Is(HttpStatusCode.Unauthorized, refused);
            Assert.False(refused.HasDetail);
            Assert.DoesNotContain("   at ", refused.Text);

            var noGender = await qa.PutAsync("/health-profile/me", user, new { heightCm = 170, weightKg = 66, birthYear = 1998 });
            Qa.Is(HttpStatusCode.BadRequest, noGender);
            Assert.False(noGender.HasDetail);
            Assert.DoesNotContain("DomainLayer", noGender.Text);

            Assert.Equal(HttpStatusCode.NotFound, (await qa.CallAsync(HttpMethod.Get, "/api/v1/swagger/v1/swagger.json")).Status);
        }

        [Fact]
        public async Task A_notifier_gets_the_code_and_an_unknown_email_gets_nothing()
        {
            var repo = new Mock<DomainLayer.Interfaces.IGenericRepository<User>>();
            var known = new User { Id = "507f1f77bcf86cd799439011", Email = "a@test.vn", EmailNormalized = "a@test.vn" };
            repo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<System.Linq.Expressions.Expression<Func<User, bool>>>()))
                .ReturnsAsync(known);
            var notifier = new Mock<IPasswordResetNotifier>();
            notifier.SetupGet(n => n.CanDeliver).Returns(true);
            var service = new AuthService(repo.Object, new Mock<Microsoft.Extensions.Configuration.IConfiguration>().Object, notifier.Object);

            await service.ForgotPasswordAsync(new ForgotPasswordRequest { Email = "A@test.vn" });
            notifier.Verify(n => n.SendAsync("a@test.vn", It.Is<string>(c => c.Length == 6)), Times.Once);

            repo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<System.Linq.Expressions.Expression<Func<User, bool>>>()))
                .ReturnsAsync((User?)null);
            await service.ForgotPasswordAsync(new ForgotPasswordRequest { Email = "khong@test.vn" });
            notifier.Verify(n => n.SendAsync("khong@test.vn", It.IsAny<string>()), Times.Never);
        }
    }
}
