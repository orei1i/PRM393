// lib/features/booking/presentation/screens/booking_history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_nav.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_views.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_ui.dart';
import 'booking_detail_screen.dart';

/// Tôi › "Lịch sử tư vấn": whom I booked, what I asked for, the plan I
/// received and how it ended (released, refunded, complaint). Tabs "Đang
/// diễn ra" and "Đã kết thúc".
class BookingHistoryScreen extends ConsumerWidget {
  const BookingHistoryScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.bookingHistory),
        builder: (_) => const BookingHistoryScreen(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBookingsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch sử tư vấn'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Đang diễn ra'), Tab(text: 'Đã kết thúc')],
          ),
        ),
        body: switch (async) {
          AsyncValue(:final value?) => TabBarView(
              children: [
                _List(
                    items: value.where((b) => b.status.isOngoing).toList(),
                    ongoing: true),
                _List(
                    items: value.where((b) => !b.status.isOngoing).toList(),
                    ongoing: false),
              ],
            ),
          AsyncError(:final error) => Center(
              child: SingleChildScrollView(
                child: ErrorStateView(
                    error: error,
                    onRetry: () => ref.invalidate(myBookingsProvider)),
              ),
            ),
          _ => const ListSkeleton(height: 120),
        },
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.items, required this.ongoing});

  final List<BookingDto> items;
  final bool ongoing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.event_note_outlined,
            title: ongoing
                ? 'Bạn chưa đặt chuyên gia nào. Khám phá chuyên gia'
                : 'Chưa có kế hoạch nào kết thúc',
            message: ongoing
                ? 'Nhờ chuyên gia thiết kế thực đơn riêng theo mục tiêu và khẩu vị của bạn.'
                : 'Các kế hoạch đã hoàn tất, bị huỷ hoặc đã xử lý khiếu nại sẽ nằm ở đây.',
            actionLabel: ongoing ? 'Khám phá chuyên gia' : null,
            // The Chuyên gia tab itself, not another directory on top.
            onAction: ongoing
                ? () => AppNav.toShellTab(
                    Navigator.of(context), ref, ShellTab.chefs)
                : null,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myBookingsProvider);
        await ref.read(myBookingsProvider.future);
      },
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => BookingCard(
          booking: items[i],
          needsAction: memberNeedsAction(items[i]),
          onTap: () => AppNav.open(
              Navigator.of(context), BookingDetailScreen.route(items[i].id)),
        ),
      ),
    );
  }
}
