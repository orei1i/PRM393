// lib/features/restaurant/presentation/screens/location_picker_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../data/geocoding_service.dart';
import '../../data/location_service.dart';
import '../../domain/geo.dart';
import '../widgets/vl_map.dart';

/// Opens "Chọn vị trí" and, when the user picks a place, makes it the
/// location every "gần bạn" list measures from. Returns the new location.
Future<UserLocation?> pickUserLocation(BuildContext context, WidgetRef ref,
    {bool startOnMap = false}) async {
  final current = ref.read(userLocationProvider).valueOrNull;
  final picked = await Navigator.of(context).push(
      LocationPickerScreen.route(initial: current, startOnMap: startOnMap));
  if (picked == null) return null;
  await ref.read(userLocationProvider.notifier).setLocation(picked);
  return picked;
}

/// "Chọn vị trí": address search ("Tìm địa chỉ") with "Dùng vị trí hiện tại
/// (mô phỏng)" and "Vị trí gần đây", or "Chọn trên bản đồ" (a fixed centre
/// pin; the address under it updates when the map stops). Pops the chosen
/// [UserLocation]; the caller decides what to do with it.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initial,
    this.startOnMap = false,
    this.title = 'Chọn vị trí',
  });

  /// Where the map starts (defaults to the user's location).
  final UserLocation? initial;
  final bool startOnMap;
  final String title;

  static Route<UserLocation> route({
    UserLocation? initial,
    bool startOnMap = false,
    String title = 'Chọn vị trí',
  }) =>
      MaterialPageRoute<UserLocation>(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
            initial: initial, startOnMap: startOnMap, title: title),
      );

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.startOnMap ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Đóng',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
          title: Text(widget.title),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tìm địa chỉ'),
              Tab(text: 'Chọn trên bản đồ'),
            ],
          ),
        ),
        body: TabBarView(
          // Horizontal drags belong to the map.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const _SearchTab(),
            _MapTab(initial: widget.initial),
          ],
        ),
      ),
    );
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final _query = TextEditingController();
  Timer? _debounce;
  Future<List<GeoPlace>>? _results;
  bool _locating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
    setState(() {}); // clear button
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isEmpty || !mounted) return;
    final results = ref.read(geocodingServiceProvider).search(q);
    setState(() {
      _results = results;
    });
  }

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      final here = await ref.read(locationServiceProvider).currentLocation();
      if (mounted) Navigator.of(context).pop(here);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentLocationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            onChanged: _onChanged,
            onSubmitted: (_) {
              _debounce?.cancel();
              _search();
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tìm địa chỉ, phường, quận…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xoá',
                      onPressed: () {
                        _query.clear();
                        _onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        Expanded(
          child: _results == null
              ? ListView(
                  children: [
                    ListTile(
                      leading: _locating
                          ? const SizedBox.square(
                              dimension: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Icon(Icons.my_location_rounded,
                              color: context.colors.primary),
                      title: const Text('Dùng vị trí hiện tại (mô phỏng)'),
                      subtitle: const Text(
                          'Ứng dụng chưa đọc GPS: dùng điểm mô phỏng ở Quận 1, TP.HCM.'),
                      onTap: _locating ? null : _useCurrent,
                    ),
                    if (recent.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text('Vị trí gần đây',
                            style: context.textStyles.titleSmall),
                      ),
                      for (final l in recent)
                        ListTile(
                          leading: const Icon(Icons.history_rounded),
                          title: Text(l.label),
                          subtitle: l.address == null ? null : Text(l.address!),
                          onTap: () => Navigator.of(context).pop(l),
                        ),
                    ],
                  ],
                )
              : FutureBuilder<List<GeoPlace>>(
                  future: _results,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _Message(
                        icon: Icons.error_outline_rounded,
                        text: describeError(snap.error!),
                        actionLabel: 'Thử lại',
                        onAction: _search,
                      );
                    }
                    final places = snap.data ?? const [];
                    if (places.isEmpty) {
                      return _Message(
                        icon: Icons.location_searching_rounded,
                        text: 'Không tìm thấy địa chỉ phù hợp. Thử tên đường, '
                            'phường hoặc quận, hoặc chọn trên bản đồ.',
                        actionLabel: 'Chọn trên bản đồ',
                        onAction: () =>
                            DefaultTabController.of(context).animateTo(1),
                      );
                    }
                    return ListView.separated(
                      itemCount: places.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = places[i];
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(p.name),
                          subtitle: Text(p.address),
                          onTap: () => Navigator.of(context)
                              .pop(p.toUserLocation(UserLocationSource.search)),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.vl.muted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _MapTab extends ConsumerStatefulWidget {
  const _MapTab({this.initial});

  final UserLocation? initial;

  @override
  ConsumerState<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<_MapTab>
    with AutomaticKeepAliveClientMixin {
  final _map = MapController();
  Timer? _idle;
  late GeoPoint _center =
      widget.initial?.point ?? MockLocationService.location.point;
  GeoPlace? _place;
  bool _resolving = true;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _idle?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    // Only the user's moves: not the first layout or programmatic ones.
    if (event is! MapEventWithMove ||
        event.source == MapEventSource.nonRotatedSizeChange ||
        event.source == MapEventSource.mapController ||
        event.source == MapEventSource.fitCamera) {
      return;
    }
    _center = event.camera.center.geoPoint;
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 400), _resolve);
    if (!_resolving) setState(() => _resolving = true);
  }

  /// Reverse geocodes the point under the pin.
  Future<void> _resolve() async {
    final id = ++_request;
    final point = _center;
    GeoPlace? place;
    try {
      place = await ref.read(geocodingServiceProvider).reverse(point);
    } catch (_) {
      place = null; // the coordinates are still usable
    }
    if (!mounted || id != _request) return;
    setState(() {
      _place = place;
      _resolving = false;
    });
  }

  void _confirm() {
    // While the address is still loading, the coordinates speak for it.
    final place = _resolving ? null : _place;
    Navigator.of(context).pop(UserLocation(
      point: _center,
      label: place?.name ?? 'Vị trí đã chọn',
      source: UserLocationSource.map,
      address: place?.address ?? formatCoordinates(_center),
      city: place?.city,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final place = _place;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: VLMap(
            controller: _map,
            center: _center,
            zoom: 16,
            onMapEvent: _onMapEvent,
            overlays: const [CenterPin()],
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
                  Text('Kéo bản đồ để đặt ghim vào đúng vị trí',
                      style: context.textStyles.labelMedium
                          ?.copyWith(color: context.vl.muted)),
                  const SizedBox(height: 6),
                  Text(
                    _resolving
                        ? 'Đang xác định địa chỉ…'
                        : place?.name ?? 'Vị trí đã chọn',
                    style: context.textStyles.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (!_resolving)
                    Text(
                      place?.address ?? formatCoordinates(_center),
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Dùng vị trí này'),
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
