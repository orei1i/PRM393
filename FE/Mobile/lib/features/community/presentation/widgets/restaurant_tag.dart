// lib/features/community/presentation/widgets/restaurant_tag.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../restaurant/data/location_service.dart';
import '../../../restaurant/data/restaurant_api_service.dart';
import '../../../restaurant/domain/entities/restaurant.dart';
import '../../../restaurant/domain/geo.dart';
import '../../../restaurant/presentation/screens/restaurant_detail_screen.dart';
import '../../domain/entities/post.dart';

/// Compact chip under a post's body: "🏪 Quán Chay An Lạc · Q.1 · ✓".
/// Opens the restaurant detail; in the composer [onRemove] adds a ✕.
class RestaurantTagChip extends StatelessWidget {
  const RestaurantTagChip(
      {super.key, required this.restaurant, this.onTap, this.onRemove});

  final TaggedRestaurant restaurant;

  /// Defaults to opening the restaurant detail.
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  static void open(BuildContext context, TaggedRestaurant restaurant) =>
      Navigator.of(context).push(
          RestaurantDetailScreen.route(restaurant.id, name: restaurant.name));

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return Semantics(
      button: true,
      label: 'Gắn quán: ${r.name}',
      excludeSemantics: true,
      child: Material(
        color: context.colors.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? () => open(context, r),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 6, onRemove == null ? 12 : 4, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined,
                    size: 16, color: context.colors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: r.name,
                        style: context.textStyles.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (r.district != null && r.district!.isNotEmpty)
                        TextSpan(text: ' · ${r.district}', style: muted),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (r.isCertified) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Đã chứng nhận thuần chay',
                    child: Icon(Icons.verified_rounded,
                        size: 15, color: context.vl.success),
                  ),
                ],
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Bỏ gắn quán',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 28),
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Gắn quán": search plus the nearest restaurants. Pops the chosen
/// [TaggedRestaurant].
Future<TaggedRestaurant?> pickTaggedRestaurant(BuildContext context) =>
    showModalBottomSheet<TaggedRestaurant>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const RestaurantTagPickerSheet(),
    );

class RestaurantTagPickerSheet extends ConsumerStatefulWidget {
  const RestaurantTagPickerSheet({super.key});

  @override
  ConsumerState<RestaurantTagPickerSheet> createState() =>
      _RestaurantTagPickerSheetState();
}

class _RestaurantTagPickerSheetState
    extends ConsumerState<RestaurantTagPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  late Future<List<Restaurant>> _results = _load('');

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<List<Restaurant>> _load(String q) async {
    final location = await ref.read(userLocationProvider.future);
    final list = await ref.read(restaurantApiProvider).listRestaurants(
        near: location.point,
        query: q.trim().isEmpty ? null : q.trim(),
        limit: 20);
    return [for (final r in list) r.toEntity()];
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _results = _load(value));
    });
  }

  static String _distance(double km) => formatDistance(km);

  void _pick(Restaurant r) => Navigator.of(context).pop(TaggedRestaurant(
        id: r.id,
        name: r.name,
        district: TaggedRestaurant.districtOf(r.address),
        isCertified: r.isVeganCertified,
      ));

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Gắn quán', style: context.textStyles.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Bài viết sẽ hiện “— tại {quán}” và mở được trang của quán.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _query,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Tìm quán theo tên, địa chỉ…',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Restaurant>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(describeError(snapshot.error!),
                                textAlign: TextAlign.center),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _results = _load(_query.text)),
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final list = snapshot.data ?? const <Restaurant>[];
                  if (list.isEmpty) {
                    return Center(
                      child: Text('Không tìm thấy quán nào',
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: context.vl.muted)),
                    );
                  }
                  return ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                        bottom: 16 + MediaQuery.paddingOf(context).bottom),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                          child: Text(
                              _query.text.trim().isEmpty
                                  ? 'Quán gần bạn'
                                  : 'Kết quả',
                              style: context.textStyles.titleSmall),
                        );
                      }
                      final r = list[i - 1];
                      final meta = [
                        if (r.distanceKm != null) _distance(r.distanceKm!),
                        r.address,
                      ].join(' · ');
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: context.colors.secondaryContainer,
                          child: Icon(Icons.storefront_outlined,
                              color: context.colors.primary),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(r.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            if (r.isVeganCertified) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified_rounded,
                                  size: 16, color: context.vl.success),
                            ],
                          ],
                        ),
                        subtitle: Text(meta,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => _pick(r),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
