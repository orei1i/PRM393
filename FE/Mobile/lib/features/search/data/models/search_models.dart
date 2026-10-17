// lib/features/search/data/models/search_models.dart
//
// GET /search?q=bún%20riêu&type=all|post|video|recipe|restaurant&lat=&lng=&limit=10
// { "query": "bún riêu",
//   "posts":  [PostDto…],          // mediaType Text/Image, status Published only
//   "videos": [PostDto…],          // posts with a video (mediaType Video), Published only
//   "recipes": [ { "id": "l5", "name": "Bún riêu chay", "caloriesCache": 520, "isVegan": true } ],
//   "restaurants": [RestaurantDto…],
//   "suggestion": { "recipe": RecipeSummaryDto, "relatedPosts": [PostDto…],
//                   "restaurants": [RestaurantDto…] } | null }
//
// Guests allowed. The client drops any non-Published post it receives anyway.
import '../../../../core/utils/json_helpers.dart';
import '../../../community/data/models/post_model.dart';
import '../../../community/domain/entities/post.dart';
import '../../../restaurant/data/models/restaurant_model.dart';
import '../../domain/entities/search_result.dart';

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List<Object?>
        ? value.whereType<Map<String, dynamic>>().map(parse).toList()
        : <T>[];

List<Post> _publishedPosts(List<PostDto> posts) => [
      for (final p in posts)
        if (PostStatus.fromApi(p.status) == PostStatus.published) p.toEntity(),
    ];

class RecipeSummaryDto {
  const RecipeSummaryDto({
    required this.id,
    required this.name,
    this.caloriesCache,
    this.isVegan = true,
  });

  /// Also reads the meal-planner summary shape (`calories`).
  factory RecipeSummaryDto.fromJson(Map<String, dynamic> json) {
    final calories = json['caloriesCache'] ?? json['calories'];
    return RecipeSummaryDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      caloriesCache: calories == null ? null : readInt(calories),
      isVegan: json['isVegan'] != false,
    );
  }

  final String id;
  final String name;
  final int? caloriesCache;
  final bool isVegan;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'caloriesCache': caloriesCache,
        'isVegan': isVegan,
      };

  RecipeSummary toEntity() => RecipeSummary(
      id: id, name: name, calories: caloriesCache, isVegan: isVegan);
}

class SearchSuggestionDto {
  const SearchSuggestionDto({
    required this.recipe,
    this.relatedPosts = const [],
    this.restaurants = const [],
  });

  factory SearchSuggestionDto.fromJson(Map<String, dynamic> json) =>
      SearchSuggestionDto(
        recipe: RecipeSummaryDto.fromJson(readMap(json['recipe'])),
        relatedPosts: _list(json['relatedPosts'], PostDto.fromJson),
        restaurants: _list(json['restaurants'], RestaurantDto.fromJson),
      );

  final RecipeSummaryDto recipe;
  final List<PostDto> relatedPosts;
  final List<RestaurantDto> restaurants;

  SearchSuggestion toEntity() => SearchSuggestion(
        recipe: recipe.toEntity(),
        relatedPosts: _publishedPosts(relatedPosts),
        restaurants: [for (final r in restaurants) r.toEntity()],
      );
}

class SearchResultDto {
  const SearchResultDto({
    required this.query,
    this.posts = const [],
    this.videos = const [],
    this.recipes = const [],
    this.restaurants = const [],
    this.suggestion,
  });

  factory SearchResultDto.fromJson(Map<String, dynamic> json) {
    final suggestion = json['suggestion'];
    return SearchResultDto(
      query: json['query'] as String? ?? '',
      posts: _list(json['posts'], PostDto.fromJson),
      videos: _list(json['videos'], PostDto.fromJson),
      recipes: _list(json['recipes'], RecipeSummaryDto.fromJson),
      restaurants: _list(json['restaurants'], RestaurantDto.fromJson),
      suggestion: suggestion is Map<String, dynamic> &&
              suggestion['recipe'] is Map<String, dynamic>
          ? SearchSuggestionDto.fromJson(suggestion)
          : null,
    );
  }

  final String query;
  final List<PostDto> posts;
  final List<PostDto> videos;
  final List<RecipeSummaryDto> recipes;
  final List<RestaurantDto> restaurants;
  final SearchSuggestionDto? suggestion;

  SearchResult toEntity() => SearchResult(
        query: query,
        posts: _publishedPosts(posts),
        videos: _publishedPosts(videos),
        recipes: [for (final r in recipes) r.toEntity()],
        restaurants: [for (final r in restaurants) r.toEntity()],
        suggestion: suggestion?.toEntity(),
      );
}

/// GET /search/suggest?q=bu&limit=8 (guests allowed)
/// `[{ "kind": "query|recipe|post|restaurant", "text": "bún riêu chay",
///     "id": null, "subtitle": "Công thức" }]`
class SearchSuggestItemDto {
  const SearchSuggestItemDto({
    required this.kind,
    required this.text,
    this.id,
    this.subtitle,
  });

  factory SearchSuggestItemDto.fromJson(Map<String, dynamic> json) =>
      SearchSuggestItemDto(
        kind: SuggestKind.fromApi(json['kind']).apiValue,
        text: json['text'] as String? ?? '',
        id: json['id']?.toString(),
        subtitle: json['subtitle'] as String?,
      );

  static List<SearchSuggestItemDto> listFromJson(Object? json) =>
      _list(json, SearchSuggestItemDto.fromJson);

  final String kind;
  final String text;
  final String? id;
  final String? subtitle;

  Map<String, dynamic> toJson() =>
      {'kind': kind, 'text': text, 'id': id, 'subtitle': subtitle};

  SearchSuggestItem toEntity() => SearchSuggestItem(
      kind: SuggestKind.fromApi(kind), text: text, id: id, subtitle: subtitle);
}

/// GET /search/discover?lat=&lng= (guests allowed)
/// { "trending": ["bún riêu", …],
///   "categories": [{ "id": "main", "label": "Món chính", "query": "cơm" }],
///   "seasonal": [{ "recipeId": "ds2", "name": "Súp bí đỏ đậu lăng",
///                  "ingredient": "bí đỏ", "coverSeed": "ds2" }],
///   "popularRecipes": [RecipeSummaryDto…],
///   "nearbyRestaurants": [RestaurantDto…] }   // nearest first, with distanceKm
/// "Xu hướng" can come from the optional `search_logs` table.
class SearchDiscoverDto {
  const SearchDiscoverDto({
    this.trending = const [],
    this.categories = const [],
    this.seasonal = const [],
    this.popularRecipes = const [],
    this.nearbyRestaurants = const [],
  });

  factory SearchDiscoverDto.fromJson(Map<String, dynamic> json) =>
      SearchDiscoverDto(
        trending: readStringList(json['trending']),
        categories: _list(json['categories'], (c) => c),
        seasonal: _list(json['seasonal'], (s) => s),
        popularRecipes:
            _list(json['popularRecipes'], RecipeSummaryDto.fromJson),
        nearbyRestaurants:
            _list(json['nearbyRestaurants'], RestaurantDto.fromJson),
      );

  final List<String> trending;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> seasonal;
  final List<RecipeSummaryDto> popularRecipes;
  final List<RestaurantDto> nearbyRestaurants;

  SearchDiscover toEntity() => SearchDiscover(
        trending: trending,
        categories: [
          for (final c in categories)
            SearchCategory(
              id: c['id']?.toString() ?? '',
              label: c['label'] as String? ?? '',
              query: c['query'] as String? ?? '',
            ),
        ],
        seasonal: [
          for (final s in seasonal)
            if ((s['recipeId'] ?? '').toString().isNotEmpty)
              SeasonalPick(
                recipeId: s['recipeId'].toString(),
                name: s['name'] as String? ?? '',
                ingredient: s['ingredient'] as String? ?? '',
                coverSeed:
                    s['coverSeed'] as String? ?? s['recipeId'].toString(),
              ),
        ],
        popularRecipes: [for (final r in popularRecipes) r.toEntity()],
        nearbyRestaurants: [for (final r in nearbyRestaurants) r.toEntity()],
      );
}
