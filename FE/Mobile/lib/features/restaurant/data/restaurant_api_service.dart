// lib/features/restaurant/data/restaurant_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../domain/entities/restaurant.dart';
import '../domain/geo.dart';
import 'mock_restaurant_repository.dart';
import 'models/restaurant_model.dart';

/// Vegan restaurants and their reviews. Reading is open to guests; writing
/// a review or suggesting a restaurant needs a member token (401 otherwise).
abstract interface class RestaurantApiService {
  /// [near] adds `distanceKm`. [query] matches the name, the address or a
  /// dish mentioned in the reviews. Restaurants without coordinates come last
  /// when sorting by distance. [radiusKm] (with [near]) keeps only places
  /// within that distance, so places without coordinates drop out.
  Future<List<RestaurantDto>> listRestaurants({
    GeoPoint? near,
    String? query,
    bool certifiedOnly = false,
    RestaurantSort sort = RestaurantSort.distance,
    double? radiusKm,
    int? limit,
  });

  /// 404 when it was removed by an admin.
  Future<RestaurantDto> getRestaurant(String id, {GeoPoint? near});

  /// Photos and the intro video (`restaurant_media`), oldest first.
  Future<List<RestaurantMediaDto>> getMedia(String restaurantId);

  /// Newest first.
  Future<List<ReviewDto>> getReviews(String restaurantId);

  /// One review per member and restaurant: a second call replaces the first.
  Future<ReviewDto> upsertReview(String restaurantId,
      {required int rating, required String comment});

  /// Created uncertified, with `createdBy` = the caller.
  Future<RestaurantDto> createRestaurant(CreateRestaurantRequestDto request);

  /// Restaurants whose name or reviews mention [food] (a word typed without
  /// accents matches any accents): the ones naming more of the dish first,
  /// then nearest, then best rated.
  Future<List<RestaurantDto>> suggestedForFood(String food,
      {GeoPoint? near, int limit = 3});
}

class RemoteRestaurantApiService implements RestaurantApiService {
  RemoteRestaurantApiService(this._dio);

  final Dio _dio;

  Map<String, dynamic> _near(GeoPoint? near) =>
      near == null ? const {} : {'lat': near.latitude, 'lng': near.longitude};

  List<RestaurantDto> _restaurants(List<dynamic>? data) => (data ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(RestaurantDto.fromJson)
      .toList();

  @override
  Future<List<RestaurantDto>> listRestaurants({
    GeoPoint? near,
    String? query,
    bool certifiedOnly = false,
    RestaurantSort sort = RestaurantSort.distance,
    double? radiusKm,
    int? limit,
  }) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
          ApiEndpoints.restaurants,
          queryParameters: {
            ..._near(near),
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
            if (certifiedOnly) 'certifiedOnly': true,
            'sort': sort.apiValue,
            if (radiusKm != null && near != null) 'radiusKm': radiusKm,
            if (limit != null) 'limit': limit,
          },
        );
        return _restaurants(res.data);
      });

  @override
  Future<List<RestaurantMediaDto>> getMedia(String restaurantId) =>
      guardApi(() async {
        final res = await _dio
            .get<List<dynamic>>(ApiEndpoints.restaurantMedia(restaurantId));
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RestaurantMediaDto.fromJson)
            .toList();
      });

  @override
  Future<RestaurantDto> getRestaurant(String id, {GeoPoint? near}) =>
      guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
            ApiEndpoints.restaurant(id),
            queryParameters: _near(near));
        return RestaurantDto.fromJson(res.data!);
      });

  @override
  Future<List<ReviewDto>> getReviews(String restaurantId) => guardApi(() async {
        final res = await _dio
            .get<List<dynamic>>(ApiEndpoints.restaurantReviews(restaurantId));
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReviewDto.fromJson)
            .toList();
      });

  @override
  Future<ReviewDto> upsertReview(String restaurantId,
          {required int rating, required String comment}) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.restaurantReviews(restaurantId),
          data: {'rating': rating, 'comment': comment},
        );
        return ReviewDto.fromJson(res.data!);
      });

  @override
  Future<RestaurantDto> createRestaurant(CreateRestaurantRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.restaurants,
            data: request.toJson());
        return RestaurantDto.fromJson(res.data!);
      });

  @override
  Future<List<RestaurantDto>> suggestedForFood(String food,
          {GeoPoint? near, int limit = 3}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
          ApiEndpoints.suggestedRestaurants,
          queryParameters: {'food': food, ..._near(near), 'limit': limit},
        );
        return _restaurants(res.data);
      });
}

final restaurantApiProvider = Provider<RestaurantApiService>((ref) {
  if (Env.useMockData) {
    return MockRestaurantRepository(
      isSignedIn: () => !ref.read(sessionControllerProvider).isGuest,
      currentUserId: () => ref.read(sessionControllerProvider).userId ?? 'u_me',
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Bạn',
    );
  }
  return RemoteRestaurantApiService(ref.watch(dioProvider));
});
