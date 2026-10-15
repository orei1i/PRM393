// lib/features/commerce/presentation/screens/my_orders_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/state_views.dart';
import '../../domain/commerce_status.dart';
import '../controllers/commerce_controllers.dart';
import '../widgets/commerce_ui.dart';
import '../widgets/order_card.dart';

enum _OrderFilter {
  all('Tất cả'),
  pending('Chờ thanh toán'),
  paid('Đã thanh toán'),
  closed('Đã huỷ / hoàn tiền');

  const _OrderFilter(this.label);
  final String label;

  bool matches(OrderStatus status) => switch (this) {
        all => true,
        pending => status == OrderStatus.pending,
        paid => status == OrderStatus.paid,
        closed =>
          status == OrderStatus.cancelled || status == OrderStatus.refunded,
      };
}

/// Tôi › "Đơn hàng của tôi": consults, courses and VIP menus the member
/// ordered, with their payment state.
class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  static const routeName = '/orders';

  static Route<void> route() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => const MyOrdersScreen(),
      );

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  _OrderFilter _filter = _OrderFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đơn hàng của tôi')),
      body: GuestGate(
        icon: Icons.receipt_long_outlined,
        title: 'Đơn hàng của bạn',
        message: 'Đăng nhập để đặt lịch, mua gói và theo dõi thanh toán.',
        benefits: const [
          'Thanh toán bằng mã QR PaymentOS',
          'Mở lại khoá học và thực đơn VIP đã mua bất cứ lúc nào',
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _FilterRow(
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
              ),
            ),
            Expanded(child: _list()),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final async = ref.watch(myOrdersProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (orders) {
        final shown = orders.where((o) => _filter.matches(o.status)).toList();
        if (orders.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: EmptyStateView(
                icon: Icons.receipt_long_outlined,
                title: 'Chưa có đơn hàng',
                message:
                    'Đặt lịch tư vấn hoặc mua khoá học, thực đơn VIP từ các chuyên gia đã xác minh.',
                actionLabel: 'Khám phá chuyên gia',
                onAction: () => Navigator.of(context).maybePop(),
              ),
            ),
          );
        }
        if (shown.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: EmptyStateView(
                icon: Icons.filter_alt_off_outlined,
                title: 'Không có đơn ở mục này',
                message: 'Chọn "Tất cả" để xem mọi đơn hàng.',
                actionLabel: 'Xem tất cả',
                onAction: () => setState(() => _filter = _OrderFilter.all),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(myOrdersProvider.future),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: shown.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => OrderCard(order: shown[i]),
          ),
        );
      },
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error, onRetry: () => ref.invalidate(myOrdersProvider)),
        ),
      ),
      loading: () => const ListSkeleton(height: 132),
    );
  }
}

/// Scrolls sideways when the labels don't fit (narrow phones, large text).
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelected});

  final _OrderFilter selected;
  final ValueChanged<_OrderFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // A finite max width makes each chip lay its label out again once the
      // Google font arrives (see FeedFilterChips).
      final maxChipWidth = math.max(0.0, constraints.maxWidth - 32);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final (i, f) in _OrderFilter.values.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChipWidth),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: f == selected,
                  onSelected: (_) => onSelected(f),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}
