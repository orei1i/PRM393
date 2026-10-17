// lib/features/restaurant/presentation/widgets/restaurant_map_view.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';
import '../controllers/restaurant_controllers.dart';
import 'restaurant_tile.dart';
import 'vl_map.dart';

/// Map mode of "Quán chay gần bạn": the user, one pin per restaurant with
/// coordinates (certified green, others grey, the sponsored one ringed), a
/// preview card for the tapped pin ("Xem quán", "Chỉ đường") and, after the
/// user pans, "Tìm trong khu vực này".
class RestaurantMapView extends StatefulWidget {
  const RestaurantMapView({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onDirections,
    required this.onSearchArea,
    this.sponsoredRestaurantId,
  });

  final RestaurantListState state;
  final ValueChanged<Restaurant> onOpen;
  final ValueChanged<Restaurant> onDirections;
  final ValueChanged<MapArea> onSearchArea;

  /// Drawn with the "Được tài trợ" ring.
  final String? sponsoredRestaurantId;

  @override
  State<RestaurantMapView> createState() => _RestaurantMapViewState();
}

class _RestaurantMapViewState extends State<RestaurantMapView> {
  /// Restaurants farther than this do not stretch the first view.
  static const _fitKm = 30.0;

  final _map = MapController();
  String? _selectedId;
  bool _moved = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (_moved || event is! MapEventWithMove) return;
    const programmatic = {
      MapEventSource.mapController,
      MapEventSource.fitCamera,
      MapEventSource.nonRotatedSizeChange,
      MapEventSource.interactiveFlagsChanged,
    };
    if (programmatic.contains(event.source)) return;
    setState(() => _moved = true);
  }

  void _searchHere() {
    final camera = _map.camera;
    final center = camera.center.geoPoint;
    final corner = camera.visibleBounds.northEast.geoPoint;
    // The circle that covers the visible map, within sane bounds.
    final radius = math.max(0.5, math.min(50.0, haversineKm(center, corner)));
    setState(() {
      _moved = false;
      _selectedId = null;
    });
    widget.onSearchArea(MapArea(center: center, radiusKm: radius));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final user = state.location.point;
    final placed = state.restaurants.where((r) => r.hasLocation).toList();
    Restaurant? selected;
    for (final r in placed) {
      if (r.id == _selectedId) selected = r;
    }
    final unplaced = state.restaurants.length - placed.length;
    return Stack(
      children: [
        Positioned.fill(
          child: VLMap(
            // A new location re-centres the map.
            key: ValueKey(user),
            controller: _map,
            center: user,
            zoom: 14,
            fitPoints: [
              user,
              // The nearest few around the user, so the first view is not
              // the whole country (a location in Hà Nội just shows Hà Nội).
              for (final r in placed
                  .where((r) => haversineKm(user, r.location!) <= _fitKm)
                  .take(6))
                r.location!,
            ],
            onMapEvent: _onMapEvent,
            onTap: () => setState(() => _selectedId = null),
            layers: [
              MarkerLayer(
                markers: [
                  userLocationMarker(user),
                  for (final r in placed)
                    Marker(
                      key: ValueKey('pin_${r.id}'),
                      point: r.location!.latLng,
                      width: RestaurantPin.size,
                      height: RestaurantPin.size,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedId = r.id),
                        child: RestaurantPin(
                          certified: r.isVeganCertified,
                          sponsored: r.id == widget.sponsoredRestaurantId,
                          selected: r.id == _selectedId,
                          label: r.name,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_moved)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _searchHere,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tìm trong khu vực này'),
              ),
            ),
          ),
        if (placed.isEmpty)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _Note(
              text: state.restaurants.isEmpty
                  ? 'Không có quán nào khớp bộ lọc.'
                  : 'Các quán này chưa có vị trí trên bản đồ. Xem ở chế độ danh sách.',
            ),
          )
        else if (unplaced > 0 && !_moved && selected == null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _Note(
                text:
                    '$unplaced quán chưa có vị trí trên bản đồ — xem ở chế độ danh sách.'),
          ),
        if (selected != null)
          Positioned(
            left: 12,
            right: 12,
            // Above the "Gợi ý quán mới" button.
            bottom: 88 + MediaQuery.paddingOf(context).bottom,
            child: _PreviewCard(
              restaurant: selected,
              sponsored: selected.id == widget.sponsoredRestaurantId,
              onOpen: () => widget.onOpen(selected!),
              onDirections: () => widget.onDirections(selected!),
              onClose: () => setState(() => _selectedId = null),
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text, style: context.textStyles.bodySmall),
      ),
    );
  }
}

/// The tapped pin's card: name, address, facts, "Xem quán" / "Chỉ đường".
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.restaurant,
    required this.sponsored,
    required this.onOpen,
    required this.onDirections,
    required this.onClose,
  });

  final Restaurant restaurant;
  final bool sponsored;
  final VoidCallback onOpen;
  final VoidCallback onDirections;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Material(
      color: context.colors.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: RestaurantThumb(seed: r.id, size: 52),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sponsored)
                        Text('Được tài trợ',
                            style: context.textStyles.labelSmall
                                ?.copyWith(color: context.vl.muted)),
                      Text(r.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(r.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.vl.muted)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          CertificationTag(certified: r.isVeganCertified),
                          DistanceLabel(restaurant: r),
                          RatingLabel(
                              average: r.averageRating, count: r.reviewCount),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Xem quán'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDirections,
                      icon: const Icon(Icons.directions_outlined),
                      label: const Text('Chỉ đường'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
