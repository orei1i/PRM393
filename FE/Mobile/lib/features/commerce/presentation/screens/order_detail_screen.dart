// lib/features/commerce/presentation/screens/order_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/models/order_model.dart';
import '../../domain/commerce_status.dart';
import '../controllers/commerce_controllers.dart';
import '../widgets/commerce_ui.dart';
import '../widgets/order_card.dart';

/// Timeline (Tạo đơn → Thanh toán → Cấp quyền → Tư vấn) plus the payment,
/// access-grant and consultation blocks of one order.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  static Route<void> route(String orderId) => MaterialPageRoute<void>(
      builder: (_) => OrderDetailScreen(orderId: orderId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết đơn hàng')),
      body: async.when(
        skipLoadingOnReload: true,
        data: (order) => RefreshIndicator(
          onRefresh: () => ref.refresh(orderProvider(orderId).future),
          child: _Body(order: order),
        ),
        error: (error, _) => Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(orderProvider(orderId))),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.order});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    final payment = order.payment;
    final grant = order.accessGrant;
    final consultation = order.consultation;
    final now = DateTime.now();
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        VLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.service.title,
                  style: context.textStyles.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(order.service.chefName,
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  serviceTypeTag(context, order.type),
                  orderStatusTag(context, order.status),
                ],
              ),
              const SizedBox(height: 10),
              InfoRow(label: 'Số tiền', value: formatVnd(order.amount)),
              InfoRow(label: 'Mã đơn', value: '#${order.id}'),
              InfoRow(label: 'Tạo lúc', value: formatStamp(order.createdAt)),
              OrderActions(order: order),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('Tiến trình'),
        VLCard(child: _Timeline(order: order, now: now)),
        const SizedBox(height: 16),
        const _SectionTitle('Thanh toán'),
        VLCard(
          child: payment == null
              ? Text('Chưa tạo mã thanh toán.',
                  style: context.textStyles.bodyMedium)
              : Column(
                  children: [
                    InfoRow(label: 'Cổng thanh toán', value: payment.provider),
                    InfoRow(
                      label: 'Mã giao dịch',
                      value: payment.transactionRef,
                      trailing: IconButton(
                        tooltip: 'Sao chép mã giao dịch',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: payment.transactionRef));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Đã sao chép mã giao dịch')));
                        },
                      ),
                    ),
                    InfoRow(label: 'Trạng thái', value: payment.status.label),
                    if (payment.paidAt != null)
                      InfoRow(
                          label: 'Thanh toán lúc',
                          value: formatStamp(payment.paidAt!)),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('Quyền truy cập'),
        VLCard(
          child: grant == null
              ? Text('Được cấp ngay khi thanh toán thành công.',
                  style: context.textStyles.bodyMedium)
              : Column(
                  children: [
                    InfoRow(
                        label: 'Trạng thái', value: grant.statusAt(now).label),
                    InfoRow(
                        label: 'Cấp lúc', value: formatStamp(grant.grantedAt)),
                    if (grant.expiresAt != null)
                      InfoRow(
                          label: 'Hết hạn',
                          value: formatFullDate(grant.expiresAt!)),
                  ],
                ),
        ),
        if (consultation != null) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Buổi tư vấn'),
          VLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                    label: 'Thời gian',
                    value: formatSlot(consultation.startAt)),
                InfoRow(
                    label: 'Thời lượng',
                    value: '${consultation.durationMinutes} phút'),
                InfoRow(label: 'Trạng thái', value: consultation.status.label),
                if (consultation.buyerNote != null)
                  _Quote(label: 'Bạn đã gửi', text: consultation.buyerNote!),
                if (consultation.declineReason != null)
                  _Quote(
                      label: 'Chuyên gia từ chối',
                      text: consultation.declineReason!),
                if (consultation.chefNotes != null)
                  _Quote(
                      label: 'Ghi chú của chuyên gia',
                      text: consultation.chefNotes!),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(text,
            style: context.textStyles.labelLarge
                ?.copyWith(color: context.vl.muted)),
      );
}

class _Quote extends StatelessWidget {
  const _Quote({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: context.textStyles.labelLarge
                  ?.copyWith(color: context.vl.muted)),
          const SizedBox(height: 2),
          Text(text, style: context.textStyles.bodyMedium),
        ],
      ),
    );
  }
}

enum _StepState { done, current, todo, stopped }

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order, required this.now});

  final OrderDto order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final payment = order.payment;
    final grant = order.accessGrant;
    final consultation = order.consultation;
    final paid = payment?.paidAt;
    final closed = order.status == OrderStatus.cancelled;

    final steps = <(String, String?, _StepState)>[
      ('Tạo đơn', formatStamp(order.createdAt), _StepState.done),
      (
        'Thanh toán',
        paid != null
            ? formatStamp(paid)
            : closed
                ? 'Đơn đã huỷ'
                : payment?.status.label,
        paid != null
            ? _StepState.done
            : closed
                ? _StepState.stopped
                : _StepState.current,
      ),
      (
        'Cấp quyền',
        grant == null
            ? null
            : grant.expiresAt == null
                ? grant.statusAt(now).label
                : '${grant.statusAt(now).label} · đến ${formatFullDate(grant.expiresAt!)}',
        grant == null
            ? (closed ? _StepState.stopped : _StepState.todo)
            : grant.statusAt(now) == GrantStatus.revoked
                ? _StepState.stopped
                : _StepState.done,
      ),
      if (consultation != null)
        (
          'Tư vấn',
          consultation.status.label,
          switch (consultation.status) {
            ConsultationStatus.completed => _StepState.done,
            ConsultationStatus.declined ||
            ConsultationStatus.cancelled =>
              _StepState.stopped,
            ConsultationStatus.awaitingPayment => _StepState.todo,
            _ => _StepState.current,
          },
        ),
    ];

    final vl = context.vl;
    return Column(
      children: [
        for (final (title, subtitle, state) in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (state) {
                    _StepState.done => Icons.check_circle_rounded,
                    _StepState.current => Icons.radio_button_checked_rounded,
                    _StepState.todo => Icons.radio_button_unchecked_rounded,
                    _StepState.stopped => Icons.cancel_rounded,
                  },
                  size: 22,
                  color: switch (state) {
                    _StepState.done => vl.success,
                    _StepState.current => vl.caution,
                    _StepState.todo => vl.muted,
                    _StepState.stopped => context.colors.error,
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: context.textStyles.titleSmall?.copyWith(
                              color:
                                  state == _StepState.todo ? vl.muted : null)),
                      if (subtitle != null)
                        Text(subtitle,
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: vl.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
