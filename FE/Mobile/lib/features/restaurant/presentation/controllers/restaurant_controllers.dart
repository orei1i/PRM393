// lib/features/restaurant/presentation/controllers/restaurant_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/location_service.dart';
import '../../data/models/restaurant_model.dart';
import '../../data/restaurant_api_service.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';

/// The "Bộ lọc" sheet's choices.
class RestaurantFilters {
  const RestaurantFilters({
    this.certifiedOnly = false,
    this.sort = RestaurantSort.distance,
    this.radiusKm,
  });

  static const defaults = RestaurantFilters();

  final bool certifiedOnly;
  final RestaurantSort sort;

  /// `null` = "Không giới hạn".
  final double? radiusKm;

  /// The badge on "Bộ lọc": choices that differ from [defaults].
  int get activeCount =>
      (certifiedOnly ? 1 : 0) +
      (sort != RestaurantSort.distance ? 1 : 0) +
      (radiusKm != null ? 1 : 0);

  RestaurantFilters copyWith({
    bool? certifiedOnly,
    RestaurantSort? sort,
    double? Function()? radiusKm,
  }) =>
      RestaurantFilters(
        certifiedOnly: certifiedOnly ?? this.certifiedOnly,
        sort: sort ?? this.sort,
        radiusKm: radiusKm == null ? this.radiusKm : radiusKm(),
      );

  @override
  bool operator ==(Object other) =>
      other is RestaurantFilters &&
      other.certifiedOnly == certifiedOnly &&
      other.sort == sort &&
      other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(certifiedOnly, sort, radiusKm);
}

/// "1 km", "10 km"; `null` → "Không giới hạn".
String radiusLabel(double? km) {
  if (km == null) return 'Không giới hạn';
  return km == km.roundToDouble() ? '${km.round()} km' : '$km km';
}

/// The map area "Tìm trong khu vực này" searches instead of the user's
/// surroundings.
class MapArea {
  const MapArea({required this.center, required this.radiusKm});

  final GeoPoint center;
  final double radiusKm;
}

class RestaurantListState {
  const RestaurantListState({
    required this.restaurants,
    required this.location,
    this.query = '',
    this.filters = RestaurantFilters.defaults,
    this.area,
    this.searching = false,
  });

  final List<Restaurant> restaurants;
  final UserLocation location;
  final String query;
  final RestaurantFilters filters;

  /// Set after "Tìm trong khu vực này"; distances stay measured from
  /// [location].
  final MapArea? area;

  /// New filters are in flight; the previous rows stay on screen.
  final bool searching;

  bool get certifiedOnly => filters.certifiedOnly;
  RestaurantSort get sort => filters.sort;
  double? get radiusKm => filters.radiusKm;

  /// Whether [r] fits the area and the "Bộ lọc" choices that decide which
  /// places belong in this list (the sponsored row obeys them too).
  bool admits(Restaurant r) {
    if (certifiedOnly && !r.isVeganCertified) return false;
    final area = this.area;
    if (area != null) {
      final point = r.location;
      return point != null && haversineKm(area.center, point) <= area.radiusKm;
    }
    final radius = radiusKm;
    if (radius == null) return true;
    final distance = r.distanceKm ??
        (r.location == null ? null : haversineKm(location.point, r.location!));
    return distance != null && distance <= radius;
  }

  /// "14 quán · trong 5 km · gần nhất trước".
  String get summary => [
        '${restaurants.length} quán',
        if (area != null)
          'trong khu vực bản đồ'
        else if (radiusKm != null)
          'trong ${radiusLabel(radiusKm)}',
        sort == RestaurantSort.distance
            ? 'gần nhất trước'
            : 'đánh giá cao trước',
      ].join(' · ');

  RestaurantListState copyWith({bool? searching}) => RestaurantListState(
        restaurants: restaurants,
        location: location,
        query: query,
        filters: filters,
        area: area,
        searching: searching ?? this.searching,
      );
}

/// "Quán chay gần bạn", keyed by the screen's initial query ('' for none).
/// Reloads when the user's location changes.
final restaurantListProvider = AsyncNotifierProvider.autoDispose
    .family<RestaurantListController, RestaurantListState, String>(
        RestaurantListController.new);

class RestaurantListController
    extends AutoDisposeFamilyAsyncNotifier<RestaurantListState, String> {
  // Kept across rebuilds (e.g. after a review elsewhere invalidates us).
  String? _query;
  RestaurantFilters _filters = RestaurantFilters.defaults;
  MapArea? _area;
  int _requestId = 0;

  @override
  Future<RestaurantListState> build(String arg) async {
    _query ??= arg.trim();
    final api = ref.watch(restaurantApiProvider);
    final location = await ref.watch(userLocationProvider.future);
    // A new location searches around it again.
    if (_area != null && state.valueOrNull?.location.point != location.point) {
      _area = null;
    }
    return _fetch(api, location);
  }

  Future<RestaurantListState> _fetch(
      RestaurantApiService api, UserLocation location) async {
    final area = _area;
    final list = await api.listRestaurants(
      near: area?.center ?? location.point,
      query: _query,
      certifiedOnly: _filters.certifiedOnly,
      sort: _filters.sort,
      radiusKm: area?.radiusKm ?? _filters.radiusKm,
    );
    var restaurants = list.map((r) => r.toEntity()).toList();
    if (area != null) {
      restaurants = [
        for (final r in restaurants)
          r.withDistance(r.location == null
              ? null
              : haversineKm(location.point, r.location!)),
      ];
    }
    return RestaurantListState(
      restaurants: restaurants,
      location: location,
      query: _query ?? '',
      filters: _filters,
      area: area,
    );
  }

  Future<void> search(String query) {
    if (query.trim() == _query && state.hasValue) return Future.value();
    _query = query.trim();
    return refresh();
  }

  Future<void> applyFilters(RestaurantFilters filters) {
    if (filters == _filters && state.hasValue) return Future.value();
    _filters = filters;
    return refresh();
  }

  Future<void> setCertifiedOnly(bool value) =>
      applyFilters(_filters.copyWith(certifiedOnly: value));

  Future<void> setSort(RestaurantSort sort) =>
      applyFilters(_filters.copyWith(sort: sort));

  Future<void> setRadius(double? km) =>
      applyFilters(_filters.copyWith(radiusKm: () => km));

  /// "Tìm trong khu vực này": restaurants around [area] instead.
  Future<void> searchArea(MapArea area) {
    _area = area;
    return refresh();
  }

  /// Back to the user's surroundings.
  Future<void> clearArea() {
    if (_area == null) return Future.value();
    _area = null;
    return refresh();
  }

  /// Reloads with the current filters, keeping the rows on screen meanwhile.
  Future<void> refresh() async {
    final id = ++_requestId;
    state = state.hasValue
        ? AsyncData(state.requireValue.copyWith(searching: true))
        : const AsyncLoading();
    final next = await AsyncValue.guard(() async => _fetch(
        ref.read(restaurantApiProvider),
        await ref.read(userLocationProvider.future)));
    if (id == _requestId) state = next; // drop stale responses while typing
  }
}

class RestaurantDetailState {
  const RestaurantDetailState({
    required this.restaurant,
    required this.reviews,
    this.media = const [],
  });

  final Restaurant restaurant;

  /// Newest first.
  final List<RestaurantReview> reviews;

  /// "Ảnh & video", oldest first; empty when none (or when they failed to
  /// load: the page still works without them).
  final List<RestaurantMedia> media;

  RestaurantReview? reviewBy(String? userId) {
    if (userId == null) return null;
    for (final r in reviews) {
      if (r.userId == userId) return r;
    }
    return null;
  }

  /// Review counts for 1★…5★ (index 0 = 1★).
  List<int> get starCounts {
    final counts = List<int>.filled(5, 0);
    for (final r in reviews) {
      counts[r.rating.clamp(1, 5) - 1]++;
    }
    return counts;
  }

  /// [review] added, or swapped for the member's earlier one, with the
  /// average and count recomputed from the list.
  RestaurantDetailState withReview(RestaurantReview review) {
    final next = [
      review,
      ...reviews.where((r) => r.id != review.id && r.userId != review.userId),
    ];
    final avg = next.fold<int>(0, (s, r) => s + r.rating) / next.length;
    final r = restaurant;
    return RestaurantDetailState(
      restaurant: Restaurant(
        id: r.id,
        name: r.name,
        address: r.address,
        isVeganCertified: r.isVeganCertified,
        location: r.location,
        distanceKm: r.distanceKm,
        averageRating: avg,
        reviewCount: next.length,
        createdById: r.createdById,
        createdByName: r.createdByName,
      ),
      reviews: next,
      media: media,
    );
  }
}

/// A restaurant with its reviews; dropped when the screen closes.
final restaurantDetailProvider = AsyncNotifierProvider.autoDispose
    .family<RestaurantDetailController, RestaurantDetailState, String>(
        RestaurantDetailController.new);

class RestaurantDetailController
    extends AutoDisposeFamilyAsyncNotifier<RestaurantDetailState, String> {
  bool _disposed = false;

  @override
  Future<RestaurantDetailState> build(String arg) async {
    ref.onDispose(() => _disposed = true);
    final api = ref.watch(restaurantApiProvider);
    final location = await ref.watch(userLocationProvider.future);
    return _fetch(api, arg, location.point);
  }

  static Future<RestaurantDetailState> _fetch(
      RestaurantApiService api, String id, GeoPoint near) async {
    final results = await Future.wait<Object>([
      api.getRestaurant(id, near: near),
      api.getReviews(id),
      _media(api, id),
    ]);
    return RestaurantDetailState(
      restaurant: (results[0] as RestaurantDto).toEntity(),
      reviews: [for (final r in results[1] as List<ReviewDto>) r.toEntity()],
      media: results[2] as List<RestaurantMedia>,
    );
  }

  /// The page works without its photos, so a failure here is not an error.
  static Future<List<RestaurantMedia>> _media(
      RestaurantApiService api, String id) async {
    try {
      return [for (final m in await api.getMedia(id)) m.toEntity()];
    } catch (_) {
      return const [];
    }
  }

  /// Saves the member's review (one per restaurant: a re-submit replaces
  /// it). Throws on failure so the sheet can show the error. Returns true
  /// when an earlier review was replaced.
  Future<bool> submitReview(
      {required int rating, required String comment}) async {
    final api = ref.read(restaurantApiProvider);
    final saved =
        (await api.upsertReview(arg, rating: rating, comment: comment.trim()))
            .toEntity();
    if (_disposed) return false;
    final current = state.valueOrNull;
    final replaced = current?.reviewBy(saved.userId) != null;
    try {
      final location = await ref.read(userLocationProvider.future);
      final next = await _fetch(api, arg, location.point);
      if (!_disposed) state = AsyncData(next);
    } catch (_) {
      // Saved anyway: patch the screen locally instead of failing.
      if (!_disposed && current != null) {
        state = AsyncData(current.withReview(saved));
      }
    }
    // Averages on the nearby list changed too.
    if (!_disposed) ref.invalidate(restaurantListProvider);
    return replaced;
  }
}
