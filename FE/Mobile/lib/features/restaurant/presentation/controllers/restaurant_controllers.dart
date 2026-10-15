// lib/features/restaurant/presentation/controllers/restaurant_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/location_service.dart';
import '../../data/models/restaurant_model.dart';
import '../../data/restaurant_api_service.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';

class RestaurantListState {
  const RestaurantListState({
    required this.restaurants,
    required this.location,
    this.query = '',
    this.certifiedOnly = false,
    this.sort = RestaurantSort.distance,
    this.searching = false,
  });

  final List<Restaurant> restaurants;
  final UserLocation location;
  final String query;
  final bool certifiedOnly;
  final RestaurantSort sort;

  /// New filters are in flight; the previous rows stay on screen.
  final bool searching;

  RestaurantListState copyWith({bool? searching}) => RestaurantListState(
        restaurants: restaurants,
        location: location,
        query: query,
        certifiedOnly: certifiedOnly,
        sort: sort,
        searching: searching ?? this.searching,
      );
}

/// "Quán chay gần bạn", keyed by the screen's initial query ('' for none).
final restaurantListProvider = AsyncNotifierProvider.autoDispose
    .family<RestaurantListController, RestaurantListState, String>(
        RestaurantListController.new);

class RestaurantListController
    extends AutoDisposeFamilyAsyncNotifier<RestaurantListState, String> {
  // Kept across rebuilds (e.g. after a review elsewhere invalidates us).
  String? _query;
  bool _certifiedOnly = false;
  RestaurantSort _sort = RestaurantSort.distance;
  int _requestId = 0;

  @override
  Future<RestaurantListState> build(String arg) async {
    _query ??= arg.trim();
    final api = ref.watch(restaurantApiProvider);
    final location = await ref.watch(userLocationProvider.future);
    return _fetch(api, location);
  }

  Future<RestaurantListState> _fetch(
      RestaurantApiService api, UserLocation location) async {
    final list = await api.listRestaurants(
      near: location.point,
      query: _query,
      certifiedOnly: _certifiedOnly,
      sort: _sort,
    );
    return RestaurantListState(
      restaurants: list.map((r) => r.toEntity()).toList(),
      location: location,
      query: _query ?? '',
      certifiedOnly: _certifiedOnly,
      sort: _sort,
    );
  }

  Future<void> search(String query) {
    if (query.trim() == _query && state.hasValue) return Future.value();
    _query = query.trim();
    return refresh();
  }

  Future<void> setCertifiedOnly(bool value) {
    if (value == _certifiedOnly && state.hasValue) return Future.value();
    _certifiedOnly = value;
    return refresh();
  }

  Future<void> setSort(RestaurantSort sort) {
    if (sort == _sort && state.hasValue) return Future.value();
    _sort = sort;
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
  const RestaurantDetailState(
      {required this.restaurant, required this.reviews});

  final Restaurant restaurant;

  /// Newest first.
  final List<RestaurantReview> reviews;

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
    final results = await Future.wait<Object>(
        [api.getRestaurant(id, near: near), api.getReviews(id)]);
    return RestaurantDetailState(
      restaurant: (results[0] as RestaurantDto).toEntity(),
      reviews: [for (final r in results[1] as List<ReviewDto>) r.toEntity()],
    );
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
