using System.Net;
using System.Text.Json;
using DomainLayer.Entities;
using MongoDB.Driver;
using VeganLife.Tests.Fixtures;
using Xunit;

namespace VeganLife.Tests
{
    /// <summary>Route mới của mục 5.1, 5.2, 5.10, 5.11: chức năng và phân quyền ở mức API (sai người, sai vai trò, khách).</summary>
    public class Sprint10_NewRoutesTests : IClassFixture<QaFactory>
    {
        private readonly Qa _qa;

        public Sprint10_NewRoutesTests(QaFactory factory) => _qa = new Qa(factory);

        private const string AnyId = "0123456789abcdef01234567";

        public static IEnumerable<object[]> MemberRoutes => new[]
        {
            new object[] { "PUT", $"/posts/{AnyId}" },
            new object[] { "GET", "/users/me/posts" },
            new object[] { "GET", "/users/me/saved-posts" },
            new object[] { "POST", $"/posts/{AnyId}/save" },
            new object[] { "PUT", $"/posts/{AnyId}/comments/{AnyId}" },
            new object[] { "GET", "/users/me/comments" },
            new object[] { "PUT", $"/recipes/{AnyId}" },
            new object[] { "DELETE", $"/recipes/{AnyId}" },
            new object[] { "POST", $"/recipes/{AnyId}/variants" },
            new object[] { "PUT", $"/recipes/{AnyId}/reviews/me" },
            new object[] { "DELETE", $"/recipes/{AnyId}/reviews/me" },
            new object[] { "GET", $"/recipes/{AnyId}/notes/me" },
            new object[] { "PUT", $"/recipes/{AnyId}/notes/me" },
            new object[] { "DELETE", $"/recipes/{AnyId}/notes/me" },
            new object[] { "POST", "/meal-plans/current/adjust" },
            new object[] { "POST", $"/meal-plans/current/adjust/{AnyId}/apply" },
            new object[] { "GET", "/meal-plans/chef-suggestions" },
            new object[] { "GET", "/users/me/recipes" },
        };

        public static IEnumerable<object[]> AdminRoutes => new[]
        {
            new object[] { "GET", "/admin/comments" },
            new object[] { "DELETE", $"/admin/comments/{AnyId}" },
            new object[] { "POST", $"/admin/comments/{AnyId}/actions" },
            new object[] { "PATCH", $"/users/{AnyId}/role" },
            new object[] { "PATCH", $"/users/{AnyId}/status" },
            new object[] { "GET", "/users" },
        };

        private static object BodyFor(string method) => method is "GET" or "DELETE" ? null! : new { };

        [MongoTheory]
        [MemberData(nameof(MemberRoutes))]
        public async Task Guests_cannot_use_member_routes(string method, string path)
        {
            var res = await _qa.CallAsync(new HttpMethod(method), path, null, BodyFor(method));
            Qa.Is(HttpStatusCode.Unauthorized, res, "unauthorized");
        }

        [MongoTheory]
        [MemberData(nameof(AdminRoutes))]
        public async Task Guests_cannot_use_admin_routes(string method, string path)
        {
            var res = await _qa.CallAsync(new HttpMethod(method), path, null, BodyFor(method));
            Qa.Is(HttpStatusCode.Unauthorized, res, "unauthorized");
        }

        [MongoTheory]
        [MemberData(nameof(AdminRoutes))]
        public async Task Members_and_chefs_cannot_use_admin_routes(string method, string path)
        {
            foreach (var role in new[] { "User", "Chef" })
            {
                var res = await _qa.CallAsync(new HttpMethod(method), path, await _qa.UserAsync(role), BodyFor(method));
                Qa.Is(HttpStatusCode.Forbidden, res, "forbidden");
            }
        }

        /* ------------------------------------------------------------ 5.1 --- */

        [MongoFact]
        public async Task Put_post_edits_only_your_own_and_keeps_published_when_approval_is_off()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var id = await _qa.NewPostAsync(author);
            var edit = new { type = "recipe", title = "Đã sửa", body = "Nội dung đã sửa", tags = new[] { "chay" }, mediaType = "Text" };

            Qa.Is(HttpStatusCode.Forbidden, await _qa.PutAsync($"/posts/{id}", other, edit));
            Qa.Is(HttpStatusCode.Forbidden, await _qa.PutAsync($"/posts/{id}", admin, edit));
            Qa.Is(HttpStatusCode.Unauthorized, await _qa.PutAsync($"/posts/{id}", null, edit));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/posts/{AnyId}", author, edit));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/posts/{id}", author, new { type = "XYZ", title = "A", body = "B" }));

            var saved = await _qa.PutAsync($"/posts/{id}", author, edit);
            Qa.Is(HttpStatusCode.OK, saved);
            Assert.Equal("Đã sửa", saved.Str("title"));
            Assert.Equal("recipe", saved.Str("type"));
            Assert.Equal("Published", saved.Str("status"));
            Assert.NotEqual(JsonValueKind.Null, saved.Data.GetProperty("updatedAt").ValueKind);
        }

        [MongoFact]
        public async Task Put_post_cannot_undo_an_admin_decision()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var edit = new { type = "discussion", title = "Đã sửa", body = "Nội dung", mediaType = "Text" };

            var hidden = await _qa.NewPostAsync(author);
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{hidden}/actions", admin, new { action = "hide" }));
            Qa.Is(HttpStatusCode.Conflict, await _qa.PutAsync($"/posts/{hidden}", author, edit), "post_hidden");
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/posts/{hidden}", other, edit));

            var rejected = await _qa.NewPostAsync(author);
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{rejected}/review", admin, new { decision = "Reject", reason = "Sai chủ đề" }));
            var resent = await _qa.PutAsync($"/posts/{rejected}", author, edit);
            Assert.Equal("Pending", resent.Str("status"));
            Assert.Equal(JsonValueKind.Null, resent.Data.GetProperty("rejectionReason").ValueKind);
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{rejected}"));
        }

        [MongoFact]
        public async Task Put_post_takes_only_media_you_own_but_keeps_the_one_it_has()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var id = await _qa.NewPostAsync(author);
            await _qa.Db.Posts.UpdateOneAsync(p => p.Id == id, MongoDB.Driver.Builders<Post>.Update.Set(p => p.MediaUrl, "/uploads/images/cu.png").Set(p => p.MediaType, "Image"));
            await _qa.Db.MediaAssets.InsertOneAsync(new MediaAsset { OwnerId = other.Id, Url = "/uploads/images/nguoi-khac.png", PublicId = Guid.NewGuid().ToString("N"), CreatedAt = DateTime.UtcNow });

            Qa.IsOk(await _qa.PutAsync($"/posts/{id}", author, new { type = "discussion", title = "Giữ ảnh", body = "Nội dung", mediaType = "Image", mediaUrl = "/uploads/images/cu.png" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/posts/{id}", author, new { type = "discussion", title = "Ảnh lạ", body = "Nội dung", mediaType = "Image", mediaUrl = "/uploads/images/nguoi-khac.png" }));
        }

        [MongoFact]
        public async Task My_posts_lists_every_status_for_me_only_with_cursor_and_status_filter()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var published = await _qa.NewPostAsync(author, "Bài một");
            var rejected = await _qa.NewPostAsync(author, "Bài hai");
            var hidden = await _qa.NewPostAsync(author, "Bài ba");
            var foreign = await _qa.NewPostAsync(other, "Bài người khác");
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{rejected}/review", admin, new { decision = "Reject", reason = "Lý do" }));
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{hidden}/actions", admin, new { action = "hide" }));

            var page = await _qa.GetAsync("/users/me/posts?limit=2", author);
            var first = page.Data.GetProperty("items").EnumerateArray().Select(p => p.GetProperty("id").GetString()).ToList();
            Assert.Equal(new[] { hidden, rejected }, first);
            var cursor = page.Str("nextCursor");

            var next = await _qa.GetAsync($"/users/me/posts?limit=2&cursor={cursor}", author);
            Assert.Equal(new[] { published }, next.Data.GetProperty("items").EnumerateArray().Select(p => p.GetProperty("id").GetString()));
            Assert.Equal(JsonValueKind.Null, next.Data.GetProperty("nextCursor").ValueKind);

            var onlyRejected = await _qa.GetAsync("/users/me/posts?status=rejected", author);
            var row = onlyRejected.Data.GetProperty("items").EnumerateArray().Single();
            Assert.Equal(rejected, row.GetProperty("id").GetString());
            Assert.Equal("Lý do", row.GetProperty("rejectionReason").GetString());

            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/users/me/posts?status=Nope", author));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/users/me/posts?cursor=khong-phai-id", author));
            Assert.DoesNotContain(foreign, (await _qa.GetAsync("/users/me/posts", author)).Text);
        }

        [MongoFact]
        public async Task Save_toggles_shows_in_saved_posts_and_follows_visibility()
        {
            var author = await _qa.UserAsync();
            var reader = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var id = await _qa.NewPostAsync(author);

            Assert.True((await _qa.PostAsync($"/posts/{id}/save", reader)).Data.GetProperty("saved").GetBoolean());
            Assert.True((await _qa.GetAsync($"/posts/{id}", reader)).Data.GetProperty("savedByMe").GetBoolean());
            Assert.False((await _qa.GetAsync($"/posts/{id}", author)).Data.GetProperty("savedByMe").GetBoolean());
            Assert.Equal(id, (await _qa.GetAsync("/users/me/saved-posts", reader)).Data[0].GetProperty("id").GetString());
            Assert.Equal(1, (await _qa.GetAsync("/users/me", reader)).Data.GetProperty("stats").GetProperty("saved").GetInt32());
            Assert.Equal(0, (await _qa.GetAsync("/users/me/saved-posts", author)).Data.GetArrayLength());

            var feed = await _qa.GetAsync("/posts?limit=50", reader);
            Assert.True(feed.Data.GetProperty("items").EnumerateArray().Single(p => p.GetProperty("id").GetString() == id).GetProperty("savedByMe").GetBoolean());

            // Bị ẩn: biến khỏi danh sách nhưng vẫn bỏ lưu được; bỏ ẩn thì quay lại.
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "hide" }));
            Assert.Equal(0, (await _qa.GetAsync("/users/me/saved-posts", reader)).Data.GetArrayLength());
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "unhide" }));
            Assert.Equal(1, (await _qa.GetAsync("/users/me/saved-posts", reader)).Data.GetArrayLength());

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/actions", admin, new { action = "hide" }));
            Assert.False((await _qa.PostAsync($"/posts/{id}/save", reader)).Data.GetProperty("saved").GetBoolean());
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{id}/save", reader));

            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/posts/{AnyId}/save", reader));
        }

        [MongoFact]
        public async Task Put_comment_is_for_its_author_on_that_post()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var post = await _qa.NewPostAsync(other);
            var elsewhere = await _qa.NewPostAsync(other);
            var id = await _qa.NewCommentAsync(author, post);

            Qa.Is(HttpStatusCode.Forbidden, await _qa.PutAsync($"/posts/{post}/comments/{id}", other, new { content = "Của tôi" }));
            Qa.Is(HttpStatusCode.Forbidden, await _qa.PutAsync($"/posts/{post}/comments/{id}", admin, new { content = "Của tôi" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/posts/{elsewhere}/comments/{id}", author, new { content = "Sai bài" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/posts/{post}/comments/{AnyId}", author, new { content = "Không có" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/posts/{post}/comments/{id}", author, new { content = "" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/posts/{post}/comments/{id}", author, new { content = new string('a', 501) }));

            var saved = await _qa.PutAsync($"/posts/{post}/comments/{id}", author, new { content = " Đã sửa " });
            Qa.Is(HttpStatusCode.OK, saved);
            Assert.Equal("Đã sửa", saved.Str("content"));
            Assert.NotEqual(JsonValueKind.Null, saved.Data.GetProperty("updatedAt").ValueKind);
            Assert.Equal(post, saved.Str("postId"));

            var listed = await _qa.GetAsync($"/posts/{post}/comments");
            Assert.NotEqual(JsonValueKind.Null, listed.Data[0].GetProperty("updatedAt").ValueKind);

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{post}/actions", admin, new { action = "hide" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/posts/{post}/comments/{id}", author, new { content = "Sau khi ẩn" }));
        }

        [MongoFact]
        public async Task My_comments_are_mine_and_do_not_leak_a_hidden_title()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var post = await _qa.NewPostAsync(other, "Tiêu đề sắp bị ẩn");
            var root = await _qa.NewCommentAsync(author, post, "Của tôi");
            await _qa.NewCommentAsync(other, post, "Của người khác");
            var gone = await _qa.NewPostAsync(other, "Bài sắp xoá");
            await _qa.NewCommentAsync(author, gone, "Trên bài đã xoá");
            Qa.IsOk(await _qa.DeleteAsync($"/posts/{gone}", other));

            var mine = await _qa.GetAsync("/users/me/comments", author);
            var row = mine.Data.EnumerateArray().Single();
            Assert.Equal(root, row.GetProperty("id").GetString());
            Assert.Equal(post, row.GetProperty("postId").GetString());
            Assert.Equal("Tiêu đề sắp bị ẩn", row.GetProperty("postTitle").GetString());
            Assert.Equal("Của tôi", row.GetProperty("content").GetString());

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{post}/actions", admin, new { action = "hide" }));
            var after = await _qa.GetAsync("/users/me/comments", author);
            Assert.DoesNotContain("Tiêu đề sắp bị ẩn", after.Text);
            Assert.Equal(1, after.Data.GetArrayLength());
        }

        [MongoFact]
        public async Task Admin_comments_list_filter_hide_unhide_and_delete_with_counts()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync(name: "Người Viết Riêng");
            var post = await _qa.NewPostAsync(author, "Bài của admin test");
            var marker = $"noi-dung-{Guid.NewGuid():N}";
            var root = await _qa.NewCommentAsync(author, post, marker);
            var reply = await _qa.NewCommentAsync(author, post, "Phản hồi", root);

            var listed = await _qa.GetAsync($"/admin/comments?view=all&search={marker.ToUpperInvariant()}", admin);
            var row = listed.Data.EnumerateArray().Single();
            Assert.Equal(root, row.GetProperty("id").GetString());
            Assert.Equal("Bài của admin test", row.GetProperty("postTitle").GetString());
            Assert.Equal("Visible", row.GetProperty("status").GetString());
            Assert.Equal(author.Id, row.GetProperty("author").GetProperty("id").GetString());
            Assert.Equal(1, row.GetProperty("replyCount").GetInt32());
            Assert.Equal(2, (await _qa.GetAsync($"/admin/comments?authorId={author.Id}", admin)).Data.GetArrayLength());
            Assert.Equal(2, (await _qa.GetAsync($"/admin/comments?postId={post}", admin)).Data.GetArrayLength());
            var replyRow = (await _qa.GetAsync($"/admin/comments?postId={post}", admin)).Data.EnumerateArray().Single(c => c.GetProperty("id").GetString() == reply);
            Assert.Equal("Người Viết Riêng", replyRow.GetProperty("replyTo").GetProperty("authorName").GetString());

            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/admin/comments?view=khong-co", admin));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/admin/comments?authorId=khong-phai-id", admin));

            var hidden = await _qa.PostAsync($"/admin/comments/{root}/actions", admin, new { action = "hide" });
            Assert.Equal("Hidden", hidden.Str("status"));
            Assert.Equal(0, (await _qa.GetAsync($"/posts/{post}/comments")).Data.GetArrayLength());
            Assert.Equal(0, (await _qa.GetAsync($"/posts/{post}")).Data.GetProperty("commentCount").GetInt32());
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/comments/{root}/replies"));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/posts/{post}/comments/{root}", author, new { content = "Sửa" }));
            Assert.Contains((await _qa.GetAsync($"/admin/comments?view=hidden&postId={post}", admin)).Data.EnumerateArray(), c => c.GetProperty("id").GetString() == root);

            Qa.IsOk(await _qa.PostAsync($"/admin/comments/{root}/actions", admin, new { action = "unhide" }));
            Assert.Equal(1, (await _qa.GetAsync($"/posts/{post}/comments")).Data.GetArrayLength());
            Assert.Equal(2, (await _qa.GetAsync($"/posts/{post}")).Data.GetProperty("commentCount").GetInt32());

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/admin/comments/{root}/actions", admin, new { action = "delete" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/admin/comments/{AnyId}/actions", admin, new { action = "hide" }));

            Qa.IsOk(await _qa.DeleteAsync($"/admin/comments/{root}", admin, new { reason = "Vi phạm" }));
            Assert.Equal(0, (await _qa.GetAsync($"/posts/{post}")).Data.GetProperty("commentCount").GetInt32());
            Qa.Is(HttpStatusCode.NotFound, await _qa.DeleteAsync($"/admin/comments/{root}", admin));
            var stored = await MongoDB.Driver.IAsyncCursorSourceExtensions.FirstAsync(MongoDB.Driver.IMongoCollectionExtensions.Find(_qa.Db.Comments, c => c.Id == root));
            Assert.Equal("Vi phạm", stored.DeleteReason);
        }

        [MongoFact]
        public async Task Admin_can_delete_a_comment_with_an_empty_body()
        {
            var admin = await _qa.AdminAsync();
            var author = await _qa.UserAsync();
            var post = await _qa.NewPostAsync(author);
            var id = await _qa.NewCommentAsync(author, post);
            Qa.IsOk(await _qa.DeleteAsync($"/admin/comments/{id}", admin));
        }

        /* ------------------------------------------------------------ 5.2 --- */

        [MongoFact]
        public async Task Catalog_is_public_pages_by_cursor_and_hides_private_recipes()
        {
            var owner = await _qa.UserAsync();
            var privateName = $"Rau riêng tư {Guid.NewGuid():N}";
            var privateId = await _qa.OwnRecipeAsync(owner, privateName);

            var first = await _qa.GetAsync("/recipes?limit=5");
            Qa.Is(HttpStatusCode.OK, first);
            Assert.Equal(5, first.Data.GetProperty("items").GetArrayLength());
            var cursor = first.Str("nextCursor");
            var next = await _qa.GetAsync($"/recipes?limit=5&cursor={cursor}");
            Assert.Empty(first.Data.GetProperty("items").EnumerateArray().Select(r => r.GetProperty("id").GetString())
                .Intersect(next.Data.GetProperty("items").EnumerateArray().Select(r => r.GetProperty("id").GetString())));

            var all = await _qa.GetAsync("/recipes?limit=200", owner);
            Assert.DoesNotContain(privateId, all.Text);
            Assert.Contains(privateId, (await _qa.GetAsync("/users/me/recipes", owner)).Text);

            var found = await _qa.GetAsync("/recipes?q=bun rieu&limit=50");
            Assert.All(found.Data.GetProperty("items").EnumerateArray(), r => Assert.Contains("riêu", r.GetProperty("name").GetString(), StringComparison.OrdinalIgnoreCase));
            Assert.NotEqual(0, found.Data.GetProperty("items").GetArrayLength());

            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/recipes?cursor=khong-phai-id"));
        }

        [MongoFact]
        public async Task Recipe_detail_is_public_except_private_ones()
        {
            var owner = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var systemId = await _qa.SystemRecipeIdAsync();
            var privateId = await _qa.OwnRecipeAsync(owner);

            Qa.Is(HttpStatusCode.OK, await _qa.GetAsync($"/recipes/{systemId}"));
            Qa.Is(HttpStatusCode.OK, await _qa.GetAsync($"/recipes/{privateId}", owner));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{privateId}", other));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{privateId}"));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{privateId}", await _qa.AdminAsync()));
        }

        private static object FullRecipe(string name = "Bún riêu thử", string? basedOn = null) => new
        {
            name,
            calories = 500,
            servings = 2,
            basedOnRecipeId = basedOn,
            allergens = new[] { "soy" },
            ingredients = new[] { "Đậu hũ 200 g", "Rau muống" },
            instructions = new[] { "Nấu" },
            ingredientItems = new object[]
            {
                new
                {
                    key = "dau_hu", name = "Đậu hũ", quantity = 200, unit = "g", role = "Riêu", isSignature = true, allergens = new[] { "soy" },
                    nutrition = new { calories = 152, proteinG = 16.2, carbsG = 3.8, fatG = 9.6, fiberG = 0.6 },
                    substitutes = new object[]
                    {
                        new { key = "dau_hu_non", name = "Đậu hũ non", quantity = 280, unit = "g", role = "Riêu", allergens = new[] { "soy" }, nutrition = new { calories = 154, proteinG = 14.0, carbsG = 4.2, fatG = 8.4, fiberG = 0.5 } },
                        new { key = "nam", name = "Nấm rơm", quantity = 200, unit = "g", role = "Khác", allergens = Array.Empty<string>(), nutrition = new { calories = 64, proteinG = 6.8, carbsG = 8.4, fatG = 0.6, fiberG = 3.0 } }
                    }
                },
                new
                {
                    key = "rau", name = "Rau muống", quantity = 100, unit = "g", role = "Rau", isSignature = false, allergens = Array.Empty<string>(),
                    nutrition = new { calories = 25, proteinG = 2.0, carbsG = 3.0, fatG = 0.2, fiberG = 2.0 },
                    substitutes = Array.Empty<object>()
                }
            }
        };

        [MongoFact]
        public async Task Own_recipes_take_the_new_fields_and_put_delete_are_for_the_owner_only()
        {
            var owner = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var systemId = await _qa.SystemRecipeIdAsync();

            var created = await _qa.PostAsync("/recipes", owner, FullRecipe(basedOn: systemId));
            Qa.Is(HttpStatusCode.Created, created);
            var id = created.Str("id");
            Assert.Equal(2, created.Data.GetProperty("servings").GetInt32());
            Assert.Equal(systemId, created.Str("basedOnRecipeId"));
            Assert.Equal("dau_hu", created.Data.GetProperty("ingredientItems")[0].GetProperty("key").GetString());
            Assert.Equal(owner.Id, created.Str("createdBy"));

            var plain = await _qa.PostAsync("/recipes", owner, new { name = "Rau luộc", calories = 50 });
            Assert.False(plain.Data.TryGetProperty("ingredientItems", out _));

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", owner, new { name = "Rau", calories = 1, basedOnRecipeId = AnyId }), "invalid_based_on");
            var otherPrivate = await _qa.OwnRecipeAsync(other);
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", owner, new { name = "Rau", calories = 1, basedOnRecipeId = otherPrivate }), "invalid_based_on");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", owner, new
            {
                name = "Rau", calories = 1,
                ingredientItems = new[] { new { key = "a", name = "Gelatin" } }
            }), "not_vegan");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/recipes", owner, new { name = "Rau", calories = 1, imageUrl = "javascript:alert(1)" }), "invalid_image");

            var edit = new { name = "Bún riêu đã sửa", calories = 450, ingredients = new[] { "Đậu hũ" }, instructions = new[] { "Nấu lại" } };
            foreach (var who in new[] { other, admin })
            {
                Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/recipes/{id}", who, edit));
                Qa.Is(HttpStatusCode.NotFound, await _qa.DeleteAsync($"/recipes/{id}", who));
                Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/recipes/{systemId}", who, edit));
                Qa.Is(HttpStatusCode.NotFound, await _qa.DeleteAsync($"/recipes/{systemId}", who));
            }
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/recipes/{systemId}", owner, edit));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{id}", owner, new { }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{id}", owner, new { name = "Thịt bò", calories = 1 }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{id}", owner, new { name = "Rau", calories = -1 }));

            var updated = await _qa.PutAsync($"/recipes/{id}", owner, edit);
            Qa.Is(HttpStatusCode.OK, updated);
            Assert.Equal("Bún riêu đã sửa", updated.Str("name"));
            Assert.Equal(450, updated.Data.GetProperty("calories").GetInt32());

            Qa.Is(HttpStatusCode.OK, await _qa.DeleteAsync($"/recipes/{id}", owner));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{id}", owner));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/recipes/{id}", owner, edit));
            Qa.Is(HttpStatusCode.NotFound, await _qa.DeleteAsync($"/recipes/{id}", owner));
            Assert.DoesNotContain(id, (await _qa.GetAsync("/users/me/recipes", owner)).Text);

            var stored = await MongoDB.Driver.IAsyncCursorSourceExtensions.FirstAsync(MongoDB.Driver.IMongoCollectionExtensions.Find(_qa.Db.Recipes, r => r.Id == id));
            Assert.True(stored.IsDeleted);
        }

        /* ------------------------------------------------------------ 5.11 --- */

        [MongoFact]
        public async Task Variants_apply_swaps_recompute_and_refuse_bad_ones()
        {
            var owner = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var baseId = (await _qa.PostAsync("/recipes", owner, FullRecipe())).Str("id");
            var systemId = await _qa.SystemRecipeIdAsync();

            var swap = new[] { new { ingredientKey = "dau_hu", substituteKey = "dau_hu_non" } };
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/recipes/{baseId}/variants", other, new { name = "Của tôi", swaps = swap }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "A", swaps = swap }), "invalid_name");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = new string('a', 81), swaps = swap }), "invalid_name");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "Không đổi" }), "no_changes");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "Bỏ đặc trưng", removed = new[] { "dau_hu" } }), "signature_required");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "Sai vai trò", swaps = new[] { new { ingredientKey = "dau_hu", substituteKey = "nam" } } }), "signature_required");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "Sai thay thế", swaps = new[] { new { ingredientKey = "dau_hu", substituteKey = "khong_co" } } }), "invalid_substitute");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "Sai dòng", removed = new[] { "khong_co" } }), "invalid_substitute");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/recipes/{systemId}/variants", owner, new { name = "Chưa có bảng", removed = new[] { "rau" } }), "invalid_substitute");

            var created = await _qa.PostAsync($"/recipes/{baseId}/variants", owner, new { name = "Bún riêu của tôi", swaps = swap, removed = new[] { "rau" } });
            Qa.Is(HttpStatusCode.Created, created);
            Assert.Equal(baseId, created.Str("basedOnRecipeId"));
            Assert.Equal("Bún riêu thử", created.Str("basedOnName"));
            Assert.Equal(154, created.Data.GetProperty("calories").GetInt32());
            Assert.False(created.Data.GetProperty("nutritionEstimated").GetBoolean());
            Assert.Equal("soy", created.Data.GetProperty("allergens")[0].GetString());
            var notes = created.Data.GetProperty("customizations").EnumerateArray().ToList();
            Assert.Contains(notes, n => n.GetProperty("type").GetString() == "swap" && n.GetProperty("to").GetString() == "Đậu hũ non");
            Assert.Contains(notes, n => n.GetProperty("type").GetString() == "remove" && n.GetProperty("name").GetString() == "Rau muống");

            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{created.Str("id")}", other));
            Assert.Contains(created.Str("id"), (await _qa.GetAsync("/users/me/recipes", owner)).Text);
        }

        [MongoFact]
        public async Task Reviews_are_one_per_member_public_to_read_and_closed_on_private_recipes()
        {
            var recipe = await _qa.SystemRecipeIdAsync();
            var created = await _qa.PostAsync("/recipes", await _qa.UserAsync(), new { name = "Rau cho đánh giá", calories = 1 });
            var owner = await _qa.UserAsync();
            var ownRecipe = await _qa.OwnRecipeAsync(owner);
            var reviewer = await _qa.UserAsync(name: "Người Đánh Giá");
            var second = await _qa.UserAsync("Chef", "Chuyên Gia");

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{recipe}/reviews/me", reviewer, new { rating = 6 }), "invalid_rating");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{recipe}/reviews/me", reviewer, new { rating = 0 }), "invalid_rating");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{recipe}/reviews/me", reviewer, new { rating = 4, content = "ngắn" }), "invalid_content");
            Qa.Is(HttpStatusCode.Forbidden, await _qa.PutAsync($"/recipes/{ownRecipe}/reviews/me", owner, new { rating = 5 }), "own_recipe");
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/recipes/{ownRecipe}/reviews/me", reviewer, new { rating = 5 }), "private_recipe");
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{ownRecipe}/reviews", owner), "private_recipe");
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{ownRecipe}/reviews"), "private_recipe");
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{AnyId}/reviews"));

            var first = await _qa.PutAsync($"/recipes/{recipe}/reviews/me", reviewer, new { rating = 5, content = "Món này rất ngon và dễ nấu." });
            Qa.Is(HttpStatusCode.OK, first);
            Assert.Equal(5, first.Data.GetProperty("review").GetProperty("rating").GetInt32());
            Assert.Equal(1, first.Data.GetProperty("ratingCount").GetInt32());

            var replaced = await _qa.PutAsync($"/recipes/{recipe}/reviews/me", reviewer, new { rating = 3, content = (string?)null });
            Assert.Equal(1, replaced.Data.GetProperty("ratingCount").GetInt32());
            Assert.Equal(3, replaced.Data.GetProperty("averageRating").GetDouble());

            Qa.IsOk(await _qa.PutAsync($"/recipes/{recipe}/reviews/me", second, new { rating = 4 }));

            var guestPage = await _qa.GetAsync($"/recipes/{recipe}/reviews");
            Assert.Equal(JsonValueKind.Null, guestPage.Data.GetProperty("myReview").ValueKind);
            Assert.Equal(2, guestPage.Data.GetProperty("items").GetArrayLength());
            Assert.Equal(3.5, guestPage.Data.GetProperty("averageRating").GetDouble());
            Assert.Equal(1, guestPage.Data.GetProperty("distribution").GetProperty("4").GetInt32());
            Assert.True(guestPage.Data.GetProperty("items")[0].GetProperty("author").GetProperty("isVerifiedChef").GetBoolean());

            var myPage = await _qa.GetAsync($"/recipes/{recipe}/reviews?limit=1", reviewer);
            Assert.Equal(3, myPage.Data.GetProperty("myReview").GetProperty("rating").GetInt32());
            Assert.Equal(1, myPage.Data.GetProperty("items").GetArrayLength());
            Assert.DoesNotContain(reviewer.Id, myPage.Data.GetProperty("items").GetRawText());

            Assert.Equal(2, (await _qa.GetAsync($"/recipes/{recipe}")).Data.GetProperty("ratingCount").GetInt32());

            var deleted = await _qa.DeleteAsync($"/recipes/{recipe}/reviews/me", reviewer);
            Qa.Is(HttpStatusCode.OK, deleted);
            Assert.Equal(1, deleted.Data.GetProperty("ratingCount").GetInt32());
            Assert.Equal(4, deleted.Data.GetProperty("averageRating").GetDouble());
            Qa.Is(HttpStatusCode.OK, await _qa.DeleteAsync($"/recipes/{recipe}/reviews/me", reviewer));
            Assert.Equal(1, (await _qa.GetAsync($"/recipes/{recipe}/reviews")).Data.GetProperty("ratingCount").GetInt32());
            Qa.IsOk(created);
            Qa.IsOk(await _qa.DeleteAsync($"/recipes/{recipe}/reviews/me", second));
        }

        [MongoFact]
        public async Task Notes_belong_to_one_person()
        {
            var me = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var recipe = await _qa.SystemRecipeIdAsync();
            var myPrivate = await _qa.OwnRecipeAsync(me);

            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{recipe}/notes/me", me));

            var saved = await _qa.PutAsync($"/recipes/{recipe}/notes/me", me, new { content = " Bớt muối " });
            Qa.Is(HttpStatusCode.OK, saved);
            Assert.Equal("Bớt muối", saved.Str("content"));
            Assert.Equal(recipe, saved.Str("recipeId"));

            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{recipe}/notes/me", other));
            Assert.Equal("Bớt muối", (await _qa.GetAsync($"/recipes/{recipe}/notes/me", me)).Str("content"));

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PutAsync($"/recipes/{recipe}/notes/me", me, new { content = new string('a', 2001) }), "invalid_content");

            var cleared = await _qa.PutAsync($"/recipes/{recipe}/notes/me", me, new { content = "" });
            Qa.Is(HttpStatusCode.OK, cleared);
            Assert.Equal(JsonValueKind.Null, cleared.Data.ValueKind);
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{recipe}/notes/me", me));

            Qa.IsOk(await _qa.PutAsync($"/recipes/{recipe}/notes/me", me, new { content = "Lại ghi" }));
            Qa.IsOk(await _qa.DeleteAsync($"/recipes/{recipe}/notes/me", me));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{recipe}/notes/me", me));

            Qa.IsOk(await _qa.PutAsync($"/recipes/{myPrivate}/notes/me", me, new { content = "Của công thức riêng" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PutAsync($"/recipes/{myPrivate}/notes/me", other, new { content = "Không được" }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{myPrivate}/notes/me", other));
        }

        [MongoFact]
        public async Task Related_posts_are_published_recipe_posts_that_name_it()
        {
            var author = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();
            var recipe = await _qa.GetAsync("/recipes?limit=1");
            var row = recipe.Data.GetProperty("items")[0];
            var recipeId = row.GetProperty("id").GetString();
            var name = row.GetProperty("name").GetString()!;

            var shown = await _qa.PostAsync("/posts", author, new { type = "recipe", title = $"Mình nấu {name}", body = "Ngon", mediaType = "Text" });
            var hidden = await _qa.PostAsync("/posts", author, new { type = "recipe", title = $"Bài ẩn {name}", body = "Ngon", mediaType = "Text" });
            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{hidden.Str("id")}/actions", admin, new { action = "hide" }));

            var related = await _qa.GetAsync($"/recipes/{recipeId}/related-posts");
            Assert.Contains(shown.Str("id"), related.Text);
            Assert.DoesNotContain(hidden.Str("id"), related.Text);

            var owner = await _qa.UserAsync();
            var mine = await _qa.OwnRecipeAsync(owner);
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/recipes/{mine}/related-posts"));
        }

        private async Task<(QaUser User, QaResult Plan)> PlanAsync(object[]? allergies = null)
        {
            var user = await _qa.UserAsync();
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody(allergies)));
            var plan = await _qa.PostAsync("/meal-plans/generate", user, new { startDate = Qa.ThisMonday() });
            Qa.IsOk(plan);
            return (user, plan);
        }

        [MongoFact]
        public async Task Adjust_proposes_without_changing_and_apply_is_once_for_the_owner()
        {
            var (user, plan) = await PlanAsync();
            var other = await _qa.UserAsync();
            var today = Qa.Today();

            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync("/meal-plans/current/adjust", other, new { message = "Ít calo hơn", scope = "day", date = today }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "x", scope = "day", date = today }), "invalid_message");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Ít calo hơn", scope = "thang", date = today }), "invalid_scope");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Ít calo hơn", scope = "day", date = "2000-01-01" }), "invalid_date");

            var unclear = await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Xin chào bạn", scope = "day", date = today });
            Assert.Equal(0, unclear.Data.GetProperty("changes").GetArrayLength());
            Assert.NotEmpty(unclear.Str("reply"));

            var before = (await _qa.GetAsync("/meal-plans/current", user)).Text;
            var proposal = await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Ít calo hơn cho hôm nay", scope = "week", date = today });
            Qa.Is(HttpStatusCode.OK, proposal);
            Assert.Equal(before, (await _qa.GetAsync("/meal-plans/current", user)).Text);

            var changes = proposal.Data.GetProperty("changes");
            Assert.NotEqual(0, changes.GetArrayLength());
            var change = changes[0];
            var changeId = change.GetProperty("id").GetString();
            Assert.True(change.GetProperty("kcalDelta").GetInt32() < 0);
            Assert.Equal("replace", change.GetProperty("action").GetString());
            var toId = change.GetProperty("to").GetProperty("id").GetString();
            var slot = change.GetProperty("slot").GetString()!;
            var date = change.GetProperty("date").GetString();
            var proposalId = proposal.Str("proposalId");

            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/meal-plans/current/adjust/{proposalId}/apply", other, new { changeIds = new[] { changeId } }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PostAsync($"/meal-plans/current/adjust/{AnyId}/apply", user, new { changeIds = new[] { changeId } }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/meal-plans/current/adjust/{proposalId}/apply", user, new { changeIds = Array.Empty<string>() }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PostAsync($"/meal-plans/current/adjust/{proposalId}/apply", user, new { changeIds = new[] { "c999" } }));

            var applied = await _qa.PostAsync($"/meal-plans/current/adjust/{proposalId}/apply", user, new { changeIds = new[] { changeId } });
            Qa.Is(HttpStatusCode.OK, applied);
            Assert.Equal(JsonValueKind.String, applied.Data.GetProperty("id").ValueKind);
            var day = applied.Data.GetProperty("days").EnumerateArray().Single(d => d.GetProperty("date").GetString() == date);
            Assert.Equal(toId, day.GetProperty("meals").GetProperty(slot).GetProperty("recipeId").GetString());

            Qa.Is(HttpStatusCode.Conflict, await _qa.PostAsync($"/meal-plans/current/adjust/{proposalId}/apply", user, new { changeIds = new[] { changeId } }), "already_applied");
        }

        [MongoFact]
        public async Task Apply_refuses_a_plan_that_moved_and_a_new_allergy()
        {
            var (user, plan) = await PlanAsync();
            var planId = plan.Str("id");
            var today = Qa.Today();

            var proposal = await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Ít calo hơn", scope = "week", date = today });
            var change = proposal.Data.GetProperty("changes")[0];
            var slot = change.GetProperty("slot").GetString();
            var date = change.GetProperty("date").GetString();

            Qa.IsOk(await _qa.DeleteAsync($"/meal-plans/{planId}/meals?date={date}&slot={slot}", user));
            Qa.Is(HttpStatusCode.Conflict, await _qa.PostAsync($"/meal-plans/current/adjust/{proposal.Str("proposalId")}/apply", user, new { changeIds = new[] { change.GetProperty("id").GetString() } }), "plan_changed");

            // Thêm dị ứng đúng món đề xuất sau khi đã có đề xuất: không được đưa món đó vào thực đơn.
            var second = await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Ít calo hơn", scope = "week", date = today });
            var target = second.Data.GetProperty("changes")[0];
            var targetName = target.GetProperty("to").GetProperty("name").GetString();
            Qa.IsOk(await _qa.PutAsync("/health-profile/me", user, Qa.ProfileBody(new object[] { new { name = targetName } })));
            Qa.Is(HttpStatusCode.Conflict, await _qa.PostAsync($"/meal-plans/current/adjust/{second.Str("proposalId")}/apply", user, new { changeIds = new[] { target.GetProperty("id").GetString() } }), "plan_changed");
        }

        [MongoFact]
        public async Task Adjust_never_proposes_what_the_member_is_allergic_to()
        {
            var (user, _) = await PlanAsync(new object[] { new { allergenId = "soy", name = "Đậu nành" } });
            var proposal = await _qa.PostAsync("/meal-plans/current/adjust", user, new { message = "Nhiều đạm hơn", scope = "week", date = Qa.Today() });
            foreach (var change in proposal.Data.GetProperty("changes").EnumerateArray())
            {
                Assert.DoesNotContain("soy", change.GetProperty("to").GetProperty("allergens").EnumerateArray().Select(a => a.GetString()));
            }
        }

        [MongoFact]
        public async Task Chef_suggestions_come_from_sent_days_of_my_bookings_only()
        {
            var member = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var chef = await _qa.UserAsync("Chef", "Lê Quang Tâm");
            await _qa.Db.Bookings.InsertOneAsync(new ChefBooking
            {
                MemberId = member.Id,
                ChefId = chef.Id,
                ChefName = chef.Name,
                Days = new List<BookingPlanDay>
                {
                    new()
                    {
                        DayIndex = 1, Date = "2026-11-05", Status = "Sent", SentAt = DateTime.UtcNow, ChefNote = "Uống đủ nước",
                        Meals = new List<BookingPlanMeal>
                        {
                            new() { Slot = "dinner", Note = "Ít muối", Recipe = new PlanRecipe { Name = "Canh chua chay", Calories = 480, Ingredients = new List<string> { "Đậu hũ" }, Instructions = "Nấu" } }
                        }
                    },
                    new()
                    {
                        DayIndex = 2, Date = "2026-11-06", Status = "Draft",
                        Meals = new List<BookingPlanMeal> { new() { Slot = "lunch", Recipe = new PlanRecipe { Name = "Bản nháp", Calories = 300 } } }
                    }
                }
            });

            var mine = await _qa.GetAsync("/meal-plans/chef-suggestions", member);
            Qa.Is(HttpStatusCode.OK, mine);
            var row = mine.Data.EnumerateArray().Single();
            Assert.Equal(chef.Id, row.GetProperty("chefId").GetString());
            Assert.Equal("Lê Quang Tâm", row.GetProperty("chefName").GetString());
            Assert.Equal("dinner", row.GetProperty("slot").GetString());
            Assert.Equal("2026-11-05", row.GetProperty("targetDate").GetString());
            Assert.Equal("Ít muối", row.GetProperty("note").GetString());
            Assert.Equal(480, row.GetProperty("recipe").GetProperty("calories").GetInt32());
            Assert.Matches("^[0-9a-f]{24}$", row.GetProperty("id").GetString()!);
            Assert.Equal(0, (await _qa.GetAsync("/meal-plans/chef-suggestions", other)).Data.GetArrayLength());
        }

        /* ------------------------------------------------------------ 5.10 --- */

        [MongoFact]
        public async Task Admin_cannot_lock_or_demote_or_delete_themselves()
        {
            var admin = await _qa.AdminAsync();
            Qa.Is(HttpStatusCode.Conflict, await _qa.PatchAsync($"/users/{admin.Id}/status", admin, new { status = "Locked", reason = "Thử" }), "self_action");
            Qa.Is(HttpStatusCode.Conflict, await _qa.PatchAsync($"/users/{admin.Id}/role", admin, new { role = "User" }), "self_action");
            Qa.Is(HttpStatusCode.BadRequest, await _qa.DeleteAsync($"/users/{admin.Id}", admin), "self_action");
            Qa.IsOk(await _qa.GetAsync("/users", admin));
        }

        [MongoFact]
        public async Task Locking_cuts_the_token_and_the_refresh_at_once_and_unlocking_restores_login()
        {
            var admin = await _qa.AdminAsync();
            var victim = await _qa.UserAsync();
            var login = await _qa.PostAsync("/auth/login", null, new { email = victim.Email, password = Qa.Password });
            Qa.IsOk(login);
            var token = login.Str("accessToken");
            Qa.IsOk(await _qa.CallAsync(HttpMethod.Get, "/users/me", token: token));

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/users/{victim.Id}/status", admin, new { status = "Bay" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/users/{victim.Id}/status", admin, new { }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PatchAsync($"/users/{AnyId}/status", admin, new { status = "Locked" }));

            var locked = await _qa.PatchAsync($"/users/{victim.Id}/status", admin, new { status = "Locked", reason = "Spam nhiều lần" });
            Qa.Is(HttpStatusCode.OK, locked);
            Assert.Equal("Locked", locked.Str("status"));
            Assert.Equal("Spam nhiều lần", locked.Str("statusReason"));

            Qa.Is(HttpStatusCode.Unauthorized, await _qa.CallAsync(HttpMethod.Get, "/users/me", token: token));
            Qa.Is(HttpStatusCode.Unauthorized, await _qa.PostAsync("/auth/refresh", null, new { refreshToken = login.Str("refreshToken") }));
            var refused = await _qa.PostAsync("/auth/login", null, new { email = victim.Email, password = Qa.Password });
            Assert.Equal((HttpStatusCode)423, refused.Status);
            Assert.Contains("Spam nhiều lần", refused.Message);

            var opened = await _qa.PatchAsync($"/users/{victim.Id}/status", admin, new { status = "Active" });
            Assert.Equal(JsonValueKind.Null, opened.Data.GetProperty("statusReason").ValueKind);
            Qa.IsOk(await _qa.PostAsync("/auth/login", null, new { email = victim.Email, password = Qa.Password }));
        }

        [MongoFact]
        public async Task Role_changes_are_for_admins_and_end_the_old_token()
        {
            var admin = await _qa.AdminAsync();
            var user = await _qa.UserAsync();
            var chef = await _qa.UserAsync("Chef");

            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/users/{user.Id}/role", admin, new { role = "Chef" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/users/{user.Id}/role", admin, new { role = "Root" }));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.PatchAsync($"/users/{user.Id}/role", admin, new { }));
            Qa.Is(HttpStatusCode.NotFound, await _qa.PatchAsync($"/users/{AnyId}/role", admin, new { role = "Admin" }));
            Qa.Is(HttpStatusCode.Conflict, await _qa.PatchAsync($"/users/{chef.Id}/role", admin, new { role = "User" }), "chef_role_locked");

            // Tự nâng quyền: không được, kể cả chính mình.
            Qa.Is(HttpStatusCode.Forbidden, await _qa.PatchAsync($"/users/{user.Id}/role", user, new { role = "Admin" }));

            var promoted = await _qa.PatchAsync($"/users/{user.Id}/role", admin, new { role = "Admin" });
            Qa.Is(HttpStatusCode.OK, promoted);
            Assert.Equal("Admin", promoted.Str("role"));
            Qa.Is(HttpStatusCode.Unauthorized, await _qa.GetAsync("/users/me", user));
            var asAdmin = new QaUser(user.Id, Qa.Jwt(user.Id, "Admin"), user.Name, user.Email);
            Qa.IsOk(await _qa.GetAsync("/users", asAdmin));

            var demoted = await _qa.PatchAsync($"/users/{user.Id}/role", admin, new { role = "User" });
            Assert.Equal("User", demoted.Str("role"));
            Qa.Is(HttpStatusCode.Unauthorized, await _qa.GetAsync("/users", asAdmin));
            var login = await _qa.PostAsync("/auth/login", null, new { email = user.Email, password = Qa.Password });
            Qa.Is(HttpStatusCode.Forbidden, await _qa.CallAsync(HttpMethod.Get, "/users", token: login.Str("accessToken")));
        }

        [MongoFact]
        public async Task User_list_filters_pages_and_has_the_admin_fields()
        {
            var admin = await _qa.AdminAsync();
            var tag = Guid.NewGuid().ToString("N");
            var author = await _qa.UserAsync(name: $"Tìm Thấy {tag}");
            var locked = await _qa.UserAsync(name: $"Bị Khoá {tag}");
            var chef = await _qa.UserAsync("Chef", $"Chuyên Gia {tag}");
            var post = await _qa.NewPostAsync(author);
            Qa.IsOk(await _qa.PostAsync($"/posts/{post}/reports", locked, new { reason = "spam" }));
            Qa.IsOk(await _qa.PatchAsync($"/users/{locked.Id}/status", admin, new { status = "Locked" }));
            Qa.IsOk(await _qa.PostAsync("/auth/login", null, new { email = author.Email, password = Qa.Password }));

            var searched = await _qa.GetAsync($"/users?search={tag.ToUpperInvariant()}", admin);
            Assert.Equal(3, searched.Data.GetArrayLength());
            Assert.Equal(JsonValueKind.True, searched.Root.GetProperty("success").ValueKind);

            var row = searched.Data.EnumerateArray().Single(u => u.GetProperty("id").GetString() == author.Id);
            Assert.Equal(1, row.GetProperty("postCount").GetInt32());
            Assert.Equal(1, row.GetProperty("reportCount").GetInt32());
            Assert.False(row.GetProperty("isVerifiedChef").GetBoolean());
            Assert.NotEqual(JsonValueKind.Null, row.GetProperty("lastActiveAt").ValueKind);
            Assert.Equal("Active", row.GetProperty("status").GetString());
            Assert.Equal("System", searched.Data.EnumerateArray().Single(u => u.GetProperty("id").GetString() == author.Id).GetProperty("authType").ValueKind == JsonValueKind.Null ? "System" : "System");
            Assert.DoesNotContain("passwordHash", searched.Text, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("refresh", searched.Text, StringComparison.OrdinalIgnoreCase);

            Assert.True(searched.Data.EnumerateArray().Single(u => u.GetProperty("id").GetString() == chef.Id).GetProperty("isVerifiedChef").GetBoolean());
            Assert.Equal(locked.Id, (await _qa.GetAsync($"/users?search={tag}&status=locked", admin)).Data.EnumerateArray().Single().GetProperty("id").GetString());
            Assert.Equal(chef.Id, (await _qa.GetAsync($"/users?search={tag}&role=chef", admin)).Data.EnumerateArray().Single().GetProperty("id").GetString());
            Assert.Equal(2, (await _qa.GetAsync($"/users?search={tag}&status=Active", admin)).Data.GetArrayLength());
            Assert.Equal(1, (await _qa.GetAsync($"/users?search={tag}&page=2&pageSize=2", admin)).Data.GetArrayLength());
            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/users?role=Root", admin));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/users?status=Nope", admin));
            Qa.Is(HttpStatusCode.BadRequest, await _qa.GetAsync("/users?status=9", admin));
        }
    }

    /// <summary>Quy tắc sản phẩm "bài mới và bài sửa chờ duyệt", bật bằng Posts:RequireApproval.</summary>
    public class Sprint10_RequireApprovalTests : IClassFixture<RequireApprovalFactory>
    {
        private readonly Qa _qa;

        public Sprint10_RequireApprovalTests(RequireApprovalFactory factory) => _qa = new Qa(factory);

        [MongoFact]
        public async Task New_and_edited_posts_wait_for_review_and_leave_the_feed()
        {
            var author = await _qa.UserAsync();
            var other = await _qa.UserAsync();
            var admin = await _qa.AdminAsync();

            var created = await _qa.PostAsync("/posts", author, Qa.PostBody("Bài chờ duyệt"));
            Qa.Is(HttpStatusCode.Created, created);
            Assert.Equal("Pending", created.Str("status"));
            var id = created.Str("id");

            Assert.DoesNotContain(id, (await _qa.GetAsync("/posts?limit=50")).Text);
            Qa.Is(HttpStatusCode.NotFound, await _qa.GetAsync($"/posts/{id}", other));
            Assert.Equal("Pending", (await _qa.GetAsync($"/posts/{id}", author)).Str("status"));
            Assert.Contains(id, (await _qa.GetAsync("/users/me/posts?status=Pending", author)).Text);

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Approve" }));
            Assert.Contains(id, (await _qa.GetAsync("/posts?limit=50")).Text);

            var edited = await _qa.PutAsync($"/posts/{id}", author, new { type = "discussion", title = "Đã sửa", body = "Nội dung", mediaType = "Text" });
            Assert.Equal("Pending", edited.Str("status"));
            Assert.DoesNotContain(id, (await _qa.GetAsync("/posts?limit=50")).Text);

            Qa.IsOk(await _qa.PostAsync($"/admin/posts/{id}/review", admin, new { decision = "Reject", reason = "Sai chủ đề" }));
            var resent = await _qa.PutAsync($"/posts/{id}", author, new { type = "discussion", title = "Sửa lại", body = "Nội dung", mediaType = "Text" });
            Assert.Equal("Pending", resent.Str("status"));
            Assert.Equal(JsonValueKind.Null, resent.Data.GetProperty("rejectionReason").ValueKind);
        }
    }
}
