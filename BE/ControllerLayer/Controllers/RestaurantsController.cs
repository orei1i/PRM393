using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Content;
using ApplicationLayer.Interfaces;
using ControllerLayer.Authorization;
using ControllerLayer.Extensions;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/restaurants")]
    [ApiController]
    public class RestaurantsController : ControllerBase
    {
        private readonly IRestaurantService _restaurants;

        public RestaurantsController(IRestaurantService restaurants)
        {
            _restaurants = restaurants;
        }

        private bool IsAdmin => User.IsInRole(AppRoles.Admin);

        [HttpGet]
        [AllowAnonymous]
        public async Task<ActionResult<ApiResponse<List<RestaurantResponse>>>> List(
            [FromQuery] double? lat, [FromQuery] double? lng, [FromQuery] string? q, [FromQuery] bool certifiedOnly = false,
            [FromQuery] string? sort = null, [FromQuery] double? radiusKm = null, [FromQuery] int? limit = null) =>
            Ok(ApiResponse<List<RestaurantResponse>>.Ok(await _restaurants.ListPublicAsync(new RestaurantListQuery
            {
                Lat = lat,
                Lng = lng,
                Q = q,
                CertifiedOnly = certifiedOnly,
                Sort = sort,
                RadiusKm = radiusKm,
                Limit = limit
            })));

        [HttpGet("suggested")]
        [AllowAnonymous]
        public async Task<ActionResult<ApiResponse<List<RestaurantResponse>>>> Suggested(
            [FromQuery] string? food, [FromQuery] double? lat, [FromQuery] double? lng, [FromQuery] int? limit) =>
            Ok(ApiResponse<List<RestaurantResponse>>.Ok(await _restaurants.SuggestedAsync(food, lat, lng, limit)));

        [HttpGet("{id}")]
        [AllowAnonymous]
        public async Task<ActionResult<ApiResponse<RestaurantResponse>>> Get(string id, [FromQuery] double? lat, [FromQuery] double? lng) =>
            Ok(ApiResponse<RestaurantResponse>.Ok(await _restaurants.GetAsync(id, lat, lng, User.GetUserIdOrDefault(), IsAdmin)));

        [HttpGet("{id}/media")]
        [AllowAnonymous]
        public async Task<ActionResult<ApiResponse<List<RestaurantMediaResponse>>>> Media(string id) =>
            Ok(ApiResponse<List<RestaurantMediaResponse>>.Ok(await _restaurants.ListMediaAsync(id, User.GetUserIdOrDefault(), IsAdmin)));

        [HttpGet("{id}/reviews")]
        [AllowAnonymous]
        public async Task<ActionResult<ApiResponse<List<RestaurantReviewResponse>>>> Reviews(string id) =>
            Ok(ApiResponse<List<RestaurantReviewResponse>>.Ok(await _restaurants.ListReviewsAsync(id, User.GetUserIdOrDefault(), IsAdmin)));

        [HttpPost("{id}/reviews")]
        [Authorize]
        public async Task<ActionResult<ApiResponse<RestaurantReviewResponse>>> UpsertReview(string id, [FromBody] UpsertRestaurantReviewRequest request) =>
            Ok(ApiResponse<RestaurantReviewResponse>.Ok(await _restaurants.UpsertReviewAsync(User.GetUserId(), id, request)));

        [HttpPost]
        [Authorize]
        public async Task<ActionResult<ApiResponse<RestaurantSuggestionResponse>>> Suggest([FromBody] CreateRestaurantRequest request)
        {
            var created = await _restaurants.SuggestAsync(User.GetUserId(), request);
            return StatusCode(StatusCodes.Status201Created, ApiResponse<RestaurantSuggestionResponse>.Created(created));
        }
    }

    [Route("api/v1/users/me/restaurant-suggestions")]
    [ApiController]
    [Authorize]
    public class MyRestaurantSuggestionsController : ControllerBase
    {
        private readonly IRestaurantService _restaurants;

        public MyRestaurantSuggestionsController(IRestaurantService restaurants)
        {
            _restaurants = restaurants;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<RestaurantSuggestionResponse>>>> List() =>
            Ok(ApiResponse<List<RestaurantSuggestionResponse>>.Ok(await _restaurants.ListMySuggestionsAsync(User.GetUserId())));
    }

    [Route("api/v1/admin/restaurants")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminRestaurantsController : ControllerBase
    {
        private readonly IRestaurantService _restaurants;

        public AdminRestaurantsController(IRestaurantService restaurants)
        {
            _restaurants = restaurants;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<List<AdminRestaurantResponse>>>> List(
            [FromQuery] string? status, [FromQuery] string? certified, [FromQuery] string? source, [FromQuery] string? search) =>
            Ok(ApiResponse<List<AdminRestaurantResponse>>.Ok(await _restaurants.AdminListAsync(status, certified, source, search)));

        [HttpPost("{id}/review")]
        public async Task<ActionResult<ApiResponse<AdminRestaurantResponse>>> Review(string id, [FromBody] ReviewRestaurantRequest request) =>
            Ok(ApiResponse<AdminRestaurantResponse>.Ok(await _restaurants.AdminReviewAsync(User.GetUserId(), id, request)));

        [HttpPatch("{id}")]
        public async Task<ActionResult<ApiResponse<AdminRestaurantResponse>>> Patch(string id, [FromBody] SetRestaurantCertifiedRequest request) =>
            Ok(ApiResponse<AdminRestaurantResponse>.Ok(await _restaurants.AdminSetCertifiedAsync(User.GetUserId(), id, request)));

        [HttpDelete("{id}")]
        public async Task<ActionResult<ApiResponse<object>>> Delete(string id)
        {
            await _restaurants.AdminDeleteAsync(User.GetUserId(), id);
            return Ok(ApiResponse<object>.Ok(new { }, "Đã xoá quán."));
        }

        [HttpGet("{id}/reviews")]
        public async Task<ActionResult<ApiResponse<List<RestaurantReviewResponse>>>> Reviews(string id) =>
            Ok(ApiResponse<List<RestaurantReviewResponse>>.Ok(await _restaurants.AdminListReviewsAsync(id)));
    }

    [Route("api/v1/admin/reviews")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminRestaurantReviewsController : ControllerBase
    {
        private readonly IRestaurantService _restaurants;

        public AdminRestaurantReviewsController(IRestaurantService restaurants)
        {
            _restaurants = restaurants;
        }

        [HttpDelete("{id}")]
        public async Task<ActionResult<ApiResponse<object>>> Delete(string id)
        {
            await _restaurants.AdminDeleteReviewAsync(User.GetUserId(), id);
            return Ok(ApiResponse<object>.Ok(new { }, "Đã xoá đánh giá."));
        }
    }

    /// <summary>Công khai nên có giới hạn theo IP: Nominatim chỉ cho khoảng 1 yêu cầu mỗi giây.</summary>
    [Route("api/v1/geo")]
    [ApiController]
    [AllowAnonymous]
    [EnableRateLimiting("geo")]
    public class GeoController : ControllerBase
    {
        private readonly IGeoService _geo;

        public GeoController(IGeoService geo)
        {
            _geo = geo;
        }

        [HttpGet("search")]
        public async Task<ActionResult<ApiResponse<List<PlaceResponse>>>> Search([FromQuery] string? q) =>
            Ok(ApiResponse<List<PlaceResponse>>.Ok(await _geo.SearchAsync(q, HttpContext.RequestAborted)));

        [HttpGet("reverse")]
        public async Task<ActionResult<ApiResponse<PlaceResponse>>> Reverse([FromQuery] double? lat, [FromQuery] double? lng) =>
            Ok(ApiResponse<PlaceResponse>.Ok(await _geo.ReverseAsync(lat, lng, HttpContext.RequestAborted)));
    }

    [Route("api/v1/search")]
    [ApiController]
    [AllowAnonymous]
    public class SearchController : ControllerBase
    {
        private readonly ISearchService _search;

        public SearchController(ISearchService search)
        {
            _search = search;
        }

        [HttpGet]
        public async Task<ActionResult<ApiResponse<SearchResponse>>> Search(
            [FromQuery] string? q, [FromQuery] string? type, [FromQuery] double? lat, [FromQuery] double? lng, [FromQuery] int? limit) =>
            Ok(ApiResponse<SearchResponse>.Ok(await _search.SearchAsync(q, type, lat, lng, limit, User.GetUserIdOrDefault())));

        [HttpGet("suggest")]
        public async Task<ActionResult<ApiResponse<List<SearchSuggestItem>>>> Suggest([FromQuery] string? q, [FromQuery] int? limit) =>
            Ok(ApiResponse<List<SearchSuggestItem>>.Ok(await _search.SuggestAsync(q, limit, User.GetUserIdOrDefault())));

        [HttpGet("discover")]
        public async Task<ActionResult<ApiResponse<SearchDiscoverResponse>>> Discover([FromQuery] double? lat, [FromQuery] double? lng) =>
            Ok(ApiResponse<SearchDiscoverResponse>.Ok(await _search.DiscoverAsync(lat, lng)));
    }
}
