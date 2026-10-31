// lib/core/navigation/app_routes.dart
import '../utils/text_search.dart';

/// Names of the pushed pages that [AppNav] looks for in the stack, set as
/// `RouteSettings.name` by each screen's `route()`. Pages that show one item
/// carry its id, so "the same page" means the same item: `/recipe/l5` and
/// `/recipe/menu_1` are different pages, two `/search` pages are not.
abstract final class AppRoutes {
  /// Recipe detail.
  static String recipe(String id) => '/recipe/$id';

  /// Ingredient detail: by DB id, else by the name without diacritics
  /// ("Cà chua" → `/ingredient/ca chua`).
  static String ingredient({String? id, required String name}) =>
      '/ingredient/${id ?? foldVietnamese(name.trim())}';

  /// Global search (whatever the query).
  static const String search = '/search';

  /// One chef booking (either party).
  static String booking(String id) => '/booking/$id';

  /// "Lịch sử tư vấn".
  static const String bookingHistory = '/booking-history';

  /// "Theo dõi cân nặng".
  static const String bodyMetrics = '/body-metrics';

  /// A community post (video, recipe, tip…).
  static String post(String id) => '/post/$id';

  /// A restaurant page.
  static String restaurant(String id) => '/restaurant/$id';
}
