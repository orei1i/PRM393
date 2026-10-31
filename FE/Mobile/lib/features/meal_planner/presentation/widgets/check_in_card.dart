// lib/features/meal_planner/presentation/widgets/check_in_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../controllers/body_metrics_controller.dart';
import '../controllers/meal_plan_controller.dart';
import 'check_in_sheet.dart';
import 'progress_review_sheet.dart';

/// Thực đơn, under the health card: "Cập nhật cân nặng" when a weigh-in is
/// due ([checkInPromptProvider]); nothing otherwise. "Để sau" hides it until
/// tomorrow.
class CheckInCard extends ConsumerWidget {
  const CheckInCard({super.key, this.padding = const EdgeInsets.only(top: 8)});

  /// Around the card when it shows.
  final EdgeInsetsGeometry padding;

  /// Compact buttons: the card stays short so the day's first meal is still
  /// on screen under the health card.
  static const _dense = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompt = ref.watch(checkInPromptProvider);
    final profile =
        ref.watch(mealPlanControllerProvider).valueOrNull?.healthProfile;
    if (prompt == null || profile == null) return const SizedBox.shrink();
    final title =
        Text('Cập nhật cân nặng', style: context.textStyles.titleSmall);
    final buttons = [
      TextButton(
        style: _dense,
        onPressed: () => ref.read(checkInPrefsProvider.notifier).snoozeToday(),
        child: const Text('Để sau'),
      ),
      FilledButton(
        style: _dense,
        onPressed: () => CheckInSheet.open(
          context,
          heightCm: profile.heightCm,
          last: ref.read(bodyMeasurementsProvider).valueOrNull?.firstOrNull,
          origin: ReviewOrigin.planner,
        ),
        child: const Text('Cập nhật'),
      ),
    ];
    final icon = Icon(Icons.monitor_weight_outlined,
        size: 20, color: context.colors.primary);
    final message = Padding(
      padding: const EdgeInsets.only(left: 28, right: 6),
      child: Text(prompt.message,
          style: context.textStyles.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant)),
    );
    return Padding(
      padding: padding,
      child: VLCard(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
        color: context.colors.secondaryContainer.withValues(alpha: 0.5),
        borderColor: context.colors.primary.withValues(alpha: 0.35),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Title and buttons on one line when there is room (a phone at
            // the default text size), else the buttons go under the text.
            final oneLine = constraints.maxWidth >= 330 &&
                MediaQuery.textScalerOf(context).scale(14) <= 15.4;
            if (oneLine) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Expanded(child: title),
                      buttons[0],
                      const SizedBox(width: 4),
                      buttons[1],
                    ],
                  ),
                  const SizedBox(height: 2),
                  message,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Row(
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Expanded(child: title),
                    ],
                  ),
                ),
                message,
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    runSpacing: 4,
                    children: buttons,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
