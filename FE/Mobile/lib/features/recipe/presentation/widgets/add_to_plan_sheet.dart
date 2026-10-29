// lib/features/recipe/presentation/widgets/add_to_plan_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/energy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../domain/recipe_customization.dart';

/// Where to put the dish: a day of the current week and a meal.
class AddToPlanChoice {
  const AddToPlanChoice({required this.date, required this.slot});

  final DateTime date;
  final MealSlot slot;
}

/// "T5 30/10".
String planDayLabel(DateTime d) => '${weekdayShort(d)} ${formatDayMonth(d)}';

/// "Thêm vào Thực đơn": pick a day of [plan] and a meal (the member's
/// meals first, then the others as "(bữa thêm)"). One serving goes in.
/// Asks before adding a dish the member is allergic to. `null` when
/// dismissed or "Chọn món khác".
Future<AddToPlanChoice?> showAddToPlanSheet(
  BuildContext context, {
  required MealPlan plan,
  required List<MealSlot> pattern,
  required Map<MealSlot, int> targets,
  required CustomizedRecipe custom,
  required DateTime initialDate,
  required MealSlot initialSlot,
  List<String> allergyConflicts = const [],
}) =>
    showModalBottomSheet<AddToPlanChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddToPlanSheet(
        plan: plan,
        pattern: pattern,
        targets: targets,
        custom: custom,
        initialDate: initialDate,
        initialSlot: initialSlot,
        allergyConflicts: allergyConflicts,
      ),
    );

/// No plan this week: "Bạn chưa có thực đơn tuần này" + "Mở Thực đơn".
/// `true` when the member wants to open Thực đơn.
Future<bool> showNoPlanSheet(BuildContext context) async {
  final open = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Thêm vào Thực đơn',
                style: context.textStyles.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('Bạn chưa có thực đơn tuần này',
                style: context.textStyles.bodyLarge),
            const SizedBox(height: 4),
            Text('Tạo thực đơn tuần trước, rồi thêm món này vào bữa bạn muốn.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Mở Thực đơn'),
            ),
          ],
        ),
      ),
    ),
  );
  return open ?? false;
}

class _AddToPlanSheet extends StatefulWidget {
  const _AddToPlanSheet({
    required this.plan,
    required this.pattern,
    required this.targets,
    required this.custom,
    required this.initialDate,
    required this.initialSlot,
    required this.allergyConflicts,
  });

  final MealPlan plan;
  final List<MealSlot> pattern;
  final Map<MealSlot, int> targets;
  final CustomizedRecipe custom;
  final DateTime initialDate;
  final MealSlot initialSlot;
  final List<String> allergyConflicts;

  @override
  State<_AddToPlanSheet> createState() => _AddToPlanSheetState();
}

class _AddToPlanSheetState extends State<_AddToPlanSheet> {
  late DateTime _date = widget.initialDate;
  late MealSlot _slot = widget.initialSlot;

  Future<void> _confirm() async {
    final navigator = Navigator.of(context);
    if (widget.allergyConflicts.isNotEmpty) {
      final labels = widget.allergyConflicts
          .map((a) => allergenLabel(a).toLowerCase())
          .join(', ');
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Món có chất bạn dị ứng'),
          content: Text('Món này có $labels — bạn đã khai báo dị ứng. '
              'Bạn vẫn muốn thêm vào Thực đơn?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Chọn món khác'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Vẫn thêm'),
            ),
          ],
        ),
      );
      if (go != true) {
        navigator.pop();
        return;
      }
    }
    navigator.pop(AddToPlanChoice(date: _date, slot: _slot));
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final custom = widget.custom;
    final day = widget.plan.dayFor(_date);
    final current = day?.meals[_slot];
    final meal = _slot.label.toLowerCase();
    final alreadyThere =
        !custom.isModified && current != null && current.id == custom.recipe.id;
    final others = [
      for (final s in MealSlot.values)
        if (!widget.pattern.contains(s)) s,
    ];
    final energy = custom.energy.shown;
    final target = widget.targets[_slot];
    final approx = custom.isModified ? '≈ ' : '';

    Widget section(String label) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(label,
              style: context.textStyles.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Thêm vào Thực đơn',
                style: context.textStyles.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            section('Ngày'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in widget.plan.days)
                  ChoiceChip(
                    label: Text(planDayLabel(d.date)),
                    selected: isSameDay(d.date, _date),
                    onSelected: (_) => setState(() => _date = d.date),
                  ),
              ],
            ),
            section('Bữa'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in widget.pattern)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: s == _slot,
                    onSelected: (_) => setState(() => _slot = s),
                  ),
                for (final s in others)
                  ChoiceChip(
                    label: Text('${s.label} (bữa thêm)'),
                    selected: s == _slot,
                    onSelected: (_) => setState(() => _slot = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (energy != null)
              Text(
                'Thực đơn tính 1 phần cho bạn: $approx${formatInt(energy)} kcal'
                '${target == null ? '' : ' · mục tiêu $meal ≈ ${Energy.formatKcal(target)} kcal'}',
                style: context.textStyles.bodyMedium,
              ),
            if (current != null && !alreadyThere) ...[
              const SizedBox(height: 6),
              Text('Đang có: ${current.name} — sẽ được thay',
                  style:
                      context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
            ],
            if (custom.isModified) ...[
              const SizedBox(height: 6),
              Text(
                  'Món đã chỉnh sẽ được lưu vào Công thức của tôi trước khi '
                  'thêm.',
                  style:
                      context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: alreadyThere ? null : _confirm,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: Text(alreadyThere
                  ? 'Món này đã có trong $meal'
                  : 'Thêm vào $meal · ${planDayLabel(_date)}'),
            ),
          ],
        ),
      ),
    );
  }
}
