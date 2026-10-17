// lib/features/meal_planner/domain/entities/meal_slot.dart

/// A meal of the day (`meal_plan_recipes.meal_type`). The member chooses
/// which ones make up their day ("Các bữa trong ngày"); any other slot can be
/// added to a single day ("＋ Thêm bữa").
enum MealSlot {
  breakfast('breakfast', 'Bữa sáng', 25),
  snackAm('snack_am', 'Phụ sáng', 10),
  lunch('lunch', 'Bữa trưa', 35),
  snackPm('snack_pm', 'Phụ chiều', 10),
  dinner('dinner', 'Bữa tối', 30),
  snackLate('snack_late', 'Phụ tối', 8);

  const MealSlot(this.apiValue, this.label, this.kcalWeight);

  final String apiValue;
  final String label;

  /// Relative share of the day's kcal, normalised over the chosen slots.
  final int kcalWeight;

  bool get isSnack =>
      this == MealSlot.snackAm ||
      this == MealSlot.snackPm ||
      this == MealSlot.snackLate;

  static MealSlot? fromApi(String value) {
    for (final slot in values) {
      if (slot.apiValue == value) return slot;
    }
    return null;
  }
}

/// Ready-made "Các bữa trong ngày".
enum MealPatternPreset {
  two('2 bữa', [MealSlot.lunch, MealSlot.dinner]),
  three('3 bữa', [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner]),
  threePlusSnack('3 bữa + 1 phụ', [
    MealSlot.breakfast,
    MealSlot.lunch,
    MealSlot.snackPm,
    MealSlot.dinner,
  ]),
  fiveSmall('5 bữa nhỏ', [
    MealSlot.breakfast,
    MealSlot.snackAm,
    MealSlot.lunch,
    MealSlot.snackPm,
    MealSlot.dinner,
  ]);

  const MealPatternPreset(this.label, this.slots);

  final String label;
  final List<MealSlot> slots;

  /// The preset with exactly these slots, if any.
  static MealPatternPreset? of(Iterable<MealSlot> slots) {
    final set = slots.toSet();
    for (final p in values) {
      if (p.slots.length == set.length && set.containsAll(p.slots)) return p;
    }
    return null;
  }
}

/// Helpers for a meal pattern: the member's slots in day order.
abstract final class MealPattern {
  /// Profiles without a pattern: 3 meals.
  static const standard = [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner];

  /// Day order, no duplicates.
  static List<MealSlot> normalize(Iterable<MealSlot> slots) {
    final set = slots.toSet();
    return [
      for (final s in MealSlot.values)
        if (set.contains(s)) s
    ];
  }

  /// `["breakfast", "lunch"]` or `"breakfast,lunch"`; empty or unknown →
  /// [standard].
  static List<MealSlot> fromApi(Object? value) {
    final raw = switch (value) {
      final List<Object?> list => list.map((e) => '$e'),
      final String csv => csv.split(','),
      _ => const <String>[],
    };
    final slots =
        normalize(raw.map((s) => MealSlot.fromApi(s.trim())).nonNulls);
    return slots.isEmpty ? standard : slots;
  }

  static List<String> toApi(Iterable<MealSlot> slots) =>
      normalize(slots).map((s) => s.apiValue).toList();

  /// "3 bữa + 1 phụ", or "Tuỳ chỉnh · 4 bữa" when it is no preset.
  static String label(Iterable<MealSlot> slots) =>
      MealPatternPreset.of(slots)?.label ?? 'Tuỳ chỉnh · ${slots.length} bữa';

  /// kcal each slot aims at so the day adds up to [dailyKcal].
  static Map<MealSlot, int> kcalTargets(
      Iterable<MealSlot> slots, int dailyKcal) {
    final list = normalize(slots);
    final total = list.fold<int>(0, (sum, s) => sum + s.kcalWeight);
    if (total == 0) return const {};
    return {
      for (final s in list) s: (dailyKcal * s.kcalWeight / total).round(),
    };
  }
}
