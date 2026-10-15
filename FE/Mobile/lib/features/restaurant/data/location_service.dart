// lib/features/restaurant/data/location_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/geo.dart';

/// Where "gần bạn" is measured from.
class UserLocation {
  const UserLocation({
    required this.point,
    required this.label,
    this.isSimulated = false,
  });

  final GeoPoint point;

  /// "Quận 1, TP.HCM (vị trí mô phỏng)".
  final String label;
  final bool isSimulated;
}

abstract interface class LocationService {
  Future<UserLocation> currentLocation();
}

/// Fixed point near Nhà hát Thành phố, Q.1. Real GPS needs the `geolocator`
/// package, which is not a dependency yet (needs approval), so every build
/// uses this for now; the server still receives real `lat`/`lng` params.
class MockLocationService implements LocationService {
  const MockLocationService();

  static const point = GeoPoint(10.7769, 106.7009);
  static const label = 'Quận 1, TP.HCM (vị trí mô phỏng)';

  @override
  Future<UserLocation> currentLocation() async =>
      const UserLocation(point: point, label: label, isSimulated: true);
}

final locationServiceProvider =
    Provider<LocationService>((ref) => const MockLocationService());

final userLocationProvider = FutureProvider<UserLocation>(
    (ref) => ref.watch(locationServiceProvider).currentLocation());
