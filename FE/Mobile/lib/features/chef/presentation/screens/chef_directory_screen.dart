// lib/features/chef/presentation/screens/chef_directory_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/floating_bar_clearance.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../booking/presentation/screens/booking_history_screen.dart';
import '../../domain/chef_specialties.dart';
import '../../domain/entities/chef.dart';
import '../controllers/chef_controllers.dart';
import '../widgets/chef_card.dart';
import 'chef_profile_screen.dart';

/// Tab "Chuyên gia" (everyone, guests included): verified chefs &
/// nutritionists who design N-day meal plans on request. [pickMode] is the
/// same list opened from Thực đơn › "Nhờ chuyên gia thiết kế".
class ChefDirectoryScreen extends ConsumerStatefulWidget {
  const ChefDirectoryScreen({super.key, this.pickMode = false});

  /// Pushed to choose a chef for a meal plan (title "Chọn chuyên gia").
  final bool pickMode;

  @override
  ConsumerState<ChefDirectoryScreen> createState() =>
      _ChefDirectoryScreenState();
}

class _ChefDirectoryScreenState extends ConsumerState<ChefDirectoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(chefDirectoryProvider.notifier).search(value);
    });
    setState(() {}); // toggles the clear button
  }

  void _open(Chef chef) => Navigator.of(context)
      .push(ChefProfileScreen.route(chef.id, preview: chef));

  Future<void> _openHistory() async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để xem lịch sử tư vấn của bạn.')) {
      return;
    }
    if (mounted) {
      await Navigator.of(context).push(BookingHistoryScreen.route());
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chefDirectoryProvider);
    final specialty = async.hasValue ? async.requireValue.specialty : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: Text(widget.pickMode ? 'Chọn chuyên gia' : 'Chuyên gia'),
            actions: [
              if (!widget.pickMode)
                IconButton(
                  tooltip: 'Lịch sử tư vấn',
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded),
                ),
            ],
          ),
          SliverToBoxAdapter(child: _IntroBanner(pickMode: widget.pickMode)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, chuyên môn, thành phố…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xoá',
                          onPressed: () {
                            _search.clear();
                            _onQueryChanged('');
                          },
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _SpecialtyChips(
                selected: specialty,
                onSelected: (value) => ref
                    .read(chefDirectoryProvider.notifier)
                    .setSpecialty(value),
              ),
            ),
          ),
          if (async.hasValue && async.requireValue.searching)
            const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2)),
          ...switch (async) {
            AsyncData(:final value) when value.chefs.isEmpty => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyStateView(
                      icon: Icons.person_search_outlined,
                      title: 'Không tìm thấy chuyên gia phù hợp',
                      message:
                          'Thử bỏ bớt từ khoá hoặc chọn "Tất cả" chuyên môn.',
                      actionLabel: 'Xoá bộ lọc',
                      onAction: () {
                        _search.clear();
                        ref.read(chefDirectoryProvider.notifier)
                          ..setSpecialty(null)
                          ..search('');
                      },
                    ),
                  ),
                ),
              ],
            AsyncData(:final value) => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      widget.pickMode
                          ? 24 + MediaQuery.paddingOf(context).bottom
                          : floatingBarClearance(context)),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ChefCard(
                            chef: value.chefs[i],
                            onTap: () => _open(value.chefs[i])),
                      ),
                      childCount: value.chefs.length,
                    ),
                  ),
                ),
              ],
            AsyncError(:final error) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: ErrorStateView(
                        error: error,
                        onRetry: () => ref.invalidate(chefDirectoryProvider)),
                  ),
                ),
              ],
            _ => [const SliverToBoxAdapter(child: _DirectorySkeleton())],
          },
        ],
      ),
    );
  }
}

/// "Tất cả" + [chefSpecialties]. Scrolls sideways; each chip gets a finite
/// max width so its label is laid out again once the Google font arrives
/// (same fix as FeedFilterChips: no clipped "Ẩm thực chay Hu").
class _SpecialtyChips extends StatelessWidget {
  const _SpecialtyChips({required this.selected, required this.onSelected});

  /// `null` = Tất cả.
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final maxChipWidth = math.max(0.0, available - 32);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final (i, value)
                in <String?>[null, ...chefSpecialties].indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChipWidth),
                child: ChoiceChip(
                  label: Text(value ?? 'Tất cả'),
                  selected: selected == value,
                  onSelected: (_) => onSelected(value),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// What the tab is for; in pick mode, what to do next.
class _IntroBanner extends StatelessWidget {
  const _IntroBanner({required this.pickMode});

  final bool pickMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: VLCard(
        color: context.colors.secondaryContainer,
        borderColor: Colors.transparent,
        child: Row(
          children: [
            Icon(pickMode ? Icons.touch_app_outlined : Icons.verified_rounded,
                color: context.vl.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pickMode
                    ? 'Chọn một chuyên gia để thiết kế thực đơn theo yêu cầu. Giá cuối do hai bên thoả thuận.'
                    : 'Đầu bếp & chuyên gia dinh dưỡng đã được VeganLife xác minh, nhận thiết kế thực đơn 3–30 ngày theo yêu cầu.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.colors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectorySkeleton extends StatelessWidget {
  const _DirectorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: VLCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 56, height: 56, radius: 28),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 160, height: 16),
                          SizedBox(height: 8),
                          SkeletonBox(height: 12),
                          SizedBox(height: 8),
                          SkeletonBox(width: 120, height: 12),
                          SizedBox(height: 12),
                          SkeletonBox(width: 90, height: 14),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
