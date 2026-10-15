// lib/features/search/data/models/search_models.dart
//
// GET /search?q=bún%20riêu&type=all|post|video|recipe|restaurant&lat=&lng=&limit=10
// { "query": "bún riêu",
//   "posts":  [PostDto…],          // mediaType Text/Image, status Published only
//   "videos": [PostDto…],          // mediaType Video, status Published only
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
