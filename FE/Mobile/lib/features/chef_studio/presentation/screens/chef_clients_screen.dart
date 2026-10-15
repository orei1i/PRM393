// lib/features/chef_studio/presentation/screens/chef_clients_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/text_search.dart';
import '../../../../core/widgets/floating_bar_clearance.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../data/models/chef_client_models.dart';
import '../../domain/chef_client_rules.dart';
import '../controllers/chef_clients_controllers.dart';
import '../widgets/chef_client_card.dart';
import '../widgets/chef_only_gate.dart';
import 'chef_bookings_screen.dart';
import 'chef_client_detail_screen.dart';
import 'chef_suggestions_screen.dart';

/// Short filter labels ("Tư vấn", not "Tư vấn 1–1").
String _typeLabel(ServiceType t) => switch (t) {
      ServiceType.consult => 'Tư vấn',
      ServiceType.course => 'Khoá học',
      ServiceType.vipMenu => 'Thực đơn VIP',
    };

/// Tab "Khách hàng" (role Chef, in place of "Chuyên gia"): the members
/// using my packages, in three tabs (Đang dùng gói · Sắp hết hạn · Đã kết
/// thúc), with search by name and a service-type filter. Also pushed from
/// the chef dashboard ([route]).
class ChefClientsScreen extends ConsumerStatefulWidget {
  const ChefClientsScreen({super.key, this.pushed = false});

  /// Pushed from the dashboard (back button) rather than shown as a tab.
  final bool pushed;

  static Route<void> route() => MaterialPageRoute<void>(
      builder: (_) => const ChefClientsScreen(pushed: true));

  @override
  ConsumerState<ChefClientsScreen> createState() => _ChefClientsScreenState();
}

class _ChefClientsScreenState extends ConsumerState<ChefClientsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: ClientBucket.values.length, vsync: this)
        ..addListener(() {
          if (!_tabs.indexIsChanging) setState(() {});
        });
  final _search = TextEditingController();
  ServiceType? _type;

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  ClientBucket get _bucket => ClientBucket.values[_tabs.index];

  bool _matches(ChefClientDto c, DateTime now) {
    if (!matchesQuery(c.fullName, _search.text)) return false;
    final type = _type;
    if (type == null) return true;
    return c.packages
        .any((o) => o.type == type && packageBucket(o, now) == c.status);
  }

  void _clearFilters() {
    _search.clear();
    setState(() => _type = null);
  }

  void _open(ChefClientDto client) => Navigator.of(context)
      .push(ChefClientDetailScreen.route(client.userId, name: client.fullName));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.pushed,
        title: const Text('Khách hàng'),
        actions: [
          IconButton(
            tooltip: 'Đề xuất món cho khách',
            onPressed: () =>
                Navigator.of(context).push(ChefSuggestionsScreen.route()),
            icon: const Icon(Icons.restaurant_menu_rounded),
          ),
          IconButton(
            tooltip: 'Lịch hẹn & đơn hàng',
            onPressed: () =>
                Navigator.of(context).push(ChefBookingsScreen.route()),
            icon: const Icon(Icons.event_note_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ChefOnlyGate(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final async = ref.watch(chefClientsProvider);
    final now = DateTime.now();
    final all = async.valueOrNull ?? const <ChefClientDto>[];
    final filtered = all.where((c) => _matches(c, now)).toList();
    int count(ClientBucket b) => filtered.where((c) => c.status == b).length;
    final shown = filtered.where((c) => c.status == _bucket).toList()
      ..sort((a, b) {
        DateTime end(ChefClientDto c) =>
            primaryPackage(c.packages, c.status, now, type: _type)
                ?.accessGrant
                ?.expiresAt ??
            DateTime(9999);
        return _bucket == ClientBucket.ended
            ? end(b).compareTo(end(a))
            : end(a).compareTo(end(b));
      });

    return RefreshIndicator(
      onRefresh: () => ref.refresh(chefClientsProvider.future),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm khách theo tên…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xoá',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
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
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final b in ClientBucket.values)
                  Tab(
                      text: async.hasValue
                          ? '${b.label} (${count(b)})'
                          : b.label),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _TypeChips(
                selected: _type,
                onSelected: (t) => setState(() => _type = t),
              ),
            ),
          ),
          ...switch (async) {
            AsyncData() when shown.isEmpty => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: _empty(filtering: all.isNotEmpty)),
                ),
              ],
            AsyncData() => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      16, 4, 16, floatingBarClearance(context)),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => ChefClientCard(
                      client: shown[i],
                      now: now,
                      typeFilter: _type,
                      onTap: () => _open(shown[i]),
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
                        onRetry: () => ref.invalidate(chefClientsProvider)),
                  ),
                ),
              ],
            _ => [const SliverToBoxAdapter(child: _ClientsSkeleton())],
          },
        ],
      ),
    );
  }

  Widget _empty({required bool filtering}) {
    if (filtering && (_search.text.isNotEmpty || _type != null)) {
      return EmptyStateView(
        icon: Icons.person_search_outlined,
        title: 'Không tìm thấy khách phù hợp',
        message: 'Thử bỏ bớt từ khoá hoặc chọn "Tất cả" loại dịch vụ.',
        actionLabel: 'Xoá bộ lọc',
        onAction: _clearFilters,
      );
    }
    return switch (_bucket) {
      ClientBucket.active => const EmptyStateView(
          icon: Icons.groups_outlined,
          title: 'Chưa có khách đang dùng gói',
          message:
              'Khi thành viên mua gói hoặc đặt lịch tư vấn với bạn, họ sẽ xuất hiện ở đây.',
        ),
      ClientBucket.expiringSoon => const EmptyStateView(
          icon: Icons.hourglass_bottom_rounded,
          title: 'Không có gói nào sắp hết hạn',
          message:
              'Gói còn dưới $expiringSoonDays ngày sẽ hiện ở đây để bạn nhắc khách gia hạn.',
        ),
      ClientBucket.ended => const EmptyStateView(
          icon: Icons.history_rounded,
          title: 'Chưa có khách đã kết thúc gói',
          message:
              'Khách có gói hết hạn, buổi tư vấn đã xong hoặc đơn đã hoàn tiền sẽ nằm ở đây.',
        ),
    };
  }
}

/// Tất cả · Tư vấn · Khoá học · Thực đơn VIP. Scrolls sideways with large
/// text instead of clipping.
class _TypeChips extends StatelessWidget {
  const _TypeChips({required this.selected, required this.onSelected});

  final ServiceType? selected;
  final ValueChanged<ServiceType?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <(ServiceType?, String)>[
      (null, 'Tất cả'),
      for (final t in ServiceType.values) (t, _typeLabel(t)),
    ];
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
            for (final (i, (type, label)) in options.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChipWidth),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected == type,
                  onSelected: (_) => onSelected(type),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _ClientsSkeleton extends StatelessWidget {
  const _ClientsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++) ...const [
              SkeletonBox(height: 112, radius: 16),
              SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
