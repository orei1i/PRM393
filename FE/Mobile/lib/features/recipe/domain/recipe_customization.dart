// lib/features/recipe/domain/recipe_customization.dart
//
// A cook's changes to a recipe (servings, swaps, removed rows) and what
// follows from them: scaled amounts, energy and macros per serving, the
// allergens left, the shopping list. Pure functions of the recipe and the
// choices, shared by the recipe page (preview) and the mock server (a saved
// variant), so both always agree.
//
// Energy (per serving, C0 = caloriesCache, S = base servings):
//   E = max(0, (C0·S + ΣΔkcal) / S); a swap r→s adds s.kcal − r.kcal, a
//   removal −r.kcal (row figures are for the whole recipe). A side without
//   kcal adds 0 and is named in [RecipeEnergy.unknown] ("≈" + W3). Macros
//   likewise (a missing figure adds 0); a macro the recipe has no figure
//   for stays hidden.
// Allergens (conservative): one is dropped only when every row is
//   annotated, some row listed it and no remaining row (or chosen
//   substitute) lists it; substitutes add theirs.
import '../../../core/utils/energy.dart';
import '../../meal_planner/domain/allergy_match.dart';
import '../../meal_planner/domain/entities/meal_slot.dart';
import 'entities/recipe_detail.dart';
import 'recipe_scaling.dart';

/// The cook's choices on a recipe page. Only choices are kept; everything
/// shown is derived from the loaded recipe ([CustomizedRecipe]).
class RecipeCustomization {
  const RecipeCustomization({
    this.servings,
    this.swaps = const {},
    this.removed = const {},
  });

  /// "Nấu cho N người"; `null` → the recipe's base servings.
  final int? servings;

  /// Row key → substitute key.
  final Map<String, String> swaps;

  /// Keys of the rows left out.
  final Set<String> removed;

  /// Some ingredient changed (servings alone don't count).
  bool get isModified => swaps.isNotEmpty || removed.isNotEmpty;

  /// "Đã chỉnh {k} nguyên liệu".
  int get changeCount => swaps.length + removed.length;

  /// Identifies the swaps and removals (not the servings): a variant saved
  /// for the same key can be reused.
  String get choicesKey {
    final s = swaps.entries.map((e) => '${e.key}>${e.value}').toList()..sort();
    final r = removed.toList()..sort();
    return 's:${s.join(',')};r:${r.join(',')}';
  }

  RecipeCustomization copyWith({
    int? servings,
    bool clearServings = false,
    Map<String, String>? swaps,
    Set<String>? removed,
  }) =>
      RecipeCustomization(
        servings: clearServings ? null : (servings ?? this.servings),
        swaps: swaps ?? this.swaps,
        removed: removed ?? this.removed,
      );
}

/// A change the server would refuse (`POST /recipes/{id}/variants` → 400).
class CustomizationException implements Exception {
  const CustomizationException(this.code, this.message);

  /// `signature_required` | `invalid_substitute` | `invalid_ingredient`.
  final String code;
  final String message;

  @override
  String toString() => 'CustomizationException($code): $message';
}

/// Checks [choices] against [recipe] like the server: swaps must pick a
/// substitute listed for that row; a "Thành phần chính" row can't be left
/// out. `null` when valid.
CustomizationException? validateCustomization(
    RecipeDetail recipe, RecipeCustomization choices) {
  for (final MapEntry(:key, :value) in choices.swaps.entries) {
    final row = recipe.ingredient(key);
    if (row == null || row.substitute(value) == null) {
      return const CustomizationException(
          'invalid_substitute', 'Lựa chọn thay thế không hợp lệ.');
    }
  }
  for (final key in choices.removed) {
    final row = recipe.ingredient(key);
    if (row == null) {
      return const CustomizationException(
          'invalid_ingredient', 'Nguyên liệu không có trong công thức.');
    }
    if (row.isSignature) {
      return CustomizationException('signature_required',
          'Không thể bỏ «${row.name}» — đây là thành phần chính của món.');
    }
  }
  return null;
}

/// One ingredient row as cooked: the original, the substitute chosen for it
/// (if any) or left out, with the amount for the servings cooked.
class CustomizedRow {
  const CustomizedRow({
    required this.original,
    required this.factor,
    this.substitute,
    this.removed = false,
  });

  final RecipeIngredient original;
  final RecipeSubstitute? substitute;
  final bool removed;

  /// N / base servings.
  final double factor;

  bool get isSwapped => substitute != null;

  String get key => original.key;

  /// What is cooked: the substitute's name when swapped.
  String get name => substitute?.name ?? original.name;

  String? get ingredientId =>
      substitute == null ? original.ingredientId : substitute!.ingredientId;

  /// Allergens of what is cooked (`null` = not annotated).
  List<String>? get allergens =>
      substitute == null ? original.allergens : substitute!.allergens;

  /// The amount for the servings cooked ("600 g", "vừa ăn"); empty for a
  /// name-only row.
  String get amount {
    final s = substitute;
    if (s != null) return scaleAmount(s.quantity, s.unit, factor).text;
    if (original.isFreeText) return '';
    return scaleAmount(original.quantity, original.unit, factor).text;
  }
}

/// Energy and macros per serving after the changes.
class RecipeEnergy {
  const RecipeEnergy({
    required this.original,
    required this.exact,
    required this.modified,
    this.unknown = const [],
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
  });

  /// C0: the recipe's kcal per serving (`null` → no energy data).
  final int? original;

  /// E: kcal per serving after the changes, unrounded.
  final double? exact;

  /// Some ingredient changed: figures are shown "≈".
  final bool modified;

  /// Items whose kcal the data doesn't give (their change counted as 0).
  final List<String> unknown;

  /// Per serving, unrounded; `null` when the recipe has no figure.
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;

  /// Whole kcal per serving as shown (`E.round()`).
  int? get shown => exact?.round();

  /// Shown − C0.
  int? get delta {
    final s = shown;
    final c0 = original;
    return s == null || c0 == null ? null : s - c0;
  }

  /// (E − C0) / C0.
  double? get ratio {
    final e = exact;
    final c0 = original;
    return e == null || c0 == null || c0 == 0 ? null : (e - c0) / c0;
  }

  /// kcal for [servings] servings (`E × N` rounded).
  int? totalFor(int servings) {
    final e = exact;
    return e == null ? null : (e * servings).round();
  }

  /// W1: the change is large (≥ 15 % of the original).
  String? get largeChangeWarning {
    final r = ratio;
    if (!modified || r == null || r.abs() < 0.15) return null;
    final pct = (r.abs() * 100).round();
    return 'Năng lượng ${r > 0 ? 'tăng' : 'giảm'} $pct % so với công thức gốc.';
  }

  /// W3: some change has no kcal figure.
  String? get unknownWarning => unknown.isEmpty
      ? null
      : 'Chưa có số liệu dinh dưỡng của «${unknown.join('», «')}» — '
          'năng lượng là ước tính.';

  /// "Đạm 18 g · Tinh bột 90 g · Béo 6 g · Chất xơ 11 g" from the known
  /// macros; `null` when none is known.
  String? get macroLine {
    final parts = [
      if (proteinG != null) 'Đạm ${proteinG!.round()} g',
      if (carbsG != null) 'Tinh bột ${carbsG!.round()} g',
      if (fatG != null) 'Béo ${fatG!.round()} g',
      if (fiberG != null) 'Chất xơ ${fiberG!.round()} g',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// [recipe] with [choices] applied.
class CustomizedRecipe {
  CustomizedRecipe(this.recipe, this.choices) : rows = _rows(recipe, choices) {
    energy = _energy();
    allergens = _allergens();
  }

  final RecipeDetail recipe;
  final RecipeCustomization choices;
  final List<CustomizedRow> rows;
  late final RecipeEnergy energy;

  /// Allergen ids after the changes (conservative, see the file header).
  late final List<String> allergens;

  int get baseServings => recipe.baseServings;

  /// Servings cooked ("Nấu cho N người").
  int get servings => choices.servings ?? baseServings;

  double get factor => servings / baseServings;

  bool get isModified => choices.isModified;

  static List<CustomizedRow> _rows(
      RecipeDetail recipe, RecipeCustomization choices) {
    final factor =
        (choices.servings ?? recipe.baseServings) / recipe.baseServings;
    return [
      for (final row in recipe.ingredients)
        CustomizedRow(
          original: row,
          factor: factor,
          removed: choices.removed.contains(row.key),
          substitute: choices.removed.contains(row.key)
              ? null
              : switch (choices.swaps[row.key]) {
                  final key? => row.substitute(key),
                  null => null,
                },
        ),
    ];
  }

  RecipeEnergy _energy() {
    final c0 = recipe.caloriesCache;
    if (!isModified) {
      return RecipeEnergy(
        original: c0,
        exact: c0?.toDouble(),
        modified: false,
        proteinG: recipe.proteinG,
        carbsG: recipe.carbsG,
        fatG: recipe.fatG,
        fiberG: recipe.fiberG,
      );
    }
    final delta = {for (final n in RecipeNutrient.values) n: 0.0};
    final unknown = <String>[];
    for (final row in rows) {
      final IngredientNutrition? before;
      final IngredientNutrition? after;
      if (row.removed) {
        before = row.original.nutrition;
        after = null;
        if (before?.calories == null) unknown.add(row.original.name);
      } else if (row.substitute case final sub?) {
        before = row.original.nutrition;
        after = sub.nutrition;
        if (after?.calories == null) {
          unknown.add(sub.name);
        } else if (before?.calories == null) {
          unknown.add(row.original.name);
        }
      } else {
        continue;
      }
      for (final n in RecipeNutrient.values) {
        final b = before?.of(n);
        if (b == null) continue;
        if (row.removed) {
          delta[n] = delta[n]! - b;
        } else if (after?.of(n) case final a?) {
          delta[n] = delta[n]! + a - b;
        }
      }
    }
    final s = baseServings;
    double? perServing(num? base, RecipeNutrient n) {
      if (base == null) return null;
      final v = base + delta[n]! / s;
      return v < 0 ? 0 : v;
    }

    return RecipeEnergy(
      original: c0,
      exact: perServing(c0, RecipeNutrient.calories),
      modified: true,
      unknown: unknown,
      proteinG: perServing(recipe.proteinG, RecipeNutrient.protein),
      carbsG: perServing(recipe.carbsG, RecipeNutrient.carbs),
      fatG: perServing(recipe.fatG, RecipeNutrient.fat),
      fiberG: perServing(recipe.fiberG, RecipeNutrient.fiber),
    );
  }

  List<String> _allergens() {
    if (!isModified) return recipe.allergens;
    final annotated = recipe.ingredients.every((i) => i.allergens != null) &&
        rows.every(
            (r) => r.substitute == null || r.substitute!.allergens != null);
    final listed = {
      for (final i in recipe.ingredients) ...?i.allergens,
    };
    final remaining = <String>[
      for (final r in rows)
        if (!r.removed) ...?r.allergens,
    ];
    final result = [
      for (final a in recipe.allergens)
        if (!annotated || !listed.contains(a) || remaining.contains(a)) a,
    ];
    for (final a in remaining) {
      if (!result.contains(a)) result.add(a);
    }
    return result;
  }

  /// The member's allergy keys the dish as cooked conflicts with.
  List<String> allergenConflicts(Iterable<String> userAllergies) =>
      allergyConflicts(
        tags: allergens,
        texts: [
          recipe.name,
          for (final r in rows)
            if (!r.removed) r.name,
        ],
        userAllergies: userAllergies,
      );

  /// The member's allergy keys one row (as cooked) conflicts with.
  static List<String> rowConflicts(
          CustomizedRow row, Iterable<String> userAllergies) =>
      allergyConflicts(
        tags: row.allergens ?? const [],
        texts: [row.name],
        userAllergies: userAllergies,
      );

  /// "Đi chợ: Bún riêu chay (3 người)" then "- Bún tươi: 600 g" per row
  /// cooked (name-only rows: "- Đậu hũ").
  String shoppingList() => [
        'Đi chợ: ${recipe.name} ($servings người)',
        for (final r in rows)
          if (!r.removed)
            r.amount.isEmpty ? '- ${r.name}' : '- ${r.name}: ${r.amount}',
      ].join('\n');

  /// The changes, in row order ("Đã đổi … → …", "Đã bỏ …").
  List<RecipeChangeNote> changeNotes() => [
        for (final r in rows)
          if (r.removed)
            RecipeChangeNote.remove(r.original.name)
          else if (r.substitute case final s?)
            RecipeChangeNote.swap(from: r.original.name, to: s.name),
      ];

  /// The rows a saved variant keeps, at the base servings: removed rows
  /// left out; a swapped row becomes its substitute (keeping key, role and
  /// flags) whose alternatives are the original and the other options.
  List<RecipeIngredient> variantRows() => [
        for (final r in rows)
          if (!r.removed)
            switch (r.substitute) {
              null => r.original,
              final s => _swappedRow(r.original, s),
            },
      ];

  static RecipeIngredient _swappedRow(
          RecipeIngredient row, RecipeSubstitute s) =>
      RecipeIngredient(
        key: row.key,
        name: s.name,
        quantity: s.quantity,
        unit: s.unit,
        ingredientId: s.ingredientId,
        role: row.role,
        isSignature: row.isSignature,
        isOptional: row.isOptional,
        allergens: s.allergens,
        nutrition: s.nutrition,
        substitutes: [
          RecipeSubstitute(
            key: '${row.key}_goc',
            name: row.name,
            quantity: row.quantity,
            unit: row.unit,
            ingredientId: row.ingredientId,
            note: 'Nguyên liệu của công thức gốc',
            allergens: row.allergens,
            nutrition: row.nutrition,
          ),
          for (final o in row.substitutes)
            if (o.key != s.key) o,
        ],
      );
}

/// Per-serving kcal change of picking [sub] for [row] (`null` when either
/// side has no kcal figure).
int? substituteKcalDelta(
    RecipeIngredient row, RecipeSubstitute sub, int baseServings) {
  final a = row.nutrition?.calories;
  final b = sub.nutrition?.calories;
  if (a == null || b == null) return null;
  return ((b - a) / baseServings).round();
}

/// What a substitute means for the member's allergies.
class SubstituteAllergyInfo {
  const SubstituteAllergyInfo({
    this.contains = const [],
    this.conflicts = const [],
    this.avoids = const [],
  });

  /// Allergen ids the substitute is tagged with.
  final List<String> contains;

  /// The member's allergy keys it conflicts with ("Chứa …", caution).
  final List<String> conflicts;

  /// The member's allergy keys the original row has and it avoids
  /// ("Tránh được dị ứng …").
  final List<String> avoids;

  bool get isSafe => conflicts.isEmpty;
}

SubstituteAllergyInfo substituteAllergyInfo(RecipeIngredient row,
    RecipeSubstitute sub, Iterable<String> userAllergies) {
  final conflicts = allergyConflicts(
      tags: sub.allergens ?? const [],
      texts: [sub.name],
      userAllergies: userAllergies);
  final rowConflicts = allergyConflicts(
      tags: row.allergens ?? const [],
      texts: [row.name],
      userAllergies: userAllergies);
  return SubstituteAllergyInfo(
    contains: sub.allergens ?? const [],
    conflicts: conflicts,
    // A tagged allergy is only "avoided" when the substitute is annotated.
    avoids: [
      for (final key in rowConflicts)
        if (!conflicts.contains(key) &&
            (sub.allergens != null || !isDishAllergenId(key)))
          key,
    ],
  );
}

/// The slot whose target the dish is compared with by default: the planner
/// slot the page was opened from, else the slot whose target is closest to
/// the original kcal [originalKcal] (stable while editing).
MealSlot? defaultCompareSlot(Map<MealSlot, int> targets, int? originalKcal,
    {MealSlot? contextSlot}) {
  if (contextSlot != null && targets.containsKey(contextSlot)) {
    return contextSlot;
  }
  if (targets.isEmpty) return null;
  if (originalKcal == null) return targets.keys.first;
  MealSlot? best;
  var bestGap = 0;
  for (final MapEntry(:key, :value) in targets.entries) {
    final gap = (value - originalKcal).abs();
    if (best == null || gap < bestGap) {
      best = key;
      bestGap = gap;
    }
  }
  return best;
}

/// W2: the dish (one serving, [energy] kcal) against a meal's target.
class SlotComparison {
  const SlotComparison(
      {required this.slot, required this.target, required this.energy});

  final MealSlot slot;

  /// The slot's kcal target, unrounded (shown to the nearest 10).
  final int target;
  final double energy;

  /// (E − target) / target.
  double get deviation => (energy - target) / target;

  /// Within ±10 %.
  bool get fits => deviation.abs() <= 0.10;

  /// "≈ 620 kcal".
  String get targetLabel => '≈ ${Energy.formatKcal(target)} kcal';

  String get message {
    final meal = slot.label.toLowerCase();
    final pct = (deviation.abs() * 100).round();
    if (fits) return 'Vừa với mục tiêu $meal ($targetLabel)';
    return deviation > 0
        ? 'Cao hơn mục tiêu $meal $pct % ($targetLabel)'
        : 'Thấp hơn mục tiêu $meal $pct % ($targetLabel)';
  }
}
