// lib/features/meal_planner/domain/entities/plan_adjustment.dart
import '../../../../core/utils/formatters.dart';
import 'meal_plan.dart';

/// Example requests, shown as chips in "Chỉnh thực đơn với AI".
const adjustPlanExamples = [
  'Ít tinh bột hơn cho bữa tối',
  'Thêm một bữa phụ chiều',
  'Thay các món có nấm',
  'Giảm còn 1.600 kcal/ngày',
  'Bữa sáng nhanh dưới 15 phút',
];

/// "Hôm nay" / "Cả tuần" in "Chỉnh thực đơn với AI".
enum AdjustScope {
  day('day', 'Hôm nay'),
  week('week', 'Cả tuần');

  const AdjustScope(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

enum PlanChangeAction {
  add('add'),
  replace('replace'),
  remove('remove');

  const PlanChangeAction(this.apiValue);
  final String apiValue;

  static PlanChangeAction fromApi(String? value) =>
      values.firstWhere((a) => a.apiValue == value, orElse: () => replace);
}

/// One change the AI proposes; applied only if the member keeps it ticked.
class PlanChange {
  const PlanChange({
    required this.id,
    required this.date,
    required this.slot,
    required this.action,
    this.from,
    this.to,
    this.kcalDelta = 0,
  });

  final String id;
  final DateTime date;
  final MealSlot slot;
  final PlanChangeAction action;

  /// The dish now in the slot (`null` for [PlanChangeAction.add]).
  final Recipe? from;

  /// The dish proposed (`null` for [PlanChangeAction.remove]).
  final Recipe? to;
  final int kcalDelta;

  /// "−180 kcal" / "+120 kcal" / "±0 kcal".
  String get kcalLabel => kcalDelta == 0
      ? '±0 kcal'
      : '${kcalDelta > 0 ? '+' : '−'}${formatInt(kcalDelta.abs())} kcal';

  /// "Thứ Năm · Bữa tối: Bò lúc lắc chay → Đậu hũ sốt cà (−180 kcal)".
  String get label {
    final what = switch (action) {
      PlanChangeAction.replace => '${from?.name ?? '—'} → ${to?.name ?? '—'}',
      PlanChangeAction.add => 'Thêm ${to?.name ?? '—'}',
      PlanChangeAction.remove => 'Bỏ ${from?.name ?? '—'}',
    };
    return '${weekdayLong(date)} · ${slot.label}: $what ($kcalLabel)';
  }
}

/// The AI's answer: a short [reply] and the [changes] it proposes (none when
/// it didn't understand or found nothing safe to change).
class PlanAdjustment {
  const PlanAdjustment({
    required this.proposalId,
    required this.reply,
    this.changes = const [],
  });

  final String proposalId;
  final String reply;
  final List<PlanChange> changes;
}
