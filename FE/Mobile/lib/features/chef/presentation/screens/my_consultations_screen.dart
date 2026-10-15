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
import '../../data/chef_api_service.dart';
import '../../domain/entities/chef.dart';
import '../controllers/chef_controllers.dart';

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
          'Thanh toán an toàn qua PayOS sau khi chuyên gia xác nhận'
        ],
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => const Center(
              child: EmptyStateView(
                icon: Icons.event_busy_outlined,
                title: 'Chưa có lịch tư vấn',
                message:
                    'Vào tab Chuyên gia để chọn đầu bếp hoặc chuyên gia dinh dưỡng phù hợp.',
              ),
            ),
          AsyncData(:final value) => RefreshIndicator(
              onRefresh: () => ref.refresh(myConsultationsProvider.future),
              child: _List(items: value),
            ),
          AsyncError(:final error) => Center(
              child: ErrorStateView(
                  error: error,
                  onRetry: () => ref.invalidate(myConsultationsProvider)),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.items});

  final List<Consultation> items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = items
        .where((c) => c.status.isUpcoming && c.scheduledAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final past = items.where((c) => !upcoming.contains(c)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
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

  final Consultation item;

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
            'Huỷ trước giờ hẹn 12 tiếng không mất phí. Chuyên gia sẽ nhận được thông báo.'),
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
      await ref.read(chefApiProvider).cancelConsultation(widget.item.id);
      ref.invalidate(myConsultationsProvider);
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
    final (Color bg, Color fg) = switch (c.status) {
      ConsultationStatus.confirmed => (
          vl.successContainer,
          vl.onSuccessContainer
        ),
      ConsultationStatus.pending => (
          vl.cautionContainer,
          vl.onCautionContainer
        ),
      _ => (context.colors.surfaceContainer, context.colors.onSurfaceVariant),
    };
    final t = c.scheduledAt;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(c.packageName,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted)),
                  ],
                ),
              ),
              VLTag(label: c.status.label, background: bg, foreground: fg),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: vl.muted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      '$time · ${formatLongDate(t)} · ${c.durationMinutes} phút')),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                  c.mode == ConsultMode.online
                      ? Icons.videocam_outlined
                      : Icons.home_outlined,
                  size: 18,
                  color: vl.muted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('${c.mode.label} · ${formatVnd(c.priceVnd)}')),
            ],
          ),
          if (c.note != null && c.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${c.note}”',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
          if (c.status.isUpcoming && c.scheduledAt.isAfter(DateTime.now())) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (c.status == ConsultationStatus.confirmed)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Phòng tư vấn mở trước giờ hẹn 10 phút.')),
                      ),
                      icon: const Icon(Icons.video_call_outlined),
                      label: const Text('Vào phòng tư vấn'),
                    ),
                  ),
                if (c.status == ConsultationStatus.confirmed)
                  const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelling ? null : _cancel,
                    child: Text(_cancelling ? 'Đang huỷ…' : 'Huỷ lịch'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
