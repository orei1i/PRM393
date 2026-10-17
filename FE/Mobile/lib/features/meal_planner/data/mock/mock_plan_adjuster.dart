// lib/features/meal_planner/data/mock/mock_plan_adjuster.dart
//
// What the server's "Chỉnh thực đơn với AI" does, with keyword rules instead
// of a model: it reads the request (accents ignored), proposes changes and
// never applies them itself. Every dish it proposes is vegan and free of the
// member's allergies (tagged ids and free-text names alike).
import '../../../../core/utils/formatters.dart';
import '../../../scanner/domain/vegan_check.dart';
import '../../domain/allergy_match.dart';
import '../../domain/entities/meal_slot.dart';
import '../../domain/entities/plan_adjustment.dart';
import '../models/meal_plan_model.dart';

class MockPlanAdjuster {
  MockPlanAdjuster({
    required this.plan,
    required this.pattern,
    required this.allergies,
    required this.today,
    required this.poolFor,
    required this.dailyKcal,
  });

  final MealPlanDto plan;
  final List<MealSlot> pattern;
  final List<String> allergies;
  final DateTime today;
  final int dailyKcal;

  /// Every catalogue dish that fits [slot].
  final List<RecipeDto> Function(MealSlot slot) poolFor;

  final List<PlanChangeDto> _changes = [];
  final Set<String> _used = {};

  bool _safe(RecipeDto r) =>
      allergyConflicts(
              tags: r.allergens, texts: [r.name], userAllergies: allergies)
          .isEmpty &&
      classifyVegan(r.name).isVegan;

  PlanAdjustmentDto propose(AdjustPlanRequestDto request, String proposalId) {
    final text = allergyText(request.message);
    bool has(String word) => text.contains(' $word ');
    final days = _daysInScope(request);
    final scopeLabel = request.scope == AdjustScope.day ? 'hôm nay' : 'cả tuần';

    final kcalMatch =
        RegExp(r'(\d[\d.,]*)\s*kcal').firstMatch(request.message.toLowerCase());
    final kcal = kcalMatch == null
        ? null
        : int.tryParse(kcalMatch.group(1)!.replaceAll(RegExp(r'[.,]'), ''));

    String? lead;
    String? noChange;
    if (kcal != null && kcal >= 1000 && kcal <= 4000) {
      lead = 'Mình đổi sang món nhẹ hơn để còn khoảng '
          '${formatInt(kcal)} kcal/ngày';
      noChange = 'Thực đơn $scopeLabel đã ở khoảng ${formatInt(kcal)} '
          'kcal/ngày hoặc thấp hơn, chưa cần đổi.';
      for (final day in days) {
        _reduceTo(day, kcal);
      }
    } else if (has('tinh bot') || has('carb')) {
      final slot = _slotIn(text, fallback: MealSlot.dinner);
      lead = 'Mình chọn món ít tinh bột hơn cho ${slot.label.toLowerCase()}';
      for (final day in days) {
        _replace(day, slot,
            accept: (cur, r) =>
                (r.nutrition.carbsG ?? double.infinity) <
                (cur.nutrition.carbsG ?? 0) - 5,
            rank: (r) => r.nutrition.carbsG ?? double.infinity);
      }
    } else if (has('nam') &&
        (has('thay') || has('bo') || has('khong') || has('tranh'))) {
      lead = 'Mình thay các món có nấm bằng món khác cùng bữa';
      for (final day in days) {
        for (final entry in day.meals.entries.toList()) {
          final slot = MealSlot.fromApi(entry.key);
          if (slot == null || !mentionsAllergy('nấm', [entry.value.name])) {
            continue;
          }
          _replace(day, slot,
              accept: (_, r) => !mentionsAllergy('nấm', [r.name]));
        }
      }
    } else if (has('nhanh') || has('phut')) {
      final minutes = int.tryParse(
              RegExp(r'(\d+)\s*phut').firstMatch(text)?.group(1) ?? '') ??
          15;
      final slot = _slotIn(text, fallback: MealSlot.breakfast);
      lead = 'Mình chọn ${slot.label.toLowerCase()} làm nhanh dưới '
          '$minutes phút';
      for (final day in days) {
        final cur = day.meals[slot.apiValue];
        if (cur == null || (cur.prepMinutes ?? 0) <= minutes) continue;
        _replace(day, slot,
            accept: (_, r) =>
                r.prepMinutes != null && r.prepMinutes! <= minutes);
      }
    } else if ((has('them') || has('bo sung')) &&
        (has('phu') || has('an vat'))) {
      final slot = has('sang')
          ? MealSlot.snackAm
          : (has('toi') || has('khuya'))
              ? MealSlot.snackLate
              : MealSlot.snackPm;
      lead = 'Mình thêm ${slot.label.toLowerCase()} nhẹ nhàng';
      noChange = 'Thực đơn $scopeLabel đã có ${slot.label.toLowerCase()} '
          'rồi. Bạn muốn đổi món thì chạm nút đổi ở bữa đó nhé.';
      final target =
          MealPattern.kcalTargets({...pattern, slot}, dailyKcal)[slot] ?? 200;
      for (final day in days) {
        if (day.meals.containsKey(slot.apiValue)) continue;
        final pick = _best(slot, day,
            accept: (_) => true,
            rank: (r) => (r.nutrition.calories - target).abs().toDouble());
        if (pick == null) continue;
        _add(PlanChangeDto(
          id: '',
          date: day.date,
          slot: slot.apiValue,
          action: PlanChangeAction.add.apiValue,
          to: pick,
          kcalDelta: pick.nutrition.calories,
        ));
      }
    } else if (has('bo') && has('phu')) {
      lead = 'Mình bỏ các bữa phụ';
      for (final day in days) {
        for (final slot in MealSlot.values.where((s) => s.isSnack)) {
          final cur = day.meals[slot.apiValue];
          if (cur == null) continue;
          _add(PlanChangeDto(
            id: '',
            date: day.date,
            slot: slot.apiValue,
            action: PlanChangeAction.remove.apiValue,
            from: cur,
            kcalDelta: -cur.nutrition.calories,
          ));
        }
      }
    }

    if (lead == null) {
      return PlanAdjustmentDto(
        proposalId: proposalId,
        reply: 'Mình chưa hiểu yêu cầu. Bạn thử: “${adjustPlanExamples[0]}”, '
            '“${adjustPlanExamples[1]}” hoặc “${adjustPlanExamples[2]}”.',
      );
    }
    if (_changes.isEmpty) {
      return PlanAdjustmentDto(
        proposalId: proposalId,
        reply: noChange ??
            'Mình chưa tìm được thay đổi nào vừa thuần chay vừa tránh được '
                'chất bạn dị ứng cho yêu cầu này.',
      );
    }
    return PlanAdjustmentDto(
      proposalId: proposalId,
      reply: '$lead: ${_changes.length} thay đổi cho $scopeLabel. Bỏ chọn '
          'những gì bạn muốn giữ, rồi bấm “Áp dụng thay đổi”.',
      changes: _changes,
    );
  }

  // ---------------------------------------------------------------------------

  List<MealPlanDayDto> _daysInScope(AdjustPlanRequestDto request) {
    final sorted = [...plan.days]..sort((a, b) => a.date.compareTo(b.date));
    if (request.scope == AdjustScope.day) {
      return sorted.where((d) => isSameDay(d.date, request.date)).toList();
    }
    final ahead =
        sorted.where((d) => !d.date.isBefore(dateOnly(today))).toList();
    return ahead.isEmpty ? sorted : ahead;
  }

  static MealSlot _slotIn(String text, {required MealSlot fallback}) {
    if (text.contains(' toi ')) return MealSlot.dinner;
    if (text.contains(' trua ')) return MealSlot.lunch;
    if (text.contains(' sang ')) return MealSlot.breakfast;
    return fallback;
  }

  void _add(PlanChangeDto change) {
    _changes.add(PlanChangeDto(
      id: 'c${_changes.length + 1}',
      date: change.date,
      slot: change.slot,
      action: change.action,
      from: change.from,
      to: change.to,
      kcalDelta: change.kcalDelta,
    ));
    if (change.to case final to?) _used.add(to.id);
  }

  /// The best safe dish for [slot] that isn't already on [day]; dishes not
  /// yet proposed this time come first.
  RecipeDto? _best(
    MealSlot slot,
    MealPlanDayDto day, {
    required bool Function(RecipeDto) accept,
    required double Function(RecipeDto) rank,
    double portion = 1,
  }) {
    final onDay = day.meals.values.map((r) => r.id).toSet();
    final options = poolFor(slot)
        .map((r) => r.scaled(portion))
        .where((r) => !onDay.contains(r.id) && _safe(r) && accept(r))
        .toList()
      ..sort((a, b) {
        final fresh = (_used.contains(a.id) ? 1 : 0)
            .compareTo(_used.contains(b.id) ? 1 : 0);
        return fresh != 0 ? fresh : rank(a).compareTo(rank(b));
      });
    return options.firstOrNull;
  }

  /// Proposes replacing [slot] of [day] with the best accepted dish (same
  /// portion size); nothing when the slot is empty or no dish fits.
  void _replace(
    MealPlanDayDto day,
    MealSlot slot, {
    required bool Function(RecipeDto current, RecipeDto candidate) accept,
    double Function(RecipeDto)? rank,
  }) {
    final cur = day.meals[slot.apiValue];
    if (cur == null) return;
    final pick = _best(slot, day,
        portion: cur.portion,
        accept: (r) => accept(cur, r),
        rank: rank ??
            (r) => (r.nutrition.calories - cur.nutrition.calories)
                .abs()
                .toDouble());
    if (pick == null) return;
    _add(PlanChangeDto(
      id: '',
      date: day.date,
      slot: slot.apiValue,
      action: PlanChangeAction.replace.apiValue,
      from: cur,
      to: pick,
      kcalDelta: pick.nutrition.calories - cur.nutrition.calories,
    ));
  }

  /// Swaps the heaviest dishes of [day] for lighter ones until the day is
  /// within 3 % of [kcal].
  void _reduceTo(MealPlanDayDto day, int kcal) {
    var total =
        day.meals.values.fold<int>(0, (s, r) => s + r.nutrition.calories);
    final slots = day.meals.entries.toList()
      ..sort((a, b) =>
          b.value.nutrition.calories.compareTo(a.value.nutrition.calories));
    for (final entry in slots) {
      final excess = total - kcal;
      if (excess <= kcal * 0.03) break;
      final slot = MealSlot.fromApi(entry.key);
      if (slot == null) continue;
      final cur = entry.value;
      final pick = _best(slot, day,
          portion: cur.portion > 1 ? 1 : cur.portion,
          accept: (r) => r.nutrition.calories < cur.nutrition.calories,
          rank: (r) =>
              ((cur.nutrition.calories - r.nutrition.calories) - excess)
                  .abs()
                  .toDouble());
      if (pick == null) continue;
      final delta = pick.nutrition.calories - cur.nutrition.calories;
      _add(PlanChangeDto(
        id: '',
        date: day.date,
        slot: slot.apiValue,
        action: PlanChangeAction.replace.apiValue,
        from: cur,
        to: pick,
        kcalDelta: delta,
      ));
      total += delta;
    }
  }
}
