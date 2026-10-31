// lib/core/config/env.dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time configuration, overridable with `--dart-define`:
///
/// ```bash
/// flutter run \
///   --dart-define=USE_MOCK_DATA=false \
///   --dart-define=API_BASE_URL=https://api.veganlife.vn/api/v1 \
///   --dart-define=BACKEND_MOCK_MODULES=community,scanner \
///   --dart-define=MAP_TILES=off \
///   --dart-define=OSRM_BASE_URL=http://127.0.0.1:9
/// ```
abstract final class Env {
  /// `true` → every feature uses its Mock repository (no backend needed).
  /// `false` → hybrid, module by module: ask `BackendModules`, not this flag.
  static const bool useMockData =
      bool.fromEnvironment('USE_MOCK_DATA', defaultValue: true);

  /// ASP.NET Core API root. 10.0.2.2 is the host machine from the Android emulator.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5001/api/v1',
  );

  /// The server root, for what the BE serves outside the API prefix (uploads,
  /// the vision route): [apiBaseUrl] without a trailing `/api/v1`.
  static String get apiOrigin => apiOriginOf(apiBaseUrl);

  static String apiOriginOf(String baseUrl) =>
      baseUrl.replaceFirst(RegExp(r'(/api/v1)?/*$'), '');

  /// Free AI questions for guests (the server is the source of truth).
  static const int guestTrialLimit =
      int.fromEnvironment('GUEST_TRIAL_LIMIT', defaultValue: 3);

  /// Mock-only switch for the scanner: `normal` | `empty` | `error`.
  static const String mockScanScenario =
      String.fromEnvironment('MOCK_SCAN_SCENARIO', defaultValue: 'normal');

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 45);

  // ------------------------------------------------------------------ maps

  /// Raster tiles for the in-app maps. The default is the public
  /// OpenStreetMap server: fine for development and demos, but its usage
  /// policy (https://operations.osmfoundation.org/policies/tiles) does not
  /// allow heavy production traffic, so production points this at a paid or
  /// self-hosted provider. No `{s}` subdomains, no bulk download or prefetch.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// `on` (default) draws [mapTileUrl] tiles; `off` keeps the maps as a flat
  /// background with markers and routes (no network). Widget tests always
  /// run with tiles off (see [isFlutterTest]).
  static const String mapTiles =
      String.fromEnvironment('MAP_TILES', defaultValue: 'on');

  static bool get mapTilesEnabled => mapTiles.trim().toLowerCase() != 'off';

  /// Sent as the tile `User-Agent` (`flutter_map (<package>)`), as the OSM
  /// tile policy requires. Same as the Android `applicationId`.
  static const String mapUserAgentPackageName = 'vn.veganlife.veganlife_mobile';

  /// In-app directions (driving profile). The default is the public OSRM
  /// demo server: no SLA, about 1 request per second, so the app asks once
  /// per route screen, caches the answer and falls back to a straight line.
  /// Production should use a self-hosted OSRM (or VietMap) behind the BE.
  /// An empty value disables routing (straight line only).
  static const String osrmBaseUrl = String.fromEnvironment(
    'OSRM_BASE_URL',
    defaultValue: 'https://router.project-osrm.org',
  );

  /// How long one OSRM request may take before the straight-line fallback.
  static const Duration routingTimeout = Duration(seconds: 5);

  /// `true` inside `flutter test`: maps skip tiles and routing skips OSRM,
  /// so widget tests never touch the network.
  static final bool isFlutterTest = () {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }();
}
