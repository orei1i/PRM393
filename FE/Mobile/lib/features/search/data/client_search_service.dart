// lib/features/search/data/client_search_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/text_search.dart';
import '../../community/data/backend_posts.dart';
import '../../community/data/community_api_service.dart';
import '../../community/data/models/post_model.dart';
import '../../community/domain/entities/post.dart';
import '../../ingredient/data/ingredient_api_service.dart';
import '../../ingredient/data/models/ingredient_model.dart';
import '../../recipe/data/recipe_catalog.dart';
import '../../restaurant/data/models/restaurant_model.dart';
import '../../restaurant/data/restaurant_api_service.dart';
import '../../restaurant/domain/geo.dart';
import '../domain/entities/search_result.dart';
import 'mock_search_repository.dart';
import 'models/search_models.dart';
import 'search_api_service.dart';

/// What the recipes of a search come from, and how much of them that is.
typedef RecipeSource = Future<(List<RecipeSummaryDto>, RecipeSearchScope)>
    Function();

/// Global search with module `search` forced to mock: the client looks through
/// what each module's API gives, so the results open real pages.
/// - Posts: the newest [maxFeedPages] pages of `GET /posts` (Published only),
///   kept for [postCacheFor] so that typing doesn't walk the feed every time.
/// - Recipes: [RecipeCatalog] for a member. A guest can't read it, and a member
///   with no plan this week gets at most 10 dishes; [RecipeSearchScope] says so.
/// - Ingredients: `GET /ingredients?q=`, which ignores accents on the BE.
/// - Restaurants: [RestaurantApiService], sample data until the BE has them.
///
/// There is no search log, so no "Xu hướng"; [discover] only keeps the
/// categories that lead to a real result.
class ClientSearchService implements SearchApiService {
  ClientSearchService({
    required this.community,
    required this.restaurants,
    required this.ingredients,
    required this.recipes,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Each module on whatever the build's switch says: a mock recipes module
  /// searches the sample catalogue, the real one the member's.
  factory ClientSearchService.fromRef(Ref<Object?> ref) => ClientSearchService(
        community: ref.watch(communityApiProvider),
        restaurants: ref.watch(restaurantApiProvider),
        ingredients: ref.watch(ingredientApiProvider),
        recipes: BackendModules.isMock(BackendModule.recipes)
            ? () async =>
                (MockSearchRepository.recipeCatalogue(), RecipeSearchScope.full)
            : () => backendRecipes(
                  isGuest: () => ref.read(sessionControllerProvider).isGuest,
                  catalog: () => ref.read(recipeCatalogProvider),
                  dio: ref.read(dioProvider),
                  planId: () => ref.read(planItemSnapshotsProvider).planId,
                ),
      );

  /// 5 × 50 = the 250 newest posts, like "Bài của tôi".
  static const maxFeedPages = 5;
  static const postCacheFor = Duration(seconds: 20);

  final CommunityApiService community;
  final RestaurantApiService restaurants;
  final IngredientApiService ingredients;
  final RecipeSource recipes;
  final DateTime Function() _now;

  List<PostDto>? _posts;
  bool _postsTruncated = false;
  DateTime? _postsAt;

  (List<RecipeSummaryDto>, RecipeSearchScope)? _recipes;
  DateTime? _recipesAt;

  /// Like [_publishedPosts]. A search asks again: it may follow a sign-in.
  Future<(List<RecipeSummaryDto>, RecipeSearchScope)> _loadRecipes(
      {bool fresh = false}) async {
    final at = _recipesAt;
    final cached = _recipes;
    if (!fresh &&
        cached != null &&
        at != null &&
        _now().difference(at) < postCacheFor) {
      return cached;
    }
    final loaded = await recipes();
    _recipesAt = _now();
    return _recipes = loaded;
  }

  /// The recipes the real BE lets this caller read.
  static Future<(List<RecipeSummaryDto>, RecipeSearchScope)> backendRecipes({
    required bool Function() isGuest,
    required RecipeCatalog Function() catalog,
    required Dio dio,
    required String? Function() planId,
  }) async {
    if (isGuest()) {
      return (const <RecipeSummaryDto>[], RecipeSearchScope.signedOut);
    }
    try {
      final rows = await catalog().load();
      final hasPlan = planId() != null || await _hasCurrentPlan(dio);
      return (
        [
          for (final r in rows)
            RecipeSummaryDto(
                id: r.id,
                name: r.name,
                caloriesCache: r.caloriesCache,
                isVegan: r.isVegan),
        ],
        hasPlan ? RecipeSearchScope.full : RecipeSearchScope.fridgeOnly,
      );
    } on ApiException {
      return (const <RecipeSummaryDto>[], RecipeSearchScope.unavailable);
    }
  }

  /// The catalogue has no way to say where its rows came from; the rule it
  /// follows is this one (see [RecipeCatalog]).
  static Future<bool> _hasCurrentPlan(Dio dio) => guardApi(() async {
        try {
          await dio.get<Map<String, dynamic>>(ApiEndpoints.currentMealPlan);
          return true;
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return false;
          rethrow;
        }
      });

  /// [fresh] for a search; typing and the idle page can use the last walk.
  Future<List<PostDto>> _publishedPosts({bool fresh = false}) async {
    final at = _postsAt;
    final cached = _posts;
    if (!fresh &&
        cached != null &&
        at != null &&
        _now().difference(at) < postCacheFor) {
      return cached;
    }
    final all = <PostDto>[];
    String? cursor;
    for (var page = 1; page <= maxFeedPages; page++) {
      final feed =
          await community.getFeed(cursor: cursor, limit: backendMaxPageSize);
      all.addAll(feed.items);
      cursor = feed.nextCursor;
      if (cursor == null) break;
    }
    _postsTruncated = cursor != null;
    _postsAt = _now();
    return _posts = [
      for (final p in all)
        if (PostStatus.fromApi(p.status) == PostStatus.published) p,
    ];
  }

  /// Exact name first, then names starting with the query; shorter first.
  static int _rank(String name, String folded) {
    final n = foldVietnamese(name);
    return n == folded ? 0 : (n.startsWith(folded) ? 1 : 2);
  }

  static List<RecipeSummaryDto> _sortedHits(
          Iterable<RecipeSummaryDto> hits, String folded) =>
      hits.toList()
        ..sort((a, b) {
          final rank = _rank(a.name, folded) - _rank(b.name, folded);
          return rank != 0 ? rank : a.name.length - b.name.length;
        });

  @override
  Future<SearchResultDto> search(
    String query, {
    SearchType type = SearchType.all,
    GeoPoint? near,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.length < 2) return SearchResultDto(query: q);
    bool wants(SearchType t) => type == SearchType.all || type == t;

    final loaded = await Future.wait<Object>([
      if (wants(SearchType.post) || wants(SearchType.video))
        _publishedPosts(fresh: true)
      else
        Future.value(const <PostDto>[]),
      _loadRecipes(fresh: true),
      if (type == SearchType.all)
        _quiet(ingredients.search(q), const <IngredientSummaryDto>[])
      else
        Future.value(const <IngredientSummaryDto>[]),
      if (wants(SearchType.restaurant))
        _quiet(restaurants.listRestaurants(near: near, query: q),
            const <RestaurantDto>[])
      else
        Future.value(const <RestaurantDto>[]),
    ]);
    final posts = loaded[0] as List<PostDto>;
    final (catalogue, scope) =
        loaded[1] as (List<RecipeSummaryDto>, RecipeSearchScope);
    final foundIngredients = loaded[2] as List<IngredientSummaryDto>;
    final places = loaded[3] as List<RestaurantDto>;

    final folded = foldVietnamese(q);
    final hits = wants(SearchType.recipe)
        ? _sortedHits(catalogue.where((r) => matchesQuery(r.name, q)), folded)
        : const <RecipeSummaryDto>[];
    final matched = posts
        .where((p) => matchesQuery(MockSearchRepository.postText(p), q))
        .toList()
      // Title hits before body-only hits; feed order (newest) otherwise.
      ..sort((a, b) {
        final ta = matchesQuery(a.title, q), tb = matchesQuery(b.title, q);
        return ta == tb ? 0 : (ta ? -1 : 1);
      });

    SearchSuggestionDto? suggestion;
    if (type == SearchType.all && hits.isNotEmpty) {
      final recipe = hits.first;
      suggestion = SearchSuggestionDto(
        recipe: recipe,
        relatedPosts: MockSearchRepository.relatedPosts(posts, recipe.name),
        restaurants: await _quiet(
            restaurants.suggestedForFood(recipe.name, near: near, limit: 3),
            const <RestaurantDto>[]),
      );
    }

    return SearchResultDto(
      query: q,
      posts: wants(SearchType.post)
          ? matched.where((p) => !p.hasVideo).take(limit).toList()
          : const [],
      videos: wants(SearchType.video)
          ? matched.where((p) => p.hasVideo).take(limit).toList()
          : const [],
      recipes: hits.take(limit).toList(),
      ingredients: foundIngredients.take(limit).toList(),
      restaurants: places.take(limit).toList(),
      suggestion: suggestion,
      recipeScope: scope,
      postsTruncated: _postsTruncated,
    );
  }

  /// Autocomplete is optional, so a source that fails just gives no rows.
  @override
  Future<List<SearchSuggestItemDto>> suggest(String query,
      {int limit = 8}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final folded = foldVietnamese(q);
    final loaded = await Future.wait<Object>([
      _quiet(_publishedPosts(), const <PostDto>[]),
      _loadRecipes(),
      _quiet(ingredients.search(q), const <IngredientSummaryDto>[]),
      _quiet(restaurants.listRestaurants(query: q), const <RestaurantDto>[]),
    ]);
    final (catalogue, _) =
        loaded[1] as (List<RecipeSummaryDto>, RecipeSearchScope);
    final hits = _sortedHits(
        catalogue.where((r) => MockSearchRepository.prefixMatch(r.name, q)),
        folded);
    final titles = (loaded[0] as List<PostDto>)
        .where((p) => MockSearchRepository.prefixMatch(p.title, q))
        .take(2);
    final places = (loaded[3] as List<RestaurantDto>)
        .where((r) => MockSearchRepository.prefixMatch(r.name, q))
        .take(2);

    return [
      for (final r in hits.take(3))
        SearchSuggestItemDto(
          kind: SuggestKind.recipe.apiValue,
          text: r.name,
          id: r.id,
          subtitle: r.caloriesCache == null
              ? 'Công thức'
              : 'Công thức · ${r.caloriesCache} kcal',
        ),
      for (final p in titles)
        SearchSuggestItemDto(
          kind: SuggestKind.post.apiValue,
          text: p.title,
          id: p.id,
          subtitle: '${p.hasVideo ? 'Video' : 'Bài viết'} · ${p.author.name}',
        ),
      for (final i in (loaded[2] as List<IngredientSummaryDto>).take(2))
        SearchSuggestItemDto(
          kind: SuggestKind.ingredient.apiValue,
          text: i.name,
          id: i.id,
          subtitle: 'Nguyên liệu',
        ),
      for (final r in places)
        SearchSuggestItemDto(
          kind: SuggestKind.restaurant.apiValue,
          text: r.name,
          id: r.id,
          subtitle: [
            if (BackendModules.isMock(BackendModule.restaurants))
              'Quán (dữ liệu mẫu)'
            else
              'Quán',
            MockSearchRepository.district(r.address),
          ].whereType<String>().join(' · '),
        ),
    ].take(limit).toList();
  }

  static Future<T> _quiet<T>(Future<T> loading, T fallback) async {
    try {
      return await loading;
    } on ApiException {
      return fallback;
    }
  }

  /// The idle page has no trending, seasonal or popular list: nothing on the BE
  /// computes them. A category only stays if searching it finds something.
  @override
  Future<SearchDiscoverDto> discover({GeoPoint? near}) async {
    final loaded = await Future.wait<Object>([
      _quiet(_publishedPosts(), const <PostDto>[]),
      _loadRecipes(),
      _quiet(restaurants.listRestaurants(near: near, limit: 3),
          const <RestaurantDto>[]),
    ]);
    final posts = loaded[0] as List<PostDto>;
    final (catalogue, _) =
        loaded[1] as (List<RecipeSummaryDto>, RecipeSearchScope);
    bool findsSomething(String query) =>
        catalogue.any((r) => matchesQuery(r.name, query)) ||
        posts.any((p) => matchesQuery(MockSearchRepository.postText(p), query));
    return SearchDiscoverDto(
      categories: [
        for (final c in MockSearchRepository.categories)
          if (findsSomething(c['query']!)) Map<String, dynamic>.from(c),
      ],
      nearbyRestaurants: (loaded[2] as List<RestaurantDto>).take(3).toList(),
    );
  }
}
