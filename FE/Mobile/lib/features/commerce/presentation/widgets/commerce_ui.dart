// lib/features/commerce/presentation/widgets/commerce_ui.dart
//
// Shared bits for the buyer and chef commerce screens: date formats and the
// status / type chips.
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../domain/commerce_status.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// "19:30"
String formatClock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "17/10/2026"
String formatFullDate(DateTime d) => '${formatDayMonth(d)}/${d.year}';

/// "T5, 17/10 · 19:30" (appointments).
String formatSlot(DateTime d) =>
    '${weekdayShort(d)}, ${formatDayMonth(d)} · ${formatClock(d)}';

/// "19:30, 17/10/2026" (payments, grants).
String formatStamp(DateTime d) => '${formatClock(d)}, ${formatFullDate(d)}';

enum _Tone { success, caution, error, neutral, ai }

Widget _tag(BuildContext context, String label, _Tone tone, {IconData? icon}) {
  final vl = context.vl;
  final (Color bg, Color fg) = switch (tone) {
    _Tone.success => (vl.successContainer, vl.onSuccessContainer),
    _Tone.caution => (vl.cautionContainer, vl.onCautionContainer),
    _Tone.error => (
        context.colors.errorContainer,
        context.colors.onErrorContainer
      ),
    _Tone.ai => (vl.aiContainer, vl.onAiContainer),
    _Tone.neutral => (
        context.colors.surfaceContainer,
        context.colors.onSurfaceVariant
      ),
  };
  return StatusPill(label: label, icon: icon, background: bg, foreground: fg);
}

/// Like `VLTag`, but a long label wraps instead of overflowing (large text,
/// "Đã duyệt · AI đang dùng · 18 đoạn").
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                style: context.textStyles.labelMedium
                    ?.copyWith(color: foreground)),
          ),
        ],
      ),
    );
  }
}

Widget orderStatusTag(BuildContext context, OrderStatus status) => _tag(
    context,
    status.label,
    switch (status) {
      OrderStatus.pending => _Tone.caution,
      OrderStatus.paid => _Tone.success,
      OrderStatus.cancelled => _Tone.neutral,
      OrderStatus.refunded => _Tone.ai,
    });

Widget paymentStatusTag(BuildContext context, PaymentStatus status) => _tag(
    context,
    status.label,
    switch (status) {
      PaymentStatus.pending => _Tone.caution,
      PaymentStatus.paid => _Tone.success,
      PaymentStatus.failed => _Tone.error,
      PaymentStatus.expired => _Tone.neutral,
      PaymentStatus.refunded => _Tone.ai,
    });

Widget grantStatusTag(BuildContext context, GrantStatus status) => _tag(
    context,
    status.label,
    switch (status) {
      GrantStatus.active => _Tone.success,
      GrantStatus.expired => _Tone.neutral,
      GrantStatus.revoked => _Tone.error,
    });

Widget consultationStatusTag(BuildContext context, ConsultationStatus status) =>
    _tag(
        context,
        status.label,
        switch (status) {
          ConsultationStatus.awaitingPayment ||
          ConsultationStatus.pending =>
            _Tone.caution,
          ConsultationStatus.confirmed ||
          ConsultationStatus.completed =>
            _Tone.success,
          ConsultationStatus.inProgress => _Tone.ai,
          ConsultationStatus.declined => _Tone.error,
          ConsultationStatus.cancelled => _Tone.neutral,
        });

Widget serviceTypeTag(BuildContext context, ServiceType type) => _tag(
      context,
      type.label,
      _Tone.neutral,
      icon: switch (type) {
        ServiceType.consult => Icons.videocam_outlined,
        ServiceType.course => Icons.school_outlined,
        ServiceType.vipMenu => Icons.restaurant_menu_rounded,
      },
    );

/// Label + value line used in detail blocks; wraps instead of overflowing
/// at large text sizes.
class InfoRow extends StatelessWidget {
  const InfoRow(
      {super.key, required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(label,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted)),
                Text(value,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Shimmering placeholder cards for list screens.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.count = 3, this.height = 96});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Shimmer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (var i = 0; i < count; i++) ...[
                SkeletonBox(height: height, radius: 16),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
