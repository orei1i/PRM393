// lib/features/restaurant/presentation/widgets/vl_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/geo.dart';
import '../maps_launcher.dart';

/// Draws OSM tiles (`MAP_TILES=on`, the default) or a flat background with
/// markers only (`MAP_TILES=off`, and always under `flutter test`, so widget
/// tests never fetch tiles).
final mapTilesEnabledProvider =
    Provider<bool>((ref) => Env.mapTilesEnabled && !Env.isFlutterTest);

/// The tile source; `null` = flutter_map's network provider (which caches
/// tiles as the servers allow). Tests that turn tiles on override it with an
/// offline fake.
final mapTileProviderProvider = Provider<TileProvider?>((ref) => null);

extension GeoPointLatLng on GeoPoint {
  LatLng get latLng => LatLng(latitude, longitude);
}

extension LatLngGeoPoint on LatLng {
  GeoPoint get geoPoint => GeoPoint(latitude, longitude);
}

/// The app's map: tiles (or the flat placeholder), the caller's [layers]
/// (routes, markers), static [overlays] and the OSM attribution, which the
/// tile policy requires whenever tiles are drawn.
class VLMap extends ConsumerWidget {
  const VLMap({
    super.key,
    required this.center,
    this.zoom = 14,
    this.fitPoints = const [],
    this.controller,
    this.interactive = true,
    this.layers = const [],
    this.overlays = const [],
    this.onTap,
    this.onMapEvent,
    this.extraAttributions = const [],
  });

  final GeoPoint center;
  final double zoom;

  /// When it has two or more distinct points, the first frame fits them all.
  final List<GeoPoint> fitPoints;
  final MapController? controller;

  /// `false` for previews (no pan / zoom; [onTap] still fires).
  final bool interactive;
  final List<Widget> layers;
  final List<Widget> overlays;
  final VoidCallback? onTap;
  final void Function(MapEvent event)? onMapEvent;

  /// More sources next to "OpenStreetMap contributors" (e.g. OSRM).
  final List<SourceAttribution> extraAttributions;

  static const _osmCopyright = 'https://www.openstreetmap.org/copyright';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(mapTilesEnabledProvider);
    final tileProvider = ref.watch(mapTileProviderProvider);
    final distinct = fitPoints.toSet();
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center.latLng,
        initialZoom: zoom,
        initialCameraFit: distinct.length >= 2
            ? CameraFit.coordinates(
                coordinates: [for (final p in distinct) p.latLng],
                padding: const EdgeInsets.fromLTRB(48, 48, 48, 64),
                maxZoom: 16,
              )
            : null,
        minZoom: 4,
        maxZoom: 19,
        backgroundColor: tiles
            ? const Color(0xFFE8E4DC)
            : context.colors.surfaceContainerHigh,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onTap: onTap == null ? null : (_, __) => onTap!(),
        onMapEvent: onMapEvent,
      ),
      children: [
        if (tiles)
          TileLayer(
            urlTemplate: Env.mapTileUrl,
            userAgentPackageName: Env.mapUserAgentPackageName,
            maxZoom: 19,
            tileProvider: tileProvider,
          ),
        ...layers,
        ...overlays,
        if (!tiles) const _TilesOffNote(),
        if (tiles)
          RichAttributionWidget(
            // Bottom-left: floating buttons sit bottom-right on map screens
            // and must never hide the credit.
            alignment: AttributionAlignment.bottomLeft,
            showFlutterMapAttribution: false,
            popupInitialDisplayDuration: const Duration(seconds: 5),
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () =>
                    ref.read(urlOpenerProvider)(Uri.parse(_osmCopyright)),
              ),
              ...extraAttributions,
            ],
          ),
      ],
    );
  }
}

/// Bottom-left hint while tiles are off.
class _TilesOffNote extends StatelessWidget {
  const _TilesOffNote();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              'Bản đồ nền đang tắt',
              style: context.textStyles.labelSmall
                  ?.copyWith(color: context.vl.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// "You are here": a blue dot with a white ring.
Marker userLocationMarker(GeoPoint point) => Marker(
      point: point.latLng,
      width: 26,
      height: 26,
      child: const _UserDot(),
    );

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vị trí của bạn',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// A storefront pin: green when certified, grey otherwise, ringed in amber
/// when sponsored, larger when selected.
class RestaurantPin extends StatelessWidget {
  const RestaurantPin({
    super.key,
    required this.certified,
    this.sponsored = false,
    this.selected = false,
    this.label,
  });

  final bool certified;
  final bool sponsored;
  final bool selected;

  /// Semantics label (the restaurant's name).
  final String? label;

  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    final fill = certified ? context.vl.success : const Color(0xFF6B7280);
    final ring = sponsored ? const Color(0xFFF59E0B) : Colors.white;
    final dimension = selected ? size : size - 6;
    return Semantics(
      label: label,
      button: true,
      child: Center(
        child: Container(
          width: dimension,
          height: dimension,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: sponsored ? 4 : 2.5),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 4),
            ],
          ),
          child: Icon(
            sponsored ? Icons.campaign_rounded : Icons.storefront_rounded,
            size: dimension * 0.5,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// The fixed pin in the middle of "Chọn trên bản đồ" (the map moves under
/// it). Its tip sits on the map centre.
class CenterPin extends StatelessWidget {
  const CenterPin({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -22),
          child: Icon(Icons.location_on_rounded,
              size: 48, color: context.colors.error),
        ),
      ),
    );
  }
}
