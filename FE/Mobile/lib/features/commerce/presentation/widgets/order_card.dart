// lib/features/commerce/presentation/widgets/order_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/presentation/screens/my_consultations_screen.dart';
import '../../data/commerce_api_service.dart';
import '../../data/models/order_model.dart';
import '../../domain/commerce_status.dart';
import '../controllers/commerce_controllers.dart';
import '../screens/order_detail_screen.dart';
import '../screens/payment_screen.dart';
import '../screens/service_content_screen.dart';
import 'commerce_ui.dart';

/// "Đơn hàng của tôi" row: service, chef, type, amount, status, date and
/// the action that fits the state.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      onTap: () =>
          Navigator.of(context).push(OrderDetailScreen.route(order.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.service.title,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(order.service.chefName,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              orderStatusTag(context, order.status),
              serviceTypeTag(context, order.type),
              VLTag.neutral(context, formatFullDate(order.createdAt)),
              Text(formatVnd(order.amount),
                  style: context.textStyles.titleSmall?.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          OrderActions(order: order),
        ],
      ),
    );
  }
}

/// Pending → "Thanh toán tiếp" / "Huỷ đơn"; paid consult → "Xem lịch";
/// paid package with access → "Mở nội dung"; refunded → a note.
class OrderActions extends ConsumerStatefulWidget {
  const OrderActions({super.key, required this.order, this.fromOrders = true});

  final OrderDto order;

  /// The payment screen's "Đơn hàng của tôi" goes back instead of pushing.
  final bool fromOrders;

  @override
  ConsumerState<OrderActions> createState() => _OrderActionsState();
}

class _OrderActionsState extends ConsumerState<OrderActions> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Huỷ đơn hàng?'),
        content: const Text(
            'Mã QR sẽ ngừng hiệu lực. Với lịch tư vấn, khung giờ được nhả cho người khác.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Giữ đơn')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Huỷ đơn')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(commerceApiProvider).cancelOrder(widget.order.id);
      ref.read(commerceRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã huỷ đơn hàng.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final navigator = Navigator.of(context);
    final List<Widget> actions = switch (order.status) {
      OrderStatus.pending => [
          FilledButton(
            onPressed: () => navigator.push(PaymentScreen.route(order.id,
                autoRenew: true, fromOrders: widget.fromOrders)),
            child: const Text('Thanh toán tiếp'),
          ),
          OutlinedButton(
            onPressed: _cancelling ? null : _cancel,
            child: Text(_cancelling ? 'Đang huỷ…' : 'Huỷ đơn'),
          ),
        ],
      OrderStatus.paid when !order.type.isPackage => [
          OutlinedButton.icon(
            onPressed: () => navigator.push(MyConsultationsScreen.route()),
            icon: const Icon(Icons.event_note_outlined, size: 18),
            label: const Text('Xem lịch'),
          ),
        ],
      OrderStatus.paid when order.canOpenContent(DateTime.now()) => [
          FilledButton.tonalIcon(
            onPressed: () => navigator.push(ServiceContentScreen.route(
                order.serviceId,
                title: order.service.title)),
            icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('Mở nội dung'),
          ),
        ],
      OrderStatus.refunded => [
          Text('Đã hoàn tiền (mô phỏng)',
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.vl.onAiContainer)),
        ],
      _ => const [],
    };
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: actions,
      ),
    );
  }
}
