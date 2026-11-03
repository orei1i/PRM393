// lib/features/restaurant/presentation/screens/location_picker_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../data/geocoding_service.dart';
import '../../data/location_service.dart';
import '../../domain/geo.dart';
import '../widgets/vl_map.dart';

/// Opens "Chọn vị trí" and, when the user picks a place, makes it the
/// location every "gần bạn" list measures from. Returns the new location.
Future<UserLocation?> pickUserLocation(
    BuildContext context, WidgetRef ref) async {
  final current = ref.read(userLocationProvider).valueOrNull;
  final picked = await Navigator.of(context)
      .push(LocationPickerScreen.route(initial: current));
  if (picked == null) return null;
  await ref.read(userLocationProvider.notifier).setLocation(picked);
  return picked;
}

/// "Chọn vị trí", one screen: the address search with "Dùng vị trí hiện tại
/// (mô phỏng)" and "Vị trí gần đây", and a floating "Tìm trên bản đồ" at the
/// bottom-left that turns the screen into the map (a fixed centre pin: drag the
/// map or tap a point; the address under it updates when the map stops). The
/// back arrow, the system back and the search box on the map return to the
/// search with what was typed. Failed tiles only get a note: a point still
/// confirms with its coordinates. Pops the chosen [UserLocation]; the caller
/// decides what to do with it.
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
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  Timer? _debounce;
  Future<List<GeoPlace>>? _results;
  bool _locating = false;

  late bool _onMap = widget.startOnMap;

  /// Where the pin was, so going back to the map finds it again.
  late GeoPoint _mapCenter =
      widget.initial?.point ?? MockLocationService.location.point;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _queryFocus.dispose();
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

  void _showMap() {
    _queryFocus.unfocus();
    setState(() => _onMap = true);
  }

  void _showSearch({bool focus = false}) {
    setState(() => _onMap = false);
    if (focus) _queryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_onMap,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _onMap
              ? IconButton(
                  tooltip: 'Quay lại tìm địa chỉ',
                  onPressed: _showSearch,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
          title: Text(widget.title),
          actions: [
            if (_onMap)
              IconButton(
                tooltip: 'Đóng',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: _onMap
            ? null
            : FloatingActionButton.extended(
                onPressed: _showMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Tìm trên bản đồ'),
              ),
        body: _onMap
            ? _MapPane(
                center: _mapCenter,
                onMoved: (point) => _mapCenter = point,
                onSearch: () => _showSearch(focus: true),
              )
            : _searchPane(context),
      ),
    );
  }

  Widget _searchPane(BuildContext context) {
    final recent = ref.watch(recentLocationsProvider);
    // Room for the floating button under the last row.
    final bottom = 88 + MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            focusNode: _queryFocus,
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
        // Module `geocoding` stays mock: this BE has no geocoder configured.
        if (DemoDataBanner.visibleFor(BackendModule.geocoding))
          const DemoDataBanner(module: BackendModule.geocoding),
        Expanded(
          child: _results == null
              ? ListView(
                  padding: EdgeInsets.only(bottom: bottom),
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
                      return const _Message(
                        icon: Icons.location_searching_rounded,
                        text: 'Không tìm thấy địa chỉ phù hợp. Thử tên đường, '
                            'phường hoặc quận, hoặc tìm trên bản đồ.',
                      );
                    }
                    return ListView.separated(
                      padding: EdgeInsets.only(bottom: bottom),
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
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 40, color: context.vl.muted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (label != null) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(onPressed: onAction, child: Text(label)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The map side of the screen: drag or tap to move the pin, "Dùng vị trí này"
/// to confirm, the box at the top to go back to searching.
class _MapPane extends ConsumerStatefulWidget {
  const _MapPane({
    required this.center,
    required this.onMoved,
    required this.onSearch,
  });

  final GeoPoint center;
  final ValueChanged<GeoPoint> onMoved;
  final VoidCallback onSearch;

  @override
  ConsumerState<_MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends ConsumerState<_MapPane> {
  final _map = MapController();
  Timer? _idle;
  late GeoPoint _center = widget.center;
  GeoPlace? _place;
  bool _resolving = true;
  bool _tilesFailed = false;
  int _request = 0;

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

  void _moved(GeoPoint point) {
    _center = point;
    widget.onMoved(point);
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 400), _resolve);
    if (!_resolving) setState(() => _resolving = true);
  }

  void _onMapEvent(MapEvent event) {
    // Only the user's moves: not the first layout or programmatic ones.
    if (event is! MapEventWithMove ||
        event.source == MapEventSource.nonRotatedSizeChange ||
        event.source == MapEventSource.mapController ||
        event.source == MapEventSource.fitCamera) {
      return;
    }
    _moved(event.camera.center.geoPoint);
  }

  /// A tap brings that point under the pin.
  void _onTapPoint(GeoPoint point) {
    _map.move(point.latLng, _map.camera.zoom);
    _moved(point);
  }

  void _onTileError() {
    if (mounted && !_tilesFailed) setState(() => _tilesFailed = true);
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
    final place = _place;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              VLMap(
                controller: _map,
                center: widget.center,
                zoom: 16,
                onMapEvent: _onMapEvent,
                onTapPoint: _onTapPoint,
                onTileError: _onTileError,
                overlays: const [CenterPin()],
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SearchBox(onTap: widget.onSearch),
                    if (_tilesFailed) ...[
                      const SizedBox(height: 8),
                      const _TilesFailedNote(),
                    ],
                  ],
                ),
              ),
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
                  Text('Kéo bản đồ hoặc chạm vào một điểm để đặt ghim',
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

/// Looks like the search field; a tap goes back to it.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Quay lại tìm địa chỉ',
      excludeSemantics: true,
      child: Material(
        color: context.colors.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: context.vl.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tìm địa chỉ, phường, quận…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodyLarge
                          ?.copyWith(color: context.vl.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiles didn't load (no internet on the emulator): not a dead end.
class _TilesFailedNote extends StatelessWidget {
  const _TilesFailedNote();

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: vl.cautionContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: vl.onCautionContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Chưa tải được bản đồ nền. Bạn vẫn chọn được điểm (có toạ độ) '
              'hoặc tìm địa chỉ ở ô phía trên.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: vl.onCautionContainer),
            ),
          ),
        ],
      ),
    );
  }
}
