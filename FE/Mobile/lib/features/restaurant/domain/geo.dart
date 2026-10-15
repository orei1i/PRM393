// lib/features/restaurant/domain/geo.dart
import 'dart:math' as math;

import '../../../core/utils/formatters.dart';

/// A WGS-84 position (`restaurants.latitude` / `restaurants.longitude`).
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

const double _earthRadiusKm = 6371.0;

/// Great-circle distance in km. The mock uses it for `distanceKm`; the real
/// server computes the same value when the request carries `lat`/`lng`.
double haversineKm(GeoPoint a, GeoPoint b) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.sqrt(h.toDouble()));
}

/// 0.367 → "370 m", 1.234 → "1,2 km", 12.6 → "13 km", null → "Chưa có vị trí".
String formatDistance(double? km) {
  if (km == null) return 'Chưa có vị trí';
  if (km < 0.05) return 'Dưới 50 m';
  final meters = (km * 100).round() * 10;
  if (meters < 1000) return '$meters m';
  if (km < 10) return '${formatDecimal(km)} km';
  return '${km.round()} km';
}
