// lib/features/booking/presentation/screens/chef_booking_inbox_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../chef_studio/presentation/widgets/chef_only_gate.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_views.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_ui.dart';
import 'booking_detail_screen.dart';

/// Tôi › Chuyên gia › "Yêu cầu tư vấn" (role Chef): tabs "Mới · Đang thương
/// lượng · Đang thực hiện · Đã kết thúc", each with a badge of what waits on
/// the chef (new requests, counter-offers, days due today, complaints).
class ChefBookingInboxScreen extends StatelessWidget {
  const ChefBookingInboxScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefBookingInboxScreen());

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final isChef =
          ref.watch(sessionControllerProvider.select((s) => s.isChef));
      if (isChef) return const _Inbox();
      return Scaffold(
        appBar: AppBar(title: const Text('Yêu cầu tư vấn')),
        body: const ChefOnlyGate(child: SizedBox.shrink()),
      );
    });
  }
}

class _Inbox extends ConsumerWidget {
  const _Inbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefInboxProvider);
    final now = DateTime.now();
    final all = async.valueOrNull ?? const <BookingDto>[];
    int badge(InboxTab tab) => all
        .where((b) => InboxTab.of(b.status) == tab && chefNeedsAction(b, now))
        .length;
    return DefaultTabController(
      length: InboxTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yêu cầu tư vấn'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final tab in InboxTab.values)
                Tab(
                  child: Badge(
                    isLabelVisible: badge(tab) > 0,
                    label: Text('${badge(tab)}'),
                    offset: const Offset(12, -6),
                    child: Text(tab.label),
                  ),
                ),
            ],
          ),
        ),
        body: DemoDataBanner.wrap(BackendModule.bookings,
            child: switch (async) {
              AsyncValue(valueOrNull: final value?) => TabBarView(
                  children: [
                    for (final tab in InboxTab.values)
                      _List(
                        tab: tab,
                        items: value
                            .where((b) => InboxTab.of(b.status) == tab)
                            .toList(),
                      ),
                  ],
                ),
              AsyncError(:final error) => Center(
                  child: SingleChildScrollView(
                    child: ErrorStateView(
                        error: error,
                        onRetry: () => ref.invalidate(chefInboxProvider)),
                  ),
                ),
              _ => const ListSkeleton(height: 120),
            }),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.tab, required this.items});

  final InboxTab tab;
  final List<BookingDto> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.inbox_outlined,
            title: switch (tab) {
              InboxTab.fresh => 'Chưa có yêu cầu mới',
              InboxTab.negotiating => 'Không có yêu cầu đang thương lượng',
              InboxTab.inProgress => 'Không có kế hoạch đang thực hiện',
              InboxTab.finished => 'Chưa có kế hoạch nào kết thúc',
            },
            message:
                'Thành viên đặt bạn từ hồ sơ công khai trong tab Chuyên gia.',
          ),
        ),
      );
    }
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(chefInboxProvider);
        await ref.read(chefInboxProvider.future);
      },
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => BookingCard(
          booking: items[i],
          asChef: true,
          needsAction: chefNeedsAction(items[i], now),
          onTap: () => Navigator.of(context)
              .push(BookingDetailScreen.route(items[i].id)),
        ),
      ),
    );
  }
}
