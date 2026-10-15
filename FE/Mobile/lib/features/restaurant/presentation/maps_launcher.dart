// lib/features/restaurant/presentation/maps_launcher.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/entities/restaurant.dart';

/// Opens a URL outside the app; overridden in tests to record the call.
typedef UrlOpener = Future<bool> Function(Uri uri);

final urlOpenerProvider = Provider<UrlOpener>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// "Mở bản đồ": Google Maps search for the address (no map widget in-app).
Uri mapsSearchUri(Restaurant restaurant) => Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': restaurant.address},
    );

/// "Chỉ đường": directions from wherever the phone is (Maps fills in the
/// origin) to the coordinates, or to the address when there are none.
Uri mapsDirectionsUri(Restaurant restaurant) {
  final point = restaurant.location;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': point == null
        ? restaurant.address
        : '${point.latitude},${point.longitude}',
  });
}
