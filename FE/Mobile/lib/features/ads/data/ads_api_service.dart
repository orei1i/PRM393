// lib/features/ads/data/ads_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'mock_ads_repository.dart';
import 'models/ad_feed_item.dart';

/// Store ads ("Được tài trợ", public, guests too). Campaigns are managed on
/// the web console (`/ads`); the app shows one row at the top of "Quán chay
/// gần bạn" and reports its impressions and clicks.
abstract interface class AdsApiService {
  /// Running campaigns of [placement] for [city] (or nationwide), nearest
  /// first when [lat] / [lng] are given.
  Future<List<AdFeedItemDto>> getFeed({
    String placement = AdPlacement.nearby,
    String? city,
    double? lat,
    double? lng,
    int limit = AdPlacement.nearbyLimit,
  });

  /// `POST /ads/{id}/impression`: the row was displayed.
  Future<void> reportImpression(String adId);

  /// `POST /ads/{id}/click`: the row (or its button) was tapped.
  Future<void> reportClick(String adId);
}

class RemoteAdsApiService implements AdsApiService {
  RemoteAdsApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<AdFeedItemDto>> getFeed({
    String placement = AdPlacement.nearby,
    String? city,
    double? lat,
    double? lng,
    int limit = AdPlacement.nearbyLimit,
  }) =>
      guardApi(() async {
        final res = await _dio
            .get<List<dynamic>>(ApiEndpoints.adsFeed, queryParameters: {
          'placement': placement,
          if (city != null) 'city': city,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          'limit': limit,
        });
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdFeedItemDto.fromJson)
            .toList();
      });

  @override
  Future<void> reportImpression(String adId) =>
      guardApi(() => _dio.post<void>(ApiEndpoints.adImpression(adId)));

  @override
  Future<void> reportClick(String adId) =>
      guardApi(() => _dio.post<void>(ApiEndpoints.adClick(adId)));
}

final adsApiProvider = Provider<AdsApiService>((ref) {
  if (BackendModules.isMock(BackendModule.ads)) return MockAdsRepository();
  return RemoteAdsApiService(ref.watch(dioProvider));
});
