// lib/features/search/data/search_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../community/data/community_api_service.dart';
import '../../restaurant/data/restaurant_api_service.dart';
import '../../restaurant/domain/geo.dart';
import '../domain/entities/search_result.dart';
import 'mock_search_repository.dart';
import 'models/search_models.dart';

/// Global search across posts, videos, recipes and restaurants. Guests
/// allowed; only `Published` posts are ever returned.
abstract interface class SearchApiService {
  /// [near] adds `distanceKm` to restaurants and orders them nearest first.
  /// [limit] applies per group.
  Future<SearchResultDto> search(
    String query, {
    SearchType type = SearchType.all,
    GeoPoint? near,
    int limit = 10,
  });

  /// Autocomplete while typing (2+ characters): queries, recipes, posts and
  /// restaurants, at most [limit].
  Future<List<SearchSuggestItemDto>> suggest(String query, {int limit = 8});

  /// The idle page: trending queries, categories, seasonal dishes, popular
  /// recipes and the nearest restaurants.
  Future<SearchDiscoverDto> discover({GeoPoint? near});
}

class RemoteSearchApiService implements SearchApiService {
  RemoteSearchApiService(this._dio);

  final Dio _dio;

  @override
  Future<SearchResultDto> search(
    String query, {
    SearchType type = SearchType.all,
    GeoPoint? near,
    int limit = 10,
  }) =>
      guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.search,
          queryParameters: {
            'q': query,
            'type': type.apiValue,
            if (near != null) ...{
              'lat': near.latitude,
              'lng': near.longitude,
            },
            'limit': limit,
          },
        );
        return SearchResultDto.fromJson(res.data!);
      });

  @override
  Future<List<SearchSuggestItemDto>> suggest(String query, {int limit = 8}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
          ApiEndpoints.searchSuggest,
          queryParameters: {'q': query, 'limit': limit},
        );
        return SearchSuggestItemDto.listFromJson(res.data);
      });

  @override
  Future<SearchDiscoverDto> discover({GeoPoint? near}) => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.searchDiscover,
          queryParameters: {
            if (near != null) ...{
              'lat': near.latitude,
              'lng': near.longitude,
            },
          },
        );
        return SearchDiscoverDto.fromJson(res.data!);
      });
}

final searchApiProvider = Provider<SearchApiService>((ref) {
  if (BackendModules.isMock(BackendModule.search)) {
    return MockSearchRepository(
      community: ref.watch(communityApiProvider),
      restaurants: ref.watch(restaurantApiProvider),
    );
  }
  return RemoteSearchApiService(ref.watch(dioProvider));
});
