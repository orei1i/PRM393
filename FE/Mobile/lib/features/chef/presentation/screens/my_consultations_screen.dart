// lib/features/chef/presentation/screens/my_consultations_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/data/commerce_api_service.dart';
import '../../../commerce/data/models/consultation_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../../commerce/presentation/screens/order_detail_screen.dart';
import '../../../commerce/presentation/screens/payment_screen.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';

/// "Lịch tư vấn của tôi": the member's consultations, from "Chờ thanh toán"
/// to "Đã hoàn thành" (with the chef's notes) or "Chuyên gia từ chối".
class MyConsultationsScreen extends ConsumerWidget {
  const MyConsultationsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const MyConsultationsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myConsultationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch tư vấn của tôi')),
      body: GuestGate(
        icon: Icons.event_note_outlined,
        title: 'Lịch tư vấn với chuyên gia',
        message: 'Đăng nhập để đặt và theo dõi lịch tư vấn 1–1.',
        benefits: const [
          'Nhắc lịch trước giờ hẹn',
          'Thanh toán qua PaymentOS, hoàn tiền nếu chuyên gia từ chối',
        ],
        child: async.when(
          skipLoadingOnReload: true,
          data: (items) => items.isEmpty
              ? const Center(
                  child: SingleChildScrollView(
                    child: EmptyStateView(
                      icon: Icons.event_busy_outlined,
                      title: 'Chưa có lịch tư vấn',
                      message:
                          'Vào tab Chuyên gia để chọn đầu bếp hoặc chuyên gia dinh dưỡng phù hợp.',
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(myConsultationsProvider.future),
                  child: _List(items: items),
                ),
          error: (error, _) => Center(
            child: SingleChildScrollView(
              child: ErrorStateView(
                  error: error,
                  onRetry: () => ref.invalidate(myConsultationsProvider)),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.items});

  final List<ConsultationDto> items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = items.where((c) => c.isUpcoming(now)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final past = items.where((c) => !upcoming.contains(c)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (upcoming.isNotEmpty) ...[
          Text('Sắp tới', style: context.textStyles.titleMedium),
          const SizedBox(height: 8),
          for (final c in upcoming)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ConsultationCard(item: c)),
          const SizedBox(height: 12),
        ],
        if (past.isNotEmpty) ...[
          Text('Đã qua & đã huỷ', style: context.textStyles.titleMedium),
          const SizedBox(height: 8),
          for (final c in past)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ConsultationCard(item: c)),
        ],
      ],
    );
  }
}

class _ConsultationCard extends ConsumerStatefulWidget {
  const _ConsultationCard({required this.item});

  final ConsultationDto item;

  @override
  ConsumerState<_ConsultationCard> createState() => _ConsultationCardState();
}

class _ConsultationCardState extends ConsumerState<_ConsultationCard> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Huỷ lịch tư vấn?'),
        content: const Text(
            'Bạn được hoàn tiền (mô phỏng) và chuyên gia sẽ nhận được thông báo. '
            'Lịch đã xác nhận chỉ huỷ được trước giờ hẹn 24 tiếng.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Giữ lịch')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Huỷ lịch')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(commerceApiProvider).cancelConsultation(widget.item.id);
      ref.read(commerceRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Đã huỷ lịch. Tiền đã được hoàn (mô phỏng).')));
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
    final c = widget.item;
    final vl = context.vl;
    final now = DateTime.now();
    final orderId = c.orderId;
    final navigator = Navigator.of(context);

    final actions = <Widget>[
      if (c.status == ConsultationStatus.awaitingPayment && orderId != null)
        FilledButton(
          onPressed: () =>
              navigator.push(PaymentScreen.route(orderId, autoRenew: true)),
          child: const Text('Thanh toán tiếp'),
        ),
      if (c.status == ConsultationStatus.confirmed && c.endAt.isAfter(now))
        FilledButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Phòng tư vấn mở trước giờ hẹn 15 phút.')),
          ),
          icon: const Icon(Icons.video_call_outlined),
          label: const Text('Vào phòng tư vấn'),
        ),
      if (c.canBuyerCancel(now))
        OutlinedButton(
          onPressed: _cancelling ? null : _cancel,
          child: Text(_cancelling ? 'Đang huỷ…' : 'Huỷ lịch'),
        ),
      if (orderId != null)
        TextButton(
          onPressed: () => navigator.push(OrderDetailScreen.route(orderId)),
          child: const Text('Xem đơn hàng'),
        ),
    ];

    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: c.chefName, size: 40, verified: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.chefName,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(c.serviceTitle,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          consultationStatusTag(context, c.status),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: vl.muted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      '${formatClock(c.startAt)} · ${formatLongDate(c.startAt)} · ${c.durationMinutes} phút')),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.videocam_outlined, size: 18, color: vl.muted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('Online qua video · ${formatVnd(c.amount)}')),
            ],
          ),
          if (c.buyerNote != null) ...[
            const SizedBox(height: 8),
            Text('“${c.buyerNote}”',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
          if (c.status == ConsultationStatus.declined) ...[
            const SizedBox(height: 10),
            _Note(
              color: context.colors.errorContainer,
              foreground: context.colors.onErrorContainer,
              text:
                  'Chuyên gia từ chối: ${c.declineReason ?? 'không nêu lý do'}',
            ),
            const SizedBox(height: 6),
            Text('Đã hoàn tiền (mô phỏng)',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: vl.onAiContainer)),
          ],
          if (c.status == ConsultationStatus.completed &&
              c.chefNotes != null) ...[
            const SizedBox(height: 10),
            Text('Ghi chú của chuyên gia',
                style: context.textStyles.labelLarge),
            const SizedBox(height: 4),
            _Note(
              color: vl.successContainer,
              foreground: vl.onSuccessContainer,
              text: c.chefNotes!,
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(
      {required this.color, required this.foreground, required this.text});

  final Color color;
  final Color foreground;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: context.textStyles.bodyMedium?.copyWith(color: foreground)),
    );
  }
}
