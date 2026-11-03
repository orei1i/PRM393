using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.DTOs.Posts;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicationLayer.Services
{
    /// <summary>Proxy định vị. Chưa cấu hình thì trả 503: không gọi ra ngoài và không tự tạo kết quả.</summary>
    public class GeoService : IGeoService
    {
        private const string NotConfigured = "Dịch vụ định vị địa chỉ chưa được cấu hình trên máy chủ. Bạn có thể nhập địa chỉ thủ công.";
        private static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(30);

        private readonly IGeocodingClient _client;
        private readonly IMemoryCache _cache;

        public GeoService(IGeocodingClient client, IMemoryCache cache)
        {
            _client = client;
            _cache = cache;
        }

        private void RequireConfigured()
        {
            if (!_client.IsConfigured) throw new ServiceUnavailableException(NotConfigured, "geo_unavailable");
        }

        private static PlaceResponse Map(GeoPlaceResult p) => new()
        {
            Name = p.Name,
            Address = p.Address,
            City = p.City,
            Latitude = p.Latitude,
            Longitude = p.Longitude
        };

        public async Task<List<PlaceResponse>> SearchAsync(string? q, CancellationToken ct = default)
        {
            RequireConfigured();
            var query = q?.Trim() ?? string.Empty;
            if (query.Length == 0) return new List<PlaceResponse>();
            if (query.Length > 200) throw ContentText.Invalid("Từ khoá tối đa 200 ký tự.");

            var key = $"geo:search:{CommerceText.Fold(query)}";
            if (_cache.TryGetValue(key, out List<PlaceResponse>? cached) && cached != null) return cached;

            var places = (await _client.SearchAsync(query, ct)).Select(Map).ToList();
            _cache.Set(key, places, CacheFor);
            return places;
        }

        public async Task<PlaceResponse> ReverseAsync(double? lat, double? lng, CancellationToken ct = default)
        {
            RequireConfigured();
            if (lat == null || lng == null) throw ContentText.Invalid("Toạ độ cần đủ vĩ độ và kinh độ.");
            ContentText.RequireCoordinatePair(lat, lng);

            var place = await _client.ReverseAsync(lat.Value, lng.Value, ct);
            return place == null ? throw new NotFoundException("Không xác định được địa điểm này.") : Map(place);
        }
    }

    /// <summary>Tìm kiếm toàn app, đọc trong bộ nhớ vì cần bỏ dấu tiếng Việt: đủ cho quy mô đồ án.</summary>
    public class SearchService : ISearchService
    {
        private const int MaxRelatedPosts = 3;
        private static readonly string[] Types = { "all", "post", "video", "recipe", "restaurant" };

        private readonly IGenericRepository<Post> _posts;
        private readonly IGenericRepository<User> _users;
        private readonly IGenericRepository<Recipe> _recipes;
        private readonly IGenericRepository<Ingredient> _ingredients;
        private readonly IGenericRepository<MealPlan> _plans;
        private readonly IGenericRepository<CatalogItem> _catalog;
        private readonly IRestaurantService _restaurants;

        public SearchService(
            IGenericRepository<Post> posts,
            IGenericRepository<User> users,
            IGenericRepository<Recipe> recipes,
            IGenericRepository<Ingredient> ingredients,
            IGenericRepository<MealPlan> plans,
            IGenericRepository<CatalogItem> catalog,
            IRestaurantService restaurants)
        {
            _posts = posts;
            _users = users;
            _recipes = recipes;
            _ingredients = ingredients;
            _plans = plans;
            _catalog = catalog;
            _restaurants = restaurants;
        }

        private static RecipeSummaryResponse MapRecipe(Recipe r) => new()
        {
            Id = r.Id,
            Name = r.Name,
            CaloriesCache = r.Calories,
            IsVegan = r.IsVegan
        };

        private static IngredientResponse MapIngredient(Ingredient i) => new()
        {
            Id = i.Id,
            Name = i.Name,
            Category = i.Category,
            CaloriesPer100g = i.CaloriesPer100g,
            ProteinG = i.ProteinG,
            CarbsG = i.CarbsG,
            FatG = i.FatG,
            FiberG = i.FiberG,
            Allergens = i.Allergens,
            IsVegan = i.IsVegan,
            Aliases = i.Aliases,
            GoodFor = i.GoodFor,
            CautionFor = i.CautionFor
        };

        /// <summary>Công thức dùng chung, cộng công thức riêng của chính người tìm. Không lộ công thức riêng của người khác.</summary>
        private async Task<List<Recipe>> VisibleRecipesAsync(string? viewerId)
        {
            var rows = await _recipes.FindAsync(r => !r.IsDeleted && (r.CreatedBy == null || r.CreatedBy == viewerId));
            return rows.ToList();
        }

        private static int RecipeRank(Recipe r, string folded)
        {
            var name = CommerceText.Fold(r.Name);
            return name == folded ? 0 : name.StartsWith(folded, StringComparison.Ordinal) ? 1 : 2;
        }

        private async Task<Dictionary<string, User>> AuthorsOfAsync(IEnumerable<Post> posts)
        {
            var ids = posts.Select(p => p.UserId).Where(ContentText.IsId).Distinct().ToList();
            return ids.Count == 0 ? new Dictionary<string, User>() : (await _users.FindAsync(u => ids.Contains(u.Id))).ToDictionary(u => u.Id);
        }

        public async Task<SearchResponse> SearchAsync(string? q, string? type, double? lat, double? lng, int? limit, string? viewerId)
        {
            var wanted = string.IsNullOrWhiteSpace(type) ? "all" : type.Trim().ToLowerInvariant();
            if (!Types.Contains(wanted)) throw ContentText.Invalid("Loại tìm kiếm không hợp lệ.");
            ContentText.RequireCoordinatePair(lat, lng);
            var query = q?.Trim() ?? string.Empty;
            var result = new SearchResponse { Query = query };
            var tokens = ContentText.Tokens(query);
            if (tokens.Count == 0) return result;

            var take = Math.Clamp(limit ?? 10, 1, 50);
            bool Wants(string kind) => wanted == "all" || wanted == kind;

            List<Post> published = new();
            Dictionary<string, User> authors = new();
            if (Wants("post") || Wants("video") || wanted == "all")
            {
                published = (await _posts.FindAsync(p => !p.IsDeleted && p.Status == "Published")).OrderByDescending(p => p.CreatedAt).ToList();
                authors = await AuthorsOfAsync(published);
            }

            bool HasVideo(Post p) => p.MediaType == "Video";
            PostResponse MapPost(Post p) => ContentText.MapPost(p, authors.GetValueOrDefault(p.UserId));

            var matched = published
                .Where(p => ContentText.Matches(tokens, p.Title, p.Body, authors.GetValueOrDefault(p.UserId)?.FullName, string.Join(' ', p.Tags)))
                .OrderByDescending(p => ContentText.Matches(tokens, p.Title))
                .ThenByDescending(p => p.CreatedAt)
                .ToList();
            if (Wants("post")) result.Posts = matched.Where(p => !HasVideo(p)).Take(take).Select(MapPost).ToList();
            if (Wants("video")) result.Videos = matched.Where(HasVideo).Take(take).Select(MapPost).ToList();

            List<Recipe> recipes = new();
            if (Wants("recipe"))
            {
                var folded = string.Join(' ', tokens);
                recipes = (await VisibleRecipesAsync(viewerId))
                    .Where(r => ContentText.Matches(tokens, r.Name))
                    .OrderBy(r => RecipeRank(r, folded))
                    .ThenBy(r => r.Name.Length)
                    .ToList();
                result.Recipes = recipes.Take(take).Select(MapRecipe).ToList();
            }

            if (wanted == "all")
            {
                var ingredients = await _ingredients.FindAsync(i => !i.IsDeleted);
                result.Ingredients = ingredients
                    .Where(i => ContentText.Matches(tokens, i.Name, string.Join(' ', i.Aliases)))
                    .Take(take)
                    .Select(MapIngredient)
                    .ToList();
            }

            if (Wants("restaurant"))
                result.Restaurants = await _restaurants.ListPublicAsync(new RestaurantListQuery { Q = query, Lat = lat, Lng = lng, Limit = take });

            if (wanted == "all" && recipes.Count > 0)
            {
                var recipe = recipes[0];
                var nameTokens = ContentText.Tokens(recipe.Name);
                result.Suggestion = new SearchSuggestionBlock
                {
                    Recipe = MapRecipe(recipe),
                    RelatedPosts = published
                        .Where(p => ContentText.Matches(nameTokens, p.Title, p.Body))
                        .OrderByDescending(HasVideo)
                        .ThenByDescending(p => p.CreatedAt)
                        .Take(MaxRelatedPosts)
                        .Select(MapPost)
                        .ToList(),
                    Restaurants = await _restaurants.SuggestedAsync(recipe.Name, lat, lng, 3)
                };
            }
            return result;
        }

        public async Task<List<SearchSuggestItem>> SuggestAsync(string? q, int? limit, string? viewerId)
        {
            var tokens = ContentText.Tokens(q);
            var query = q?.Trim() ?? string.Empty;
            if (tokens.Count == 0 || query.Length < 2) return new List<SearchSuggestItem>();

            var take = Math.Clamp(limit ?? 8, 1, 20);
            var perGroup = Math.Max(2, take / 2);

            var recipes = (await VisibleRecipesAsync(viewerId))
                .Where(r => ContentText.Matches(tokens, r.Name))
                .OrderBy(r => r.Name.Length)
                .Take(perGroup)
                .Select(r => new SearchSuggestItem { Kind = "recipe", Text = r.Name, Id = r.Id, Subtitle = r.Calories > 0 ? $"{r.Calories} kcal" : null });

            var posts = (await _posts.FindAsync(p => !p.IsDeleted && p.Status == "Published"))
                .Where(p => ContentText.Matches(tokens, p.Title))
                .OrderByDescending(p => p.CreatedAt)
                .Take(perGroup)
                .Select(p => new SearchSuggestItem { Kind = "post", Text = p.Title, Id = p.Id });

            var ingredients = (await _ingredients.FindAsync(i => !i.IsDeleted))
                .Where(i => ContentText.Matches(tokens, i.Name, string.Join(' ', i.Aliases)))
                .Take(perGroup)
                .Select(i => new SearchSuggestItem { Kind = "ingredient", Text = i.Name, Id = i.Id });

            var restaurants = (await _restaurants.ListPublicAsync(new RestaurantListQuery { Q = query, Limit = perGroup }))
                .Select(r => new SearchSuggestItem { Kind = "restaurant", Text = r.Name, Id = r.Id, Subtitle = r.Address });

            return recipes.Concat(restaurants).Concat(ingredients).Concat(posts).Take(take).ToList();
        }

        public async Task<SearchDiscoverResponse> DiscoverAsync(double? lat, double? lng)
        {
            ContentText.RequireCoordinatePair(lat, lng);
            var categories = await _catalog.FindAsync(c => c.Kind == "category" && c.Active && !c.IsDeleted);

            return new SearchDiscoverResponse
            {
                Categories = categories
                    .OrderBy(c => c.Label, StringComparer.Ordinal)
                    .Select(c => new SearchCategoryResponse { Id = c.Id, Label = c.Label, Query = c.Label })
                    .ToList(),
                PopularRecipes = await PopularRecipesAsync(),
                NearbyRestaurants = await _restaurants.ListPublicAsync(new RestaurantListQuery { Lat = lat, Lng = lng, Limit = 3 })
            };
        }

        /// <summary>"Yêu thích" đo bằng số lần món xuất hiện trong thực đơn gần đây. Chưa có dữ liệu thì rỗng, không tự xếp hạng.</summary>
        private async Task<List<RecipeSummaryResponse>> PopularRecipesAsync()
        {
            var plans = await _plans.FindPagedAsync(p => !p.IsDeleted, 1, 200, sortDesc: p => p.CreatedAt);
            var counts = plans
                .SelectMany(p => p.Days)
                .SelectMany(d => d.Meals.Values)
                .Where(m => ContentText.IsId(m.RecipeId))
                .GroupBy(m => m.RecipeId!)
                .OrderByDescending(g => g.Count())
                .Take(12)
                .Select(g => g.Key)
                .ToList();
            if (counts.Count == 0) return new List<RecipeSummaryResponse>();

            var recipes = (await _recipes.FindAsync(r => counts.Contains(r.Id) && !r.IsDeleted && r.CreatedBy == null)).ToDictionary(r => r.Id);
            return counts.Where(recipes.ContainsKey).Take(6).Select(id => MapRecipe(recipes[id])).ToList();
        }
    }
}
