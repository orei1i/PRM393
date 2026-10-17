// lib/features/booking/presentation/widgets/booking_ui.dart
//
// Shared bits of the booking screens: VN-time formats, status chips, the
// 5-step progress and the booking card of "Lịch sử tư vấn" / "Yêu cầu tư vấn".
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../../domain/booking_views.dart';

/// "20/10 – 29/10".
String formatDateRange(DateTime start, DateTime end) =>
    '${formatDayMonth(start)} – ${formatDayMonth(end)}';

Widget bookingStatusTag(BuildContext context, BookingStatus status) {
  final vl = context.vl;
  final (Color bg, Color fg) = switch (status) {
    BookingStatus.requested ||
    BookingStatus.negotiating ||
    BookingStatus.awaitingPayment =>
      (vl.cautionContainer, vl.onCautionContainer),
    BookingStatus.active || BookingStatus.ended => (
        vl.aiContainer,
        vl.onAiContainer
      ),
    BookingStatus.completed || BookingStatus.resolved => (
        vl.successContainer,
        vl.onSuccessContainer
      ),
    BookingStatus.disputed || BookingStatus.declined => (
        context.colors.errorContainer,
        context.colors.onErrorContainer
      ),
    BookingStatus.cancelled || BookingStatus.expired => (
        context.colors.surfaceContainer,
        context.colors.onSurfaceVariant
      ),
  };
  return StatusPill(label: status.label, background: bg, foreground: fg);
}

Widget escrowStatusTag(BuildContext context, EscrowStatus status) {
  final vl = context.vl;
  final (Color bg, Color fg) = switch (status) {
    EscrowStatus.held => (vl.cautionContainer, vl.onCautionContainer),
    EscrowStatus.frozen => (
        context.colors.errorContainer,
        context.colors.onErrorContainer
      ),
    EscrowStatus.released => (vl.successContainer, vl.onSuccessContainer),
    EscrowStatus.refunded || EscrowStatus.partiallyRefunded => (
        vl.aiContainer,
        vl.onAiContainer
      ),
  };
  return StatusPill(
      label: status.label,
      icon: Icons.lock_clock_outlined,
      background: bg,
      foreground: fg);
}

/// "Gửi yêu cầu → Thoả thuận giá → Thanh toán → Nhận kế hoạch → Hoàn tất".
/// Wraps at large text sizes instead of overflowing.
class BookingStepper extends StatelessWidget {
  const BookingStepper({super.key, required this.booking});

  final BookingDto booking;

  @override
  Widget build(BuildContext context) {
    final step = bookingStep(booking);
    final stopped = const {
      BookingStatus.declined,
      BookingStatus.cancelled,
      BookingStatus.expired,
    }.contains(booking.status);
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, label) in bookingSteps.indexed) ...[
          if (i > 0)
            Icon(Icons.chevron_right_rounded,
                size: 16, color: context.vl.muted),
          _Step(
            label: label,
            state: i < step
                ? _StepState.done
                : i == step
                    ? (stopped ? _StepState.stopped : _StepState.current)
                    : _StepState.todo,
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, current, stopped, todo }

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final (IconData icon, Color color) = switch (state) {
      _StepState.done => (Icons.check_circle_rounded, vl.success),
      _StepState.current => (
          Icons.radio_button_checked_rounded,
          context.colors.primary
        ),
      _StepState.stopped => (Icons.cancel_rounded, context.colors.error),
      _StepState.todo => (Icons.radio_button_unchecked_rounded, vl.muted),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: context.textStyles.labelMedium?.copyWith(
              color: state == _StepState.todo ? vl.muted : null,
              fontWeight: state == _StepState.current ? FontWeight.w800 : null,
            )),
      ],
    );
  }
}

/// A booking in "Lịch sử tư vấn" ([asChef] = false: the chef is shown) or in
/// "Yêu cầu tư vấn" ([asChef] = true: the member is shown).
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.onTap,
    this.asChef = false,
    this.needsAction = false,
  });

  final BookingDto booking;
  final VoidCallback onTap;
  final bool asChef;

  /// Highlights a booking that waits on the viewer.
  final bool needsAction;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final vl = context.vl;
    final other = asChef ? b.member : b.chef;
    final price = b.price;
    final outcome = asChef ? null : memberOutcome(b);
    final muted = context.textStyles.bodySmall?.copyWith(color: vl.muted);
    final paid = b.escrow != null;
    return VLCard(
      onTap: onTap,
      borderColor: needsAction ? context.colors.primary : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: other.fullName, size: 44, verified: !asChef),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(other.fullName,
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(planSummary(b.planDays, b.bookingType),
                    style: context.textStyles.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  [
                    formatDateRange(b.startDate, b.endDate),
                    if (price != null) formatVnd(price),
                  ].join(' · '),
                  style: muted,
                ),
                if (paid) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${asChef ? 'Đã gửi' : 'Đã nhận'} ${b.deliveredDays}/${b.planDays} ngày',
                    style: muted,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    bookingStatusTag(context, b.status),
                    if (needsAction)
                      StatusPill(
                        label: asChef ? 'Cần bạn xử lý' : 'Chờ bạn',
                        icon: Icons.notifications_active_outlined,
                        background: context.colors.primaryContainer,
                        foreground: context.colors.onPrimaryContainer,
                      ),
                  ],
                ),
                if (outcome != null) ...[
                  const SizedBox(height: 6),
                  Text(outcome,
                      style: context.textStyles.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: vl.muted),
        ],
      ),
    );
  }
}

/// Section title used on the booking screens.
class BookingSectionTitle extends StatelessWidget {
  const BookingSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: context.textStyles.titleMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
