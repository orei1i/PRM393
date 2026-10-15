// lib/features/restaurant/presentation/screens/restaurant_nearby_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/location_service.dart';
import '../../domain/entities/restaurant.dart';
import '../controllers/restaurant_controllers.dart';
import '../widgets/restaurant_tile.dart';
import 'restaurant_detail_screen.dart';
import 'submit_restaurant_screen.dart';

/// "Quán chay gần bạn": restaurants nearest first (or best rated), with a
/// certified-only filter and a name / address / dish search. Guests can
/// browse; suggesting a new place needs sign-in.
class RestaurantNearbyScreen extends ConsumerStatefulWidget {
  const RestaurantNearbyScreen({super.key, this.initialQuery});

  /// Pre-filled food/dish filter, e.g. from a search or a sponsored card.
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
    final location = ref.watch(userLocationProvider).valueOrNull;
    final busy = value != null && (value.searching || async.isRefreshing);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _suggest,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Gợi ý quán mới'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _list.refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              floating: true,
              snap: true,
              title: Text('Quán chay gần bạn'),
            ),
            if (location != null)
              SliverToBoxAdapter(child: _LocationNote(location: location)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _search,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm tên quán, địa chỉ, món…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Xoá',
                            onPressed: _clearQuery,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: context.colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: context.vl.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: context.vl.border),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _Filters(
                certifiedOnly: value?.certifiedOnly ?? false,
                sort: value?.sort ?? RestaurantSort.distance,
                onCertifiedOnly: (v) => _list.setCertifiedOnly(v),
                onSort: (s) => _list.setSort(s),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 2,
                child:
                    busy ? const LinearProgressIndicator(minHeight: 2) : null,
              ),
            ),
            ...async.when(
              data: _content,
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

  List<Widget> _content(RestaurantListState state) {
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
                message: state.query.isEmpty && !state.certifiedOnly
                    ? 'Bạn biết quán chay nào ngon? Gợi ý cho cộng đồng nhé.'
                    : 'Thử từ khoá khác, bỏ lọc chứng nhận, hoặc gợi ý quán bạn biết.',
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '${list.length} quán · ${state.sort == RestaurantSort.distance ? 'gần nhất trước' : 'đánh giá cao trước'}',
            style: context.textStyles.labelMedium
                ?.copyWith(color: context.vl.muted),
          ),
        ),
      ),
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

/// "Gần: Quận 1, TP.HCM (vị trí mô phỏng)". Wraps instead of clipping with
/// large text.
class _LocationNote extends StatelessWidget {
  const _LocationNote({required this.location});

  final UserLocation location;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location_rounded,
                  size: 16, color: context.colors.onSecondaryContainer),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Gần: ${location.label}',
                  style: context.textStyles.labelLarge
                      ?.copyWith(color: context.colors.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Tất cả" / "Đã chứng nhận thuần chay" + "Gần nhất" / "Đánh giá cao".
class _Filters extends StatelessWidget {
  const _Filters({
    required this.certifiedOnly,
    required this.sort,
    required this.onCertifiedOnly,
    required this.onSort,
  });

  final bool certifiedOnly;
  final RestaurantSort sort;
  final ValueChanged<bool> onCertifiedOnly;
  final ValueChanged<RestaurantSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tất cả'),
                selected: !certifiedOnly,
                onSelected: (_) => onCertifiedOnly(false),
              ),
              ChoiceChip(
                avatar: certifiedOnly
                    ? null
                    : Icon(Icons.verified_outlined,
                        size: 18, color: context.vl.success),
                label: const Text('Đã chứng nhận thuần chay'),
                selected: certifiedOnly,
                onSelected: (_) => onCertifiedOnly(true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<RestaurantSort>(
            segments: [
              for (final s in RestaurantSort.values)
                ButtonSegment(
                  value: s,
                  label: Text(s.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            selected: {sort},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            onSelectionChanged: (selection) => onSort(selection.first),
          ),
        ],
      ),
    );
  }
}
