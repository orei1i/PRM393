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

/// Every distance shown (list, map card, route, sponsored row): 0.367 →
/// "370 m", 1.234 → "1,2 km", 12.6 → "13 km", 1141.2 → "1.141 km"
/// (Vietnamese thousands separator), null → "Chưa có vị trí".
String formatDistance(double? km) {
  if (km == null) return 'Chưa có vị trí';
  if (km < 0.05) return 'Dưới 50 m';
  final meters = (km * 100).round() * 10;
  if (meters < 1000) return '$meters m';
  // 9.96 would read "10,0 km" with one decimal: whole km from there on.
  if (km < 9.95) return '${formatDecimal(km)} km';
  return '${formatInt(km)} km';
}

/// Driving time for a route summary: 540 → "≈ 9 phút", 3900 → "≈ 1 giờ 5
/// phút", under a minute → "≈ 1 phút".
String formatTravelTime(double seconds) {
  final minutes = (seconds / 60).round().clamp(1, 1 << 30);
  if (minutes < 60) return '≈ $minutes phút';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '≈ $hours giờ' : '≈ $hours giờ $rest phút';
}

/// "10.77690, 106.70090": a picked point without a known address.
String formatCoordinates(GeoPoint p) =>
    '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
