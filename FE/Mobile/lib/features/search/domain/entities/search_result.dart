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

/// What an autocomplete row opens: a query to search, or the item itself.
enum SuggestKind {
  query('query'),
  recipe('recipe'),
  post('post'),
  restaurant('restaurant');

  const SuggestKind(this.apiValue);
  final String apiValue;

  static SuggestKind fromApi(Object? value) =>
      values.firstWhere((k) => k.apiValue == value?.toString(),
          orElse: () => SuggestKind.query);
}

/// One autocomplete row while typing ("bún riêu chay" · Công thức).
class SearchSuggestItem {
  const SearchSuggestItem({
    required this.kind,
    required this.text,
    this.id,
    this.subtitle,
  });

  final SuggestKind kind;
  final String text;

  /// The recipe, post or restaurant to open; `null` for a query.
  final String? id;
  final String? subtitle;
}

/// A tile of the "Danh mục" grid: searches [query].
class SearchCategory {
  const SearchCategory(
      {required this.id, required this.label, required this.query});

  final String id;
  final String label;
  final String query;
}

/// "Món theo mùa": a recipe built on an in-season [ingredient].
class SeasonalPick {
  const SeasonalPick({
    required this.recipeId,
    required this.name,
    required this.ingredient,
    required this.coverSeed,
  });

  final String recipeId;
  final String name;
  final String ingredient;
  final String coverSeed;
}

/// The idle search page: what to look for before typing anything.
class SearchDiscover {
  const SearchDiscover({
    this.trending = const [],
    this.categories = const [],
    this.seasonal = const [],
    this.popularRecipes = const [],
    this.nearbyRestaurants = const [],
  });

  /// "Xu hướng tìm kiếm", most searched first.
  final List<String> trending;
  final List<SearchCategory> categories;
  final List<SeasonalPick> seasonal;

  /// "Công thức được yêu thích".
  final List<RecipeSummary> popularRecipes;

  /// "Quán chay gần bạn", nearest first.
  final List<Restaurant> nearbyRestaurants;
}

/// "Đã xem gần đây": an item opened from search (kept on the device).
class RecentView {
  const RecentView({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
  });

  factory RecentView.fromJson(Map<String, dynamic> json) => RecentView(
        kind: SuggestKind.fromApi(json['kind']),
        id: json['id']?.toString() ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String?,
      );

  /// [SuggestKind.recipe], [SuggestKind.post] or [SuggestKind.restaurant].
  final SuggestKind kind;
  final String id;
  final String title;
  final String? subtitle;

  Map<String, dynamic> toJson() => {
        'kind': kind.apiValue,
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
      };
}
