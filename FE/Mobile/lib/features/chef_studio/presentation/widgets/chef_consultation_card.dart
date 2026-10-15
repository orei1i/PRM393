// lib/features/chef_studio/presentation/widgets/chef_consultation_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/data/models/consultation_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/chef_studio_api_service.dart';
import '../../domain/chef_studio_rules.dart';
import '../screens/consultation_session_screen.dart';

/// Booking as the chef sees it: buyer, service, time, amount, the buyer's
/// note and status. Pending ones get "Từ chối" / "Xác nhận".
class ChefConsultationCard extends ConsumerStatefulWidget {
  const ChefConsultationCard({super.key, required this.item});

  final ConsultationDto item;

  @override
  ConsumerState<ChefConsultationCard> createState() =>
      _ChefConsultationCardState();
}

class _ChefConsultationCardState extends ConsumerState<ChefConsultationCard> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.read(commerceRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirm() => _act(
      () => ref
          .read(chefStudioApiProvider)
          .confirmConsultation(widget.item.id)
          .then((_) {}),
      'Đã xác nhận lịch với ${widget.item.buyer?.fullName ?? 'khách'}.');

  Future<void> _decline() async {
    final reason = await showDeclineDialog(context);
    if (reason == null || !mounted) return;
    await _act(
        () => ref
            .read(chefStudioApiProvider)
            .declineConsultation(widget.item.id, reason)
            .then((_) {}),
        'Đã từ chối và hoàn tiền cho khách (mô phỏng).');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    final vl = context.vl;
    return VLCard(
      onTap: () =>
          Navigator.of(context).push(ConsultationSessionScreen.route(c.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: c.buyer?.fullName ?? 'Khách', size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.buyer?.fullName ?? 'Khách',
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
                    '${formatSlot(c.startAt)} · ${c.durationMinutes} phút · ${formatVnd(c.amount)}'),
              ),
            ],
          ),
          if (c.buyerNote != null) ...[
            const SizedBox(height: 8),
            Text('“${c.buyerNote}”',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
          if (c.status == ConsultationStatus.pending) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _decline,
                  child: const Text('Từ chối'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: Text(_busy ? 'Đang lưu…' : 'Xác nhận'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Lý do (gửi cho khách)", at least 10 characters. Returns the reason, or
/// null when cancelled.
Future<String?> showDeclineDialog(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _DeclineDialog(),
    );

class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog();

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _reason = TextEditingController();
  bool _attempted = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (ConsultationRules.declineReason(_reason.text) != null) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Từ chối lịch hẹn?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Khách được hoàn tiền (mô phỏng) và nhận lý do bạn ghi dưới đây.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            onChanged: (_) {
              if (_attempted) setState(() {});
            },
            decoration: InputDecoration(
              labelText: 'Lý do (gửi cho khách)',
              border: const OutlineInputBorder(),
              errorText: _attempted
                  ? ConsultationRules.declineReason(_reason.text)
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ')),
        FilledButton(onPressed: _submit, child: const Text('Từ chối')),
      ],
    );
  }
}
