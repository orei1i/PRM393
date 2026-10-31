// lib/features/meal_planner/presentation/widgets/progress_review_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_nav.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/body_progress.dart';
import '../screens/body_metrics_screen.dart';

/// Where "Cập nhật cân nặng" was started, which decides the review's
/// buttons.
enum ReviewOrigin {
  /// Thực đơn's check-in card: "Về Thực đơn" just closes the review.
  planner,

  /// "Theo dõi cân nặng": no "Xem lịch sử" (already there), "Xong".
  metricsScreen,

  /// Anywhere else: "Về Thực đơn" switches to the tab.
  other,
}

/// "Tiến độ của bạn": the new weigh-in against the previous one, a verdict
/// for the profile goal and, when losing fast, a caution.
class ProgressReviewSheet extends ConsumerWidget {
  const ProgressReviewSheet(
      {super.key, required this.review, required this.origin});

  final ProgressReview review;
  final ReviewOrigin origin;

  static Future<void> show(BuildContext context, ProgressReview review,
          {required ReviewOrigin origin}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ProgressReviewSheet(review: review, origin: origin),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final verdict = review.verdict;
    final onMetrics = origin == ReviewOrigin.metricsScreen;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tiến độ của bạn', style: context.textStyles.titleLarge),
            const SizedBox(height: 4),
            Text(review.subtitle,
                style:
                    context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
            const SizedBox(height: 16),
            _ReviewRow(
                icon: Icons.monitor_weight_outlined, text: review.weightRow),
            _ReviewRow(icon: Icons.speed_rounded, text: review.bmiRow),
            if (review.waistRow case final waist?) ...[
              _ReviewRow(icon: Icons.straighten_rounded, text: waist),
              if (review.waistCaution)
                Padding(
                  padding: const EdgeInsets.only(left: 30, bottom: 8),
                  child: MetricPill.tone(context, BodyProgress.whtrCautionLabel,
                      VerdictTone.caution),
                ),
            ],
            if (review.bodyFatRow case final fat?)
              _ReviewRow(icon: Icons.water_drop_outlined, text: fat),
            if (review.energyRow case final energy?)
              _ReviewRow(
                  icon: Icons.local_fire_department_outlined, text: energy),
            if (verdict != null) ...[
              const SizedBox(height: 4),
              MetricPill.tone(context, verdict.label, verdict.tone),
            ],
            if (review.fastLoss) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: vl.cautionContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: vl.cautionBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: vl.onCautionContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(BodyProgress.fastLossMessage,
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: vl.onCautionContainer)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(BodyProgress.disclaimer,
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!onMetrics) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        AppNav.open(navigator, BodyMetricsScreen.route());
                      },
                      child: const Text('Xem lịch sử'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      if (origin == ReviewOrigin.other) {
                        AppNav.toShellTab(navigator, ref, ShellTab.planner);
                      } else {
                        navigator.pop();
                      }
                    },
                    child: Text(onMetrics ? 'Xong' : 'Về Thực đơn'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.textStyles.bodyLarge)),
        ],
      ),
    );
  }
}

/// Rounded label that wraps at large text sizes (verdicts, WHtR caution,
/// history chips).
class MetricPill extends StatelessWidget {
  const MetricPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  factory MetricPill.tone(
      BuildContext context, String label, VerdictTone tone) {
    final vl = context.vl;
    return switch (tone) {
      VerdictTone.good => MetricPill(
          label: label,
          icon: Icons.check_circle_outline_rounded,
          background: vl.successContainer,
          foreground: vl.onSuccessContainer,
        ),
      VerdictTone.neutral => MetricPill(
          label: label,
          icon: Icons.trending_flat_rounded,
          background: context.colors.surfaceContainer,
          foreground: context.colors.onSurfaceVariant,
        ),
      VerdictTone.caution => MetricPill(
          label: label,
          icon: Icons.warning_amber_rounded,
          background: vl.cautionContainer,
          foreground: vl.onCautionContainer,
        ),
    };
  }

  /// Plain grey label ("Từ Hồ sơ sức khoẻ", "Mỡ 26,2 %").
  factory MetricPill.neutral(BuildContext context, String label) => MetricPill(
        label: label,
        background: context.colors.surfaceContainer,
        foreground: context.colors.onSurfaceVariant,
      );

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
