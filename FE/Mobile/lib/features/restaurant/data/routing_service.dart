// lib/features/restaurant/data/routing_service.dart
//
// In-app directions ("Chỉ đường") drawn as a polyline. The app asks the OSRM
// HTTP API directly (driving profile only):
//
// GET {OSRM_BASE_URL}/route/v1/driving/{fromLng},{fromLat};{toLng},{toLat}
//     ?overview=full&geometries=geojson&alternatives=false&steps=false
// { "code": "Ok", "routes": [ { "distance": 2604.3, "duration": 540.1,
//     "geometry": { "type": "LineString", "coordinates": [[106.7009, 10.7769], …] } } ] }
//
// The public demo server (router.project-osrm.org) has no SLA and allows
// about one request per second, so the app sends one request per route
// screen, caches answers in memory for the session, times out after 5 s and
// then draws a straight line with the haversine distance instead. There is
// no turn-by-turn navigation: "Mở bằng Google Maps" stays in the overflow
// menu for that.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/utils/json_helpers.dart';
import '../domain/geo.dart';

/// A route between two points.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    this.durationSeconds,
    this.isStraightLine = false,
  });

  /// From the origin to the destination, at least two points.
  final List<GeoPoint> points;
  final double distanceKm;

  /// Driving time; `null` for a straight line (no road network known).
  final double? durationSeconds;

  /// No road route could be loaded: [points] is just origin → destination.
  final bool isStraightLine;
}

abstract interface class RoutingService {
  /// Throws when no route can be found or the server cannot be reached.
  Future<RouteResult> route(GeoPoint from, GeoPoint to);
}

/// The fallback: a straight line and its great-circle distance.
class StraightLineRoutingService implements RoutingService {
  const StraightLineRoutingService();

  @override
  Future<RouteResult> route(GeoPoint from, GeoPoint to) async => RouteResult(
        points: [from, to],
        distanceKm: haversineKm(from, to),
        isStraightLine: true,
      );
}

/// Thrown when OSRM answers without a usable route (`code` ≠ `Ok`).
class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;

  @override
  String toString() => 'RoutingException: $message';
}

/// OSRM `route` service, driving profile, with an in-memory cache.
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: Env.routingTimeout,
              receiveTimeout: Env.routingTimeout,
              headers: {
                // Identify the app, as the OSRM demo usage policy asks.
                'User-Agent':
                    'VeganLife/0.1 (${Env.mapUserAgentPackageName}; flutter)',
              },
            ));

  final String baseUrl;
  final Dio _dio;

  static final Map<String, RouteResult> _cache = {};

  /// Forget cached routes (tests).
  static void clearCache() => _cache.clear();

  static String _coord(GeoPoint p) =>
      '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}';

  /// The request URL (also the cache key).
  Uri routeUri(GeoPoint from, GeoPoint to) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base/route/v1/driving/${_coord(from)};${_coord(to)}'
        '?overview=full&geometries=geojson&alternatives=false&steps=false');
  }

  @override
  Future<RouteResult> route(GeoPoint from, GeoPoint to) async {
    final uri = routeUri(from, to);
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null) return cached;
    final res = await _dio
        .getUri<Map<String, dynamic>>(uri)
        .timeout(Env.routingTimeout);
    final result = parse(res.data ?? const {}, from: from, to: to);
    _cache[key] = result;
    return result;
  }

  /// Reads an OSRM `route` answer. The geometry is GeoJSON `[lng, lat]`.
  static RouteResult parse(Map<String, dynamic> json,
      {required GeoPoint from, required GeoPoint to}) {
    if (json['code'] != 'Ok') {
      throw RoutingException(
          json['message'] as String? ?? json['code']?.toString() ?? 'no route');
    }
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const RoutingException('no route');
    }
    final route = readMap(routes.first);
    final coords = readMap(route['geometry'])['coordinates'];
    final points = <GeoPoint>[
      if (coords is List)
        for (final c in coords)
          if (c is List && c.length >= 2)
            GeoPoint(readDouble(c[1]), readDouble(c[0])),
    ];
    if (points.length < 2) throw const RoutingException('empty geometry');
    return RouteResult(
      points: points,
      distanceKm: readDouble(route['distance']) / 1000,
      durationSeconds: readDouble(route['duration']),
    );
  }
}

/// OSRM unless `OSRM_BASE_URL` is empty or this is `flutter test` (then the
/// straight line). Tests override it with fakes.
final routingServiceProvider = Provider<RoutingService>((ref) {
  if (Env.osrmBaseUrl.trim().isEmpty || Env.isFlutterTest) {
    return const StraightLineRoutingService();
  }
  return OsrmRoutingService(baseUrl: Env.osrmBaseUrl.trim());
});

/// The route for one (origin, destination) pair. Any failure or a timeout
/// (`Env.routingTimeout` + 1 s at most) falls back to the straight line.
final routeProvider = FutureProvider.autoDispose
    .family<RouteResult, (GeoPoint, GeoPoint)>((ref, pair) async {
  final (from, to) = pair;
  const fallback = StraightLineRoutingService();
  try {
    return await ref
        .watch(routingServiceProvider)
        .route(from, to)
        .timeout(Env.routingTimeout + const Duration(seconds: 1));
  } catch (_) {
    return fallback.route(from, to);
  }
});
