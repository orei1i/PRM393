// lib/features/restaurant/data/location_service.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/utils/json_helpers.dart';
import '../domain/geo.dart';

/// How a [UserLocation] was chosen.
enum UserLocationSource {
  /// "Dùng vị trí hiện tại (mô phỏng)": the device position (simulated).
  current('current'),

  /// An address search result ("Tìm địa chỉ").
  search('search'),

  /// "Chọn trên bản đồ".
  map('map');

  const UserLocationSource(this.key);
  final String key;

  static UserLocationSource fromKey(Object? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => current);
}

/// Where "gần bạn" is measured from: nearby list, search "Quán", discover,
/// sponsored row and the route origin.
class UserLocation {
  const UserLocation({
    required this.point,
    required this.label,
    this.isSimulated = false,
    this.source = UserLocationSource.current,
    this.address,
    this.city,
  });

  final GeoPoint point;

  /// "Quận 1, TP.HCM (vị trí mô phỏng)", "Chợ Bến Thành"…
  final String label;
  final bool isSimulated;
  final UserLocationSource source;

  /// Full address line, when known ("Lê Lợi, P. Bến Thành, Q.1, TP.HCM").
  final String? address;

  /// Campaign targeting for the sponsored row ("TP. Hồ Chí Minh", same
  /// spelling as the web's AD_CITIES); `null` = unknown.
  final String? city;

  Map<String, dynamic> toJson() => {
        'lat': point.latitude,
        'lng': point.longitude,
        'label': label,
        'isSimulated': isSimulated,
        'source': source.key,
        'address': address,
        'city': city,
      };

  /// `null` for anything unreadable (an older app version, a broken value).
  static UserLocation? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final lat = json['lat'], lng = json['lng'], label = json['label'];
    if (lat is! num || lng is! num || label is! String || label.isEmpty) {
      return null;
    }
    return UserLocation(
      point: GeoPoint(readDouble(lat), readDouble(lng)),
      label: label,
      isSimulated: json['isSimulated'] == true,
      source: UserLocationSource.fromKey(json['source']),
      address: json['address'] as String?,
      city: json['city'] as String?,
    );
  }

  bool samePlace(UserLocation other) =>
      other.point == point && other.label == label;
}

abstract interface class LocationService {
  Future<UserLocation> currentLocation();
}

/// Fixed point near Nhà hát Thành phố, Q.1. Real GPS needs the `geolocator`
/// package, which is not a dependency yet (needs approval), so every build
/// uses this for "Dùng vị trí hiện tại"; the server still receives real
/// `lat`/`lng` params.
class MockLocationService implements LocationService {
  const MockLocationService();

  static const point = GeoPoint(10.7769, 106.7009);
  static const label = 'Quận 1, TP.HCM (vị trí mô phỏng)';
  static const city = 'TP. Hồ Chí Minh';

  static const location = UserLocation(
    point: point,
    label: label,
    isSimulated: true,
    address: '7 Công trường Lam Sơn, P. Bến Nghé, Q.1, TP.HCM',
    city: city,
  );

  @override
  Future<UserLocation> currentLocation() async => location;
}

final locationServiceProvider =
    Provider<LocationService>((ref) => const MockLocationService());

SharedPreferences? _prefsOrNull(Ref<Object?> ref) {
  try {
    return ref.read(sharedPreferencesProvider);
  } catch (_) {
    return null; // a bare ProviderContainer in tests: nothing to persist
  }
}

/// The location the app measures from. Starts from the saved choice
/// (`vl.user_location`) or the device position; [setLocation] changes it and
/// every list watching `userLocationProvider.future` reloads.
final userLocationProvider =
    AsyncNotifierProvider<UserLocationController, UserLocation>(
        UserLocationController.new);

class UserLocationController extends AsyncNotifier<UserLocation> {
  static const prefsKey = 'vl.user_location';

  @override
  Future<UserLocation> build() async {
    final prefs = _prefsOrNull(ref);
    final saved = prefs?.getString(prefsKey);
    if (saved != null) {
      try {
        final parsed = UserLocation.fromJson(jsonDecode(saved));
        if (parsed != null) return parsed;
      } catch (_) {
        // fall through to the device position
      }
    }
    return ref.watch(locationServiceProvider).currentLocation();
  }

  /// Measures from [location] from now on (and after a restart).
  Future<void> setLocation(UserLocation location) async {
    state = AsyncData(location);
    final prefs = _prefsOrNull(ref);
    await prefs?.setString(prefsKey, jsonEncode(location.toJson()));
    if (location.source != UserLocationSource.current) {
      await ref.read(recentLocationsProvider.notifier).add(location);
    }
  }

  /// Back to "Dùng vị trí hiện tại" (simulated until GPS is approved).
  Future<UserLocation> useCurrent() async {
    final current = await ref.read(locationServiceProvider).currentLocation();
    await setLocation(current);
    return current;
  }
}

/// "Vị trí gần đây" of the location picker: searched or map-picked places,
/// newest first, at most [RecentLocationsController.max]
/// (`vl.recent_locations`).
final recentLocationsProvider =
    NotifierProvider<RecentLocationsController, List<UserLocation>>(
        RecentLocationsController.new);

class RecentLocationsController extends Notifier<List<UserLocation>> {
  static const prefsKey = 'vl.recent_locations';
  static const max = 5;

  @override
  List<UserLocation> build() {
    final raw = _prefsOrNull(ref)?.getStringList(prefsKey) ?? const [];
    final list = <UserLocation>[];
    for (final item in raw) {
      try {
        final parsed = UserLocation.fromJson(jsonDecode(item));
        if (parsed != null) list.add(parsed);
      } catch (_) {
        // skip a broken entry
      }
    }
    return list;
  }

  Future<void> add(UserLocation location) async {
    state = [
      location,
      ...state.where((l) => !l.samePlace(location)),
    ].take(max).toList();
    await _prefsOrNull(ref)?.setStringList(
        prefsKey, [for (final l in state) jsonEncode(l.toJson())]);
  }

  Future<void> clear() async {
    state = const [];
    await _prefsOrNull(ref)?.remove(prefsKey);
  }
}
