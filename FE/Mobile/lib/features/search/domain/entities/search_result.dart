// lib/features/search/domain/entities/search_result.dart
import '../../../community/domain/entities/post.dart';
import '../../../restaurant/domain/entities/restaurant.dart';

/// `type` query value of `GET /search`.
enum SearchType {
  all('all'),
  post('post'),
  video('video'),
  recipe('recipe'),
  restaurant('restaurant');

  const SearchType(this.apiValue);
  final String apiValue;
}

/// A catalogue dish, opened with `RecipeDetailScreen.route(id, name:)`.
class RecipeSummary {
  const RecipeSummary({
    required this.id,
    required this.name,
    this.calories,
    this.isVegan = true,
  });

  final String id;
  final String name;

  /// `recipes.calories_cache`; null when not computed yet.
  final int? calories;
  final bool isVegan;
}

/// "Gợi ý cho «tên món»": the best matching recipe with related videos and
/// posts, and restaurants whose reviews mention the dish.
class SearchSuggestion {
  const SearchSuggestion({
    required this.recipe,
    this.relatedPosts = const [],
    this.restaurants = const [],
  });

  final RecipeSummary recipe;

  /// Videos first.
  final List<Post> relatedPosts;

  /// Nearest first, at most 3.
  final List<Restaurant> restaurants;
}

class SearchResult {
  const SearchResult({
    required this.query,
    this.posts = const [],
    this.videos = const [],
    this.recipes = const [],
    this.restaurants = const [],
    this.suggestion,
  });

  final String query;

  /// Published text/image posts (recipes shared by members, discussions).
  final List<Post> posts;

  /// Published video posts.
  final List<Post> videos;
  final List<RecipeSummary> recipes;
  final List<Restaurant> restaurants;
  final SearchSuggestion? suggestion;

  bool get isEmpty =>
      posts.isEmpty &&
      videos.isEmpty &&
      recipes.isEmpty &&
      restaurants.isEmpty &&
      suggestion == null;
}
