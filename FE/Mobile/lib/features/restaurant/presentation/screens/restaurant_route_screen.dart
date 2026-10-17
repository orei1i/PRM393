// lib/features/restaurant/presentation/screens/restaurant_route_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../data/location_service.dart';
import '../../data/routing_service.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';
import '../maps_launcher.dart';
import '../widgets/vl_map.dart';
import 'location_picker_screen.dart';

/// Opens Google Maps (turn-by-turn) for [restaurant]; a snackbar when no
/// app can open it. The overflow action of the map screens.
Future<void> openInGoogleMaps(
    BuildContext context, WidgetRef ref, Restaurant restaurant) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await ref.read(urlOpenerProvider)(restaurant.hasLocation
        ? mapsDirectionsUri(restaurant)
        : mapsSearchUri(restaurant));
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Không mở được Google Maps trên máy này.')));
  }
}

/// App-bar overflow with "Mở bằng Google Maps".
class GoogleMapsMenu extends ConsumerWidget {
  const GoogleMapsMenu({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Thêm',
      onSelected: (_) => openInGoogleMaps(context, ref, restaurant),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'google_maps',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_new_rounded),
            title: Text('Mở bằng Google Maps'),
          ),
        ),
      ],
    );
  }
}

/// "Chỉ đường": the driving route from the user's location (or another
/// origin picked with "Đổi") to [restaurant], drawn in the app. OSRM when it
/// answers within 5 s; otherwise a straight line with the note "Không tải
/// được tuyến đường — hiển thị đường thẳng".
class RestaurantRouteScreen extends ConsumerStatefulWidget {
  const RestaurantRouteScreen({super.key, required this.restaurant});

  /// Must have a location (callers hide "Chỉ đường" otherwise).
  final Restaurant restaurant;

  static Route<void> route(Restaurant restaurant) => MaterialPageRoute<void>(
        builder: (_) => RestaurantRouteScreen(restaurant: restaurant),
      );

  @override
  ConsumerState<RestaurantRouteScreen> createState() =>
      _RestaurantRouteScreenState();
}

class _RestaurantRouteScreenState extends ConsumerState<RestaurantRouteScreen> {
  /// "Đổi": another origin for this screen only.
  UserLocation? _origin;

  Future<void> _changeOrigin(UserLocation current) async {
    final picked = await Navigator.of(context).push(LocationPickerScreen.route(
        initial: current, title: 'Chọn điểm xuất phát'));
    if (picked != null && mounted) setState(() => _origin = picked);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    final destination = r.location;
    final origin = _origin ?? ref.watch(userLocationProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉ đường'),
        actions: [GoogleMapsMenu(restaurant: r)],
      ),
      body: destination == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Quán chưa có vị trí trên bản đồ',
                    textAlign: TextAlign.center),
              ),
            )
          : origin == null
              ? const Center(child: CircularProgressIndicator())
              : _RouteBody(
                  restaurant: r,
                  destination: destination,
                  origin: origin,
                  onChangeOrigin: () => _changeOrigin(origin),
                ),
    );
  }
}

class _RouteBody extends ConsumerWidget {
  const _RouteBody({
    required this.restaurant,
    required this.destination,
    required this.origin,
    required this.onChangeOrigin,
  });

  final Restaurant restaurant;
  final GeoPoint destination;
  final UserLocation origin;
  final VoidCallback onChangeOrigin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(routeProvider((origin.point, destination)));
    final route = async.valueOrNull;
    final viaOsrm = route != null && !route.isStraightLine;
    final color = context.colors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: VLMap(
            key: ValueKey(origin.point),
            center: destination,
            fitPoints: [origin.point, destination],
            layers: [
              if (route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [for (final p in route.points) p.latLng],
                      strokeWidth: 5,
                      color: color,
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white,
                      pattern: route.isStraightLine
                          ? const StrokePattern.dotted()
                          : const StrokePattern.solid(),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  userLocationMarker(origin.point),
                  Marker(
                    point: destination.latLng,
                    width: RestaurantPin.size,
                    height: RestaurantPin.size,
                    child: RestaurantPin(
                        certified: restaurant.isVeganCertified,
                        selected: true,
                        label: restaurant.name),
                  ),
                ],
              ),
            ],
            extraAttributions: [
              if (viaOsrm)
                const TextSourceAttribution('Project OSRM',
                    prependCopyright: false),
            ],
          ),
        ),
        Material(
          color: context.colors.surface,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(restaurant.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  if (route == null)
                    Row(
                      children: [
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text('Đang tìm đường…',
                            style: context.textStyles.bodyMedium),
                      ],
                    )
                  else ...[
                    Text(
                      route.isStraightLine
                          ? '${formatDistance(route.distanceKm)} (đường chim bay)'
                          : '${formatDistance(route.distanceKm)} · '
                              '${formatTravelTime(route.durationSeconds ?? 0)} đi xe',
                      style: context.textStyles.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (route.isStraightLine)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18, color: context.vl.onCautionContainer),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Không tải được tuyến đường — hiển thị đường thẳng',
                                style: context.textStyles.bodySmall?.copyWith(
                                    color: context.vl.onCautionContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.trip_origin_rounded,
                          size: 18, color: context.vl.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Từ: ${origin.label}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodyMedium),
                      ),
                      TextButton(
                          onPressed: onChangeOrigin, child: const Text('Đổi')),
                    ],
                  ),
                  if (viaOsrm)
                    Text(
                      'Tuyến đường: OSRM · Dữ liệu © OpenStreetMap contributors. '
                      'Chỉ để tham khảo, không dẫn đường từng bước.',
                      style: context.textStyles.labelSmall
                          ?.copyWith(color: context.vl.muted),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen map of one restaurant (tap on the detail page's map): the
/// restaurant and the user, with "Chỉ đường".
class RestaurantMapScreen extends ConsumerWidget {
  const RestaurantMapScreen({super.key, required this.restaurant});

  final Restaurant restaurant;

  static Route<void> route(Restaurant restaurant) => MaterialPageRoute<void>(
        builder: (_) => RestaurantMapScreen(restaurant: restaurant),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = restaurant;
    final point = r.location;
    final user = ref.watch(userLocationProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [GoogleMapsMenu(restaurant: r)],
      ),
      floatingActionButton: point == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).push(RestaurantRouteScreen.route(r)),
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Chỉ đường'),
            ),
      body: point == null
          ? const Center(child: Text('Quán chưa có vị trí trên bản đồ'))
          : VLMap(
              center: point,
              zoom: 16,
              layers: [
                MarkerLayer(
                  markers: [
                    if (user != null) userLocationMarker(user.point),
                    Marker(
                      point: point.latLng,
                      width: RestaurantPin.size,
                      height: RestaurantPin.size,
                      child: RestaurantPin(
                          certified: r.isVeganCertified,
                          selected: true,
                          label: r.name),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
