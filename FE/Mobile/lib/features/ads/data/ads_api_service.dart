// lib/features/ads/data/ads_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'mock_ads_repository.dart';
import 'models/ad_feed_item.dart';

/// Store ads shown as "Được tài trợ" cards (public, guests too). Campaigns
/// are managed on the web console (`/ads`).
abstract interface class AdsApiService {
  /// Running campaigns for [city] (or nationwide), nearest first when
  /// [lat] / [lng] are given.
  Future<List<AdFeedItemDto>> getFeed(
      {String? city, double? lat, double? lng, int limit = 3});
}

class RemoteAdsApiService implements AdsApiService {
  RemoteAdsApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<AdFeedItemDto>> getFeed(
          {String? city, double? lat, double? lng, int limit = 3}) =>
      guardApi(() async {
        final res = await _dio
            .get<List<dynamic>>(ApiEndpoints.adsFeed, queryParameters: {
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
}

final adsApiProvider = Provider<AdsApiService>((ref) {
  if (Env.useMockData) return MockAdsRepository();
  return RemoteAdsApiService(ref.watch(dioProvider));
});
