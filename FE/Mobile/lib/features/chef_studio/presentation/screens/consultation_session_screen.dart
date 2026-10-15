// lib/features/chef_studio/presentation/screens/consultation_session_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/data/models/consultation_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/chef_studio_api_service.dart';
import '../../domain/chef_studio_rules.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_consultation_card.dart';
import '../widgets/chef_only_gate.dart';

/// "Buổi tư vấn": Đã thanh toán → Đã xác nhận → Đang tư vấn → Hoàn thành.
class ConsultationSessionScreen extends StatelessWidget {
  const ConsultationSessionScreen({super.key, required this.consultationId});

  final String consultationId;

  static Route<void> route(String consultationId) => MaterialPageRoute<void>(
      builder: (_) =>
          ConsultationSessionScreen(consultationId: consultationId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buổi tư vấn')),
      body: ChefOnlyGate(child: _Loader(consultationId: consultationId)),
    );
  }
}

class _Loader extends ConsumerWidget {
  const _Loader({required this.consultationId});

  final String consultationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefConsultationsProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (all) {
        final c = all.where((c) => c.id == consultationId).firstOrNull;
        if (c == null) {
          return const Center(
            child: SingleChildScrollView(
              child: EmptyStateView(
                icon: Icons.event_busy_outlined,
                title: 'Không tìm thấy buổi tư vấn',
                message: 'Lịch hẹn có thể đã bị huỷ hoặc thuộc tài khoản khác.',
              ),
            ),
          );
        }
        return _Session(item: c);
      },
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(chefConsultationsProvider)),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _Session extends ConsumerStatefulWidget {
  const _Session({required this.item});

  final ConsultationDto item;

  @override
  ConsumerState<_Session> createState() => _SessionState();
}

class _SessionState extends ConsumerState<_Session> {
  final _notes = TextEditingController();
  bool _busy = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(_Session old) {
    super.didUpdateWidget(old);
    _syncClock();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _notes.dispose();
    super.dispose();
  }

  /// "Bắt đầu" unlocks 15 minutes before the appointment: re-check every
  /// 20 s while the screen waits for that moment.
  void _syncClock() {
    final waiting = widget.item.status == ConsultationStatus.confirmed &&
        !ConsultationRules.canStart(widget.item.startAt, DateTime.now());
    if (waiting) {
      _clock ??= Timer.periodic(const Duration(seconds: 20), (_) {
        if (!mounted) return;
        setState(() {});
        if (ConsultationRules.canStart(widget.item.startAt, DateTime.now())) {
          _clock?.cancel();
          _clock = null;
        }
      });
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  Future<void> _act(Future<Object?> Function(ChefStudioApiService api) action,
      String done) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(chefStudioApiProvider));
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

  Future<void> _decline() async {
    final reason = await showDeclineDialog(context);
    if (reason == null || !mounted) return;
    await _act((api) => api.declineConsultation(widget.item.id, reason),
        'Đã từ chối và hoàn tiền cho khách (mô phỏng).');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    final vl = context.vl;
    final now = DateTime.now();
    final buyer = c.buyer?.fullName ?? 'Khách';

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        VLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(name: buyer, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(buyer,
                            style: context.textStyles.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(c.serviceTitle,
                            style: context.textStyles.bodyMedium
                                ?.copyWith(color: vl.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              consultationStatusTag(context, c.status),
              const SizedBox(height: 6),
              InfoRow(label: 'Giờ hẹn', value: formatSlot(c.startAt)),
              InfoRow(label: 'Thời lượng', value: '${c.durationMinutes} phút'),
              InfoRow(label: 'Số tiền', value: formatVnd(c.amount)),
              if (c.buyerNote != null) ...[
                const SizedBox(height: 6),
                Text('“${c.buyerNote}”',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: vl.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        VLCard(child: _Steps(status: c.status)),
        const SizedBox(height: 16),
        ..._stage(context, c, now),
      ],
    );
  }

  List<Widget> _stage(BuildContext context, ConsultationDto c, DateTime now) {
    final vl = context.vl;
    switch (c.status) {
      case ConsultationStatus.pending:
        return [
          FilledButton(
            onPressed: _busy
                ? null
                : () => _act((api) => api.confirmConsultation(c.id),
                    'Đã xác nhận lịch hẹn.'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Xác nhận'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _decline,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: const Text('Từ chối'),
          ),
        ];
      case ConsultationStatus.confirmed:
        final canStart = ConsultationRules.canStart(c.startAt, now);
        return [
          FilledButton.icon(
            onPressed: !canStart || _busy
                ? null
                : () => _act((api) => api.startConsultation(c.id),
                    'Buổi tư vấn đã bắt đầu.'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.video_call_outlined),
            label: Text(_busy ? 'Đang mở…' : 'Bắt đầu buổi tư vấn'),
          ),
          if (!canStart)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Mở trước giờ hẹn 15 phút',
                  textAlign: TextAlign.center,
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted)),
            ),
        ];
      case ConsultationStatus.inProgress:
        final notesOk = ConsultationRules.notes(_notes.text) == null;
        return [
          TextField(
            controller: _notes,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Ghi chú & khuyến nghị cho khách',
              hintText:
                  'Thực đơn gợi ý, món nên tránh, lịch nấu trong tuần… (ít nhất ${ConsultationRules.minNotes} ký tự)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              helperText: 'Khách xem được trong "Lịch tư vấn của tôi".',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: !notesOk || _busy
                ? null
                : () => _act(
                    (api) => api.completeConsultation(c.id, _notes.text.trim()),
                    'Đã hoàn thành buổi tư vấn.'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_busy ? 'Đang lưu…' : 'Hoàn thành buổi tư vấn'),
          ),
        ];
      case ConsultationStatus.completed:
        return [
          Text('Ghi chú đã gửi cho khách',
              style: context.textStyles.titleSmall),
          const SizedBox(height: 6),
          VLCard(
            color: vl.successContainer,
            borderColor: Colors.transparent,
            child: Text(c.chefNotes ?? 'Không có ghi chú.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: vl.onSuccessContainer)),
          ),
          if (c.completedAt != null) ...[
            const SizedBox(height: 6),
            Text('Hoàn thành lúc ${formatStamp(c.completedAt!)}',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
        ];
      case ConsultationStatus.declined:
        return [
          VLCard(
            child: Text(
                'Bạn đã từ chối: ${c.declineReason ?? '—'}\nKhách đã được hoàn tiền (mô phỏng).',
                style: context.textStyles.bodyMedium),
          ),
        ];
      case ConsultationStatus.cancelled:
      case ConsultationStatus.awaitingPayment:
        return [
          VLCard(
            child: Text('Khách đã huỷ lịch hẹn này.',
                style: context.textStyles.bodyMedium),
          ),
        ];
    }
  }
}

/// Vertical stepper: Đã thanh toán → Đã xác nhận → Đang tư vấn → Hoàn thành.
class _Steps extends StatelessWidget {
  const _Steps({required this.status});

  final ConsultationStatus status;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Đã thanh toán',
      'Đã xác nhận',
      'Đang tư vấn',
      'Hoàn thành'
    ];
    final reached = switch (status) {
      ConsultationStatus.awaitingPayment => 0,
      ConsultationStatus.pending ||
      ConsultationStatus.declined ||
      ConsultationStatus.cancelled =>
        1,
      ConsultationStatus.confirmed => 2,
      ConsultationStatus.inProgress => 3,
      ConsultationStatus.completed => 4,
    };
    final stopped = status == ConsultationStatus.declined ||
        status == ConsultationStatus.cancelled;
    final vl = context.vl;
    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  i < reached
                      ? Icons.check_circle_rounded
                      : stopped && i == reached
                          ? Icons.cancel_rounded
                          : i == reached
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: i < reached
                      ? vl.success
                      : stopped && i == reached
                          ? context.colors.error
                          : i == reached
                              ? vl.caution
                              : vl.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stopped && i == reached ? status.label : labels[i],
                    style: context.textStyles.titleSmall
                        ?.copyWith(color: i > reached ? vl.muted : null),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
