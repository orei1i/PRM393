// lib/features/ads/data/models/ad_feed_item.dart
//
// GET /ads/feed?placement=nearby&city=&lat=&lng=&limit=1   (public, guests allowed)
// Same item shape as the web admin's `AdFeedItem` (FE/Web src/types/ads.ts):
// only Running campaigns of that placement (default nearby) whose targetCity
// is null or equals `city` (case / diacritic-insensitive); with lat/lng the
// server adds `distanceKm` and sorts nearest first. The app shows at most one
// "Được tài trợ" row, at the top of "Quán chay gần bạn" (and a ringed marker
// in its map mode); never in the feed or a post.
// POST /ads/{id}/impression (first display of the row on a screen) and
// POST /ads/{id}/click (each tap) → 204; failures are ignored.
// {
//   "id": "ad_hanh_tam", "restaurantId": "rs_hanh_tam", "placement": "nearby",
//   "restaurant": { "id": "rs_hanh_tam", "name": "Bún Riêu Chay Hạnh Tâm",
//     "address": "152 Đinh Tiên Hoàng, …", "isVeganCertified": true,
//     "latitude": 10.8003, "longitude": 106.6977,
//     "averageRating": 4.75, "reviewCount": 4 },
//   "headline": "…", "message": "…",
//   "ctaType": "ViewStore",            // ViewStore | Directions | Book
//   "ctaLabel": "Xem quán",
//   "targetCity": "TP. Hồ Chí Minh",   // null = toàn quốc
//   "startAt": "…", "endAt": "…",
//   "distanceKm": 2.6                  // null without lat/lng or coordinates
// }
// `averageRating`, `reviewCount` and `distanceKm` are computed by BE.
import '../../../../core/utils/json_helpers.dart';

/// `ad_campaigns.placement`: where the app shows a campaign. Only one today.
abstract final class AdPlacement {
  /// The top row of "Quán chay gần bạn".
  static const nearby = 'nearby';

  /// At most this many sponsored rows per list (web `AD_NEARBY_LIMIT`).
  static const nearbyLimit = 1;
}

/// What the card's button does (`ad_campaigns.cta_type`).
enum AdCtaType {
  viewStore('ViewStore', 'Xem quán'),
  directions('Directions', 'Chỉ đường'),
  book('Book', 'Đặt bàn');

  const AdCtaType(this.apiValue, this.label);
  final String apiValue;

  /// Fallback when the server sends no `ctaLabel`.
  final String label;

  static AdCtaType fromApi(Object? value) {
    final raw = (value?.toString() ?? '').replaceAll('_', '').toLowerCase();
    return values.firstWhere((t) => t.apiValue.toLowerCase() == raw,
        orElse: () => AdCtaType.viewStore);
  }
}

class AdRestaurantDto {
  const AdRestaurantDto({
    required this.id,
    required this.name,
    required this.address,
    this.isVeganCertified = false,
    this.latitude,
    this.longitude,
    this.averageRating,
    this.reviewCount = 0,
  });

  factory AdRestaurantDto.fromJson(Map<String, dynamic> json) =>
      AdRestaurantDto(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        isVeganCertified: json['isVeganCertified'] == true,
        latitude:
            json['latitude'] == null ? null : readDouble(json['latitude']),
        longitude:
            json['longitude'] == null ? null : readDouble(json['longitude']),
        averageRating: json['averageRating'] == null
            ? null
            : readDouble(json['averageRating']),
        reviewCount: readInt(json['reviewCount']),
      );

  final String id;
  final String name;
  final String address;
  final bool isVeganCertified;
  final double? latitude;
  final double? longitude;

  /// `null` until the first review.
  final double? averageRating;
  final int reviewCount;

  bool get hasLocation => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'isVeganCertified': isVeganCertified,
        'latitude': latitude,
        'longitude': longitude,
        'averageRating': averageRating,
        'reviewCount': reviewCount,
      };
}

/// A "Được tài trợ" row of "Quán chay gần bạn".
class AdFeedItemDto {
  const AdFeedItemDto({
    required this.id,
    required this.restaurantId,
    this.placement = AdPlacement.nearby,
    required this.restaurant,
    required this.headline,
    required this.message,
    required this.ctaType,
    required this.ctaLabel,
    this.targetCity,
    this.startAt,
    this.endAt,
    this.distanceKm,
  });

  factory AdFeedItemDto.fromJson(Map<String, dynamic> json) {
    final cta = AdCtaType.fromApi(json['ctaType']);
    final label = json['ctaLabel'] as String?;
    return AdFeedItemDto(
      id: json['id']?.toString() ?? '',
      restaurantId: json['restaurantId']?.toString() ?? '',
      placement: json['placement'] as String? ?? AdPlacement.nearby,
      restaurant: AdRestaurantDto.fromJson(readMap(json['restaurant'])),
      headline: json['headline'] as String? ?? '',
      message: json['message'] as String? ?? '',
      ctaType: cta,
      ctaLabel: (label == null || label.trim().isEmpty) ? cta.label : label,
      targetCity: json['targetCity'] as String?,
      startAt: readDateTime(json['startAt']),
      endAt: readDateTime(json['endAt']),
      distanceKm:
          json['distanceKm'] == null ? null : readDouble(json['distanceKm']),
    );
  }

  final String id;
  final String restaurantId;
  final String placement;
  final AdRestaurantDto restaurant;
  final String headline;
  final String message;
  final AdCtaType ctaType;
  final String ctaLabel;

  /// `null` = toàn quốc.
  final String? targetCity;
  final DateTime? startAt;
  final DateTime? endAt;
  final double? distanceKm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'restaurantId': restaurantId,
        'placement': placement,
        'restaurant': restaurant.toJson(),
        'headline': headline,
        'message': message,
        'ctaType': ctaType.apiValue,
        'ctaLabel': ctaLabel,
        'targetCity': targetCity,
        'startAt': startAt?.toUtc().toIso8601String(),
        'endAt': endAt?.toUtc().toIso8601String(),
        'distanceKm': distanceKm,
      };
}
