// lib/features/ads/presentation/controllers/ads_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../restaurant/data/location_service.dart';
import '../../data/ads_api_service.dart';
import '../../data/models/ad_feed_item.dart';

/// Campaign targeting when the location's city is unknown (the simulated
/// position is in TP.HCM).
const adCity = 'TP. Hồ Chí Minh';

/// The "Được tài trợ" row of "Quán chay gần bạn" (`placement=nearby`,
/// `limit=1`, so at most one item), nearest to the user's location;
/// refetched when the location changes. Public: the same for guests and
/// members. Empty when no campaign runs there, and on any failure (the list
/// simply has no sponsored row).
final nearbyAdsProvider =
    FutureProvider.autoDispose<List<AdFeedItemDto>>((ref) async {
  final location = await ref.watch(userLocationProvider.future);
  try {
    final ads = await ref.watch(adsApiProvider).getFeed(
          placement: AdPlacement.nearby,
          city: location.city ?? (location.isSimulated ? adCity : null),
          lat: location.point.latitude,
          lng: location.point.longitude,
          limit: AdPlacement.nearbyLimit,
        );
    return ads.take(AdPlacement.nearbyLimit).toList();
  } catch (_) {
    return const [];
  }
});

/// Reports what the user saw and tapped. Failures never reach the UI.
final adEventsProvider =
    Provider<AdEvents>((ref) => AdEvents(ref.watch(adsApiProvider)));

class AdEvents {
  const AdEvents(this._api);

  final AdsApiService _api;

  Future<void> impression(String adId) async {
    try {
      await _api.reportImpression(adId);
    } catch (_) {
      // counters are best effort
    }
  }

  Future<void> click(String adId) async {
    try {
      await _api.reportClick(adId);
    } catch (_) {
      // counters are best effort
    }
  }
}
