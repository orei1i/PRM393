// lib/features/restaurant/presentation/screens/restaurant_nearby_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../ads/data/models/ad_feed_item.dart';
import '../../../ads/presentation/controllers/ads_controller.dart';
import '../../../ads/presentation/widgets/sponsored_restaurant_row.dart';
import '../../domain/entities/restaurant.dart';
import '../controllers/restaurant_controllers.dart';
import '../widgets/location_chip.dart';
import '../widgets/restaurant_filter_sheet.dart';
import '../widgets/restaurant_map_view.dart';
import '../widgets/restaurant_tile.dart';
import 'restaurant_detail_screen.dart';
import 'restaurant_route_screen.dart';
import 'submit_restaurant_screen.dart';

/// "Quán chay gần bạn": a compact header (location chip → "Chọn vị trí",
/// search, "Bộ lọc" with a count badge, removable filter chips), then the
/// list (one "Được tài trợ" row first) or the map ("Xem bản đồ" /
/// "Xem danh sách"). Guests can browse; suggesting a place needs sign-in.
class RestaurantNearbyScreen extends ConsumerStatefulWidget {
  const RestaurantNearbyScreen({super.key, this.initialQuery});

  /// Pre-filled food/dish filter, e.g. from a search.
  final String? initialQuery;

  static Route<void> route({String? initialQuery}) => MaterialPageRoute<void>(
        builder: (_) => RestaurantNearbyScreen(initialQuery: initialQuery),
      );

  @override
  ConsumerState<RestaurantNearbyScreen> createState() =>
      _RestaurantNearbyScreenState();
}

class _RestaurantNearbyScreenState
    extends ConsumerState<RestaurantNearbyScreen> {
  late final _search = TextEditingController(text: widget.initialQuery?.trim());
  Timer? _debounce;
  bool _mapMode = false;

  /// Ads already counted on this screen (one impression per display).
  final _seenAds = <String>{};

  /// Family key of this screen's list.
  String get _key => widget.initialQuery?.trim() ?? '';

  RestaurantListController get _list =>
      ref.read(restaurantListProvider(_key).notifier);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _list.search(value));
    setState(() {}); // toggles the clear button
  }

  void _clearQuery() {
    _search.clear();
    _debounce?.cancel();
    _list.search('');
    setState(() {});
  }

  void _open(Restaurant r) => Navigator.of(context)
      .push(RestaurantDetailScreen.route(r.id, name: r.name));

  void _directions(Restaurant r) =>
      Navigator.of(context).push(RestaurantRouteScreen.route(r));

  void _adShown(AdFeedItemDto ad) {
    if (_seenAds.add(ad.id)) ref.read(adEventsProvider).impression(ad.id);
  }

  Future<void> _openFilters(RestaurantFilters current) async {
    final next = await showRestaurantFilterSheet(context, current);
    if (next != null && mounted) _list.applyFilters(next);
  }

  Future<void> _suggest() async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để gợi ý quán chay mới cho cộng đồng.')) {
      return;
    }
    if (!mounted) return;
    // The form replaces itself with the new restaurant's detail and
    // refreshes this list.
    await Navigator.of(context).push(SubmitRestaurantScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(restaurantListProvider(_key));
    final value = async.valueOrNull;
    final busy = value != null && (value.searching || async.isRefreshing);
    final ads = ref.watch(nearbyAdsProvider).valueOrNull ?? const [];
    final ad = ads.isEmpty ? null : ads.first;

    final header = _Header(
      search: _search,
      onQueryChanged: _onQueryChanged,
      onClearQuery: _clearQuery,
      filters: value?.filters ?? RestaurantFilters.defaults,
      area: value?.area,
      onOpenFilters: () =>
          _openFilters(value?.filters ?? RestaurantFilters.defaults),
      onFilters: (f) => _list.applyFilters(f),
      onClearArea: () => _list.clearArea(),
      busy: busy,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quán chay gần bạn'),
        actions: [
          IconButton(
            tooltip: _mapMode ? 'Xem danh sách' : 'Xem bản đồ',
            onPressed: () => setState(() => _mapMode = !_mapMode),
            icon: Icon(_mapMode ? Icons.view_list_rounded : Icons.map_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _suggest,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Gợi ý quán mới'),
      ),
      body: _mapMode
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(
                  child: async.when(
                    skipLoadingOnReload: true,
                    data: (state) => RestaurantMapView(
                      state: state,
                      sponsoredRestaurantId: ad?.restaurantId,
                      onOpen: _open,
                      onDirections: _directions,
                      onSearchArea: (area) => _list.searchArea(area),
                    ),
                    error: (error, _) => Center(
                      child: SingleChildScrollView(
                        child: ErrorStateView(
                            error: error, onRetry: () => _list.refresh()),
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: () => _list.refresh(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: header),
                  ...async.when(
                    data: (state) => _content(state, ad),
                    error: (error, _) => [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 88),
                          child: Center(
                            child: ErrorStateView(
                                error: error, onRetry: () => _list.refresh()),
                          ),
                        ),
                      ),
                    ],
                    loading: () => [
                      const SliverToBoxAdapter(child: RestaurantListSkeleton()),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _content(RestaurantListState state, AdFeedItemDto? ad) {
    final sponsored = ad == null
        ? null
        : SponsoredRestaurantRow(
            key: ValueKey('ad_${ad.id}'),
            ad: ad,
            onShown: () => _adShown(ad),
          );
    if (state.restaurants.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            // Keeps the action clear of the "Gợi ý quán mới" button.
            padding: const EdgeInsets.only(bottom: 88),
            child: Center(
              child: EmptyStateView(
                icon: Icons.storefront_outlined,
                title: 'Chưa có quán nào khớp',
                message: state.query.isEmpty &&
                        state.filters == RestaurantFilters.defaults &&
                        state.area == null
                    ? 'Bạn biết quán chay nào ngon? Gợi ý cho cộng đồng nhé.'
                    : 'Thử từ khoá khác, bỏ bớt bộ lọc, đổi vị trí, hoặc gợi ý quán bạn biết.',
                actionLabel: 'Gợi ý quán mới',
                onAction: _suggest,
              ),
            ),
          ),
        ),
      ];
    }
    final list = state.restaurants;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            state.summary,
            style: context.textStyles.labelMedium
                ?.copyWith(color: context.vl.muted),
          ),
        ),
      ),
      if (sponsored != null) ...[
        SliverToBoxAdapter(child: sponsored),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
      ],
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (i > 0) const RestaurantTileDivider(),
              RestaurantTile(
                key: ValueKey(list[i].id),
                restaurant: list[i],
                onTap: () => _open(list[i]),
              ),
            ],
          ),
          childCount: list.length,
        ),
      ),
      // Clear the extended FAB and the gesture bar.
      SliverToBoxAdapter(
        child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom),
      ),
    ];
  }
}

/// Location chip; search + "Bộ lọc"; removable chips for active filters.
class _Header extends StatelessWidget {
  const _Header({
    required this.search,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.filters,
    required this.area,
    required this.onOpenFilters,
    required this.onFilters,
    required this.onClearArea,
    required this.busy,
  });

  final TextEditingController search;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final RestaurantFilters filters;
  final MapArea? area;
  final VoidCallback onOpenFilters;
  final ValueChanged<RestaurantFilters> onFilters;
  final VoidCallback onClearArea;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final count = filters.activeCount;
    final chips = <Widget>[
      if (area != null)
        InputChip(
          avatar: const Icon(Icons.crop_free_rounded, size: 18),
          label: const Text('Khu vực bản đồ'),
          onDeleted: onClearArea,
          deleteButtonTooltipMessage: 'Bỏ lọc khu vực',
        ),
      if (filters.certifiedOnly)
        InputChip(
          avatar:
              Icon(Icons.verified_rounded, size: 18, color: context.vl.success),
          label: const Text('Đã chứng nhận'),
          onDeleted: () => onFilters(filters.copyWith(certifiedOnly: false)),
          deleteButtonTooltipMessage: 'Bỏ lọc chứng nhận',
        ),
      if (filters.sort != RestaurantSort.distance)
        InputChip(
          label: Text(filters.sort.label),
          onDeleted: () =>
              onFilters(filters.copyWith(sort: RestaurantSort.distance)),
          deleteButtonTooltipMessage: 'Sắp xếp gần nhất',
        ),
      if (filters.radiusKm != null)
        InputChip(
          label: Text('Trong ${radiusLabel(filters.radiusKm)}'),
          onDeleted: () => onFilters(filters.copyWith(radiusKm: () => null)),
          deleteButtonTooltipMessage: 'Bỏ giới hạn bán kính',
        ),
    ];
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: context.vl.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: LocationChip()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm tên quán, địa chỉ, món…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Xoá',
                            onPressed: onClearQuery,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: context.colors.surface,
                    border: border,
                    enabledBorder: border,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: onOpenFilters,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Bộ lọc'),
                ),
              ),
            ],
          ),
        ),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 4, children: chips),
          ),
        const SizedBox(height: 6),
        SizedBox(
          height: 2,
          child: busy ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
      ],
    );
  }
}
