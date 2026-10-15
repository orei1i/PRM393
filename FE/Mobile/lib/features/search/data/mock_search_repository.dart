// lib/features/search/data/mock_search_repository.dart
import '../../../core/network/api_exception.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../community/data/community_api_service.dart';
import '../../community/data/models/post_model.dart';
import '../../community/domain/entities/post.dart';
import '../../meal_planner/data/mock/meal_planner_mock_data.dart';
import '../../recipe/data/mock/recipe_mock_data.dart';
import '../../restaurant/data/models/restaurant_model.dart';
import '../../restaurant/data/restaurant_api_service.dart';
import '../../restaurant/domain/food_match.dart';
import '../../restaurant/domain/geo.dart';
import '../domain/entities/search_result.dart';
import 'models/search_models.dart';
import 'search_api_service.dart';

/// Search over the other features' APIs, the way the server would join
/// them: posts come from paging [CommunityApiService.getFeed] (so new posts
/// and the Published-only rule apply automatically), restaurants from
/// [RestaurantApiService], recipes from the meal-planner / recipe catalogue.
/// Matching ignores case and accents. `#fail` in the query → 503.
class MockSearchRepository implements SearchApiService {
  MockSearchRepository({required this.community, required this.restaurants});

  final CommunityApiService community;
  final RestaurantApiService restaurants;

  /// Related videos/posts shown in the suggestion block.
  static const maxRelatedPosts = 6;

  /// Every dish the app can open in the recipe screen, once.
  static List<RecipeSummaryDto> recipeCatalogue() {
    final byId = <String, RecipeSummaryDto>{};
    for (final json in [
      ...handWrittenRecipes.values,
      ...mockBreakfasts,
      ...mockLunches,
      ...mockDinners,
      for (final list in mockSwapPool.values) ...list,
      ...mockPantryDishes,
    ]) {
      final dto = RecipeSummaryDto.fromJson(Map<String, dynamic>.from(json));
      if (dto.id.isNotEmpty) byId.putIfAbsent(dto.id, () => dto);
    }
    return byId.values.toList();
  }

  /// Exact name first, then names starting with the query, then the rest;
  /// shorter names first within a rank.
  static int _recipeRank(RecipeSummaryDto r, String folded) {
    final name = foldVietnamese(r.name);
    if (name == folded) return 0;
    if (name.startsWith(folded)) return 1;
    return 2;
  }

  Future<List<PostDto>> _publishedPosts() async {
    final all = <PostDto>[];
    String? cursor;
    do {
      final page = await community.getFeed(cursor: cursor, limit: 50);
      all.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return all
        .where((p) => PostStatus.fromApi(p.status) == PostStatus.published)
        .toList();
  }

  static bool _isVideo(PostDto p) =>
      p.type == PostType.video.apiValue ||
      PostMediaType.tryParse(p.mediaType) == PostMediaType.video;

  static String _postText(PostDto p) => [
        p.title,
        p.body,
        p.author.name,
        for (final t in p.tags) dietTagLabel(t),
      ].join(' ');

  /// Posts mentioning the dish: videos first, then the ones naming more of
  /// it, then newest; at most [maxRelatedPosts].
  static List<PostDto> relatedPosts(List<PostDto> posts, String recipeName) {
    final texts = {
      for (final p in posts) p.id: [p.title, p.body],
    };
    final hits = matchFood(texts, recipeName);
    final scores = foodMatchScores(texts, recipeName);
    final related = posts.where((p) => hits.contains(p.id)).toList()
      ..sort((a, b) {
        if (_isVideo(a) != _isVideo(b)) return _isVideo(a) ? -1 : 1;
        final sa = scores[a.id] ?? 0, sb = scores[b.id] ?? 0;
        if (sa != sb) return sb.compareTo(sa);
        return b.createdAt.compareTo(a.createdAt);
      });
    return related.take(maxRelatedPosts).toList();
  }

  @override
  Future<SearchResultDto> search(
    String query, {
    SearchType type = SearchType.all,
    GeoPoint? near,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.length < 2) return SearchResultDto(query: q);
    if (q.toLowerCase().contains('#fail')) {
      await mockDelay(400);
      throw const ApiException(
          message: 'Máy chủ tìm kiếm đang bận. Thử lại sau ít phút.',
          statusCode: 503,
          code: 'unavailable');
    }
    bool wants(SearchType t) => type == SearchType.all || type == t;

    // Independent sources load side by side, like the server's joins.
    final postsFuture = wants(SearchType.post) || wants(SearchType.video)
        ? _publishedPosts()
        : Future.value(const <PostDto>[]);
    final restaurantsFuture = wants(SearchType.restaurant)
        ? restaurants.listRestaurants(near: near, query: q)
        : Future.value(const <RestaurantDto>[]);

    final folded = foldVietnamese(q);
    final recipes = !wants(SearchType.recipe)
        ? const <RecipeSummaryDto>[]
        : (recipeCatalogue().where((r) => matchesQuery(r.name, q)).toList()
          ..sort((a, b) {
            final rank = _recipeRank(a, folded) - _recipeRank(b, folded);
            return rank != 0 ? rank : a.name.length - b.name.length;
          }));

    final loaded = await Future.wait<Object>([postsFuture, restaurantsFuture]);
    final posts = loaded[0] as List<PostDto>;
    final nearby = loaded[1] as List<RestaurantDto>;
    final matched = posts.where((p) => matchesQuery(_postText(p), q)).toList()
      // Title hits before body-only hits; feed order (newest) otherwise.
      ..sort((a, b) {
        final ta = matchesQuery(a.title, q), tb = matchesQuery(b.title, q);
        return ta == tb ? 0 : (ta ? -1 : 1);
      });

    SearchSuggestionDto? suggestion;
    if (type == SearchType.all && recipes.isNotEmpty) {
      final recipe = recipes.first;
      suggestion = SearchSuggestionDto(
        recipe: recipe,
        relatedPosts: relatedPosts(posts, recipe.name),
        restaurants: await restaurants.suggestedForFood(recipe.name,
            near: near, limit: 3),
      );
    }

    return SearchResultDto(
      query: q,
      posts: wants(SearchType.post)
          ? matched.where((p) => !_isVideo(p)).take(limit).toList()
          : const [],
      videos: wants(SearchType.video)
          ? matched.where(_isVideo).take(limit).toList()
          : const [],
      recipes: recipes.take(limit).toList(),
      restaurants: nearby.take(limit).toList(),
      suggestion: suggestion,
    );
  }
}
