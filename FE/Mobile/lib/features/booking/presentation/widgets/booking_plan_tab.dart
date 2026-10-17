// lib/features/booking/presentation/widgets/booking_plan_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../controllers/booking_controllers.dart';

/// "Kế hoạch": the plan days. The member sees what was sent (with "Phản hồi
/// ngày này" for DailyFeedback and "Áp dụng kế hoạch vào Thực đơn"); the
/// chef sees drafts too and opens "Soạn kế hoạch".
class BookingPlanTab extends ConsumerWidget {
  const BookingPlanTab({
    super.key,
    required this.booking,
    required this.party,
    required this.busy,
    required this.onFeedback,
    required this.onApply,
    required this.onCompose,
  });

  final BookingDto booking;
  final BookingParty party;
  final bool busy;
  final ValueChanged<PlanDayDto> onFeedback;
  final ValueChanged<List<PlanDayDto>> onApply;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final asChef = party == BookingParty.chef;
    final padding = EdgeInsets.fromLTRB(
        16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom);
    if (b.escrow == null) {
      return ListView(
        padding: padding,
        children: [
          _Info(
            icon: Icons.lock_clock_outlined,
            text: asChef
                ? 'Bạn soạn kế hoạch được sau khi thành viên thanh toán. Tiền được VeganLife giữ đến 3 ngày sau khi kế hoạch kết thúc.'
                : 'Kế hoạch xuất hiện ở đây sau khi bạn thanh toán. Tiền được VeganLife giữ, chỉ chuyển cho chuyên gia 3 ngày sau khi kế hoạch kết thúc nếu bạn không khiếu nại.',
          ),
        ],
      );
    }
    final async = ref.watch(bookingPlanProvider(b.id));
    return switch (async) {
      AsyncValue(:final value?) => ListView(
          padding: padding,
          children: _content(context, value),
        ),
      AsyncError(:final error) => Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(bookingPlanProvider(b.id))),
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  List<Widget> _content(BuildContext context, List<PlanDayDto> days) {
    final b = booking;
    final asChef = party == BookingParty.chef;
    final sent = days.where((d) => d.isSent).toList();
    final editable = asChef &&
        (b.status == BookingStatus.active || b.status == BookingStatus.ended) &&
        sent.length < b.planDays;
    final contract = b.contract;
    return [
      if (asChef && editable)
        FilledButton.icon(
          onPressed: busy ? null : onCompose,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Soạn kế hoạch'),
        ),
      if (!asChef && sent.isNotEmpty)
        FilledButton.tonalIcon(
          onPressed: busy ? null : () => onApply(sent),
          icon: const Icon(Icons.playlist_add_check_rounded),
          label: const Text('Áp dụng kế hoạch vào Thực đơn'),
        ),
      if (!asChef && sent.isEmpty && contract != null)
        _Info(
          icon: Icons.hourglass_top_rounded,
          text:
              'Chuyên gia đang soạn kế hoạch · hạn ${formatVnStamp(contract.deliveryDueAt)}',
        ),
      if (b.bookingType == BookingType.dailyFeedback &&
          sent.length < b.planDays &&
          contract != null) ...[
        const SizedBox(height: 8),
        Text(
          'Có phản hồi mỗi ngày: ngày N được gửi trước ${contract.dailySendCutoff} ngày N; '
          'bạn góp ý trước ${contract.feedbackCutoff} để chuyên gia chỉnh ngày hôm sau.',
          style:
              context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
        ),
      ],
      const SizedBox(height: 8),
      for (final d in asChef ? days : sent)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PlanDayCard(
            day: d,
            showStatus: asChef,
            action: !asChef &&
                    b.bookingType == BookingType.dailyFeedback &&
                    (b.status == BookingStatus.active ||
                        b.status == BookingStatus.ended)
                ? TextButton.icon(
                    onPressed: busy ? null : () => onFeedback(d),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: Text(d.feedback == null
                        ? 'Phản hồi ngày này'
                        : 'Sửa phản hồi'),
                  )
                : null,
          ),
        ),
    ];
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      color: context.vl.aiContainer,
      borderColor: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.vl.onAiContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.onAiContainer)),
          ),
        ],
      ),
    );
  }
}

/// "Ngày 1 · Thứ Hai 20/10": meals per slot, the chef's note and the
/// member's feedback.
class PlanDayCard extends StatelessWidget {
  const PlanDayCard({
    super.key,
    required this.day,
    this.showStatus = false,
    this.action,
  });

  final PlanDayDto day;
  final bool showStatus;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final muted = context.textStyles.bodySmall?.copyWith(color: vl.muted);
    final status = day.status;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(day.title,
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (showStatus)
                StatusPill(
                  label: status?.label ?? 'Chưa soạn',
                  background: status == PlanDayStatus.sent
                      ? vl.successContainer
                      : status == PlanDayStatus.draft
                          ? vl.cautionContainer
                          : context.colors.surfaceContainer,
                  foreground: status == PlanDayStatus.sent
                      ? vl.onSuccessContainer
                      : status == PlanDayStatus.draft
                          ? vl.onCautionContainer
                          : context.colors.onSurfaceVariant,
                ),
            ],
          ),
          if (day.meals.isEmpty) ...[
            const SizedBox(height: 6),
            Text('Chưa có món.', style: muted),
          ],
          for (final m in day.meals) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${m.slot.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: m.recipe.name),
                if (m.recipe.calories != null)
                  TextSpan(
                      text: ' · ${formatInt(m.recipe.calories!)} kcal',
                      style: muted),
              ]),
              style: context.textStyles.bodyMedium,
            ),
            if (m.note != null && m.note!.isNotEmpty)
              Text(m.note!,
                  style: muted?.copyWith(fontStyle: FontStyle.italic)),
          ],
          if (day.calories > 0) ...[
            const SizedBox(height: 6),
            Text('Tổng ≈ ${formatInt(day.calories)} kcal', style: muted),
          ],
          if (day.chefNote != null && day.chefNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Ghi chú của chuyên gia: ${day.chefNote}',
                style: context.textStyles.bodySmall),
          ],
          if (day.feedback != null) ...[
            const SizedBox(height: 8),
            Text('Phản hồi: ${day.feedback!.summary}',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.colors.primary)),
          ],
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}
