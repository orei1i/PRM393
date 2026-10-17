// lib/features/ingredient/domain/entities/ingredient.dart
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/text_search.dart';

/// Shown under nutrition figures.
const nutritionDisclaimer =
    'Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế.';

/// Where the reference figures come from (when the server doesn't say).
const nutritionSourceNote =
    'Tham khảo: Bảng thành phần thực phẩm Việt Nam / USDA FoodData Central';

/// `ingredients.category`, with the filter label used in "Nguyên liệu trong
/// tủ".
enum IngredientCategory {
  leafy('leafy', 'Rau lá'),
  veg('veg', 'Rau củ quả'),
  mushroom('mushroom', 'Nấm'),
  plantProtein('plant_protein', 'Đạm thực vật'),
  grain('grain', 'Ngũ cốc'),
  nutSeed('nut_seed', 'Hạt'),
  fruit('fruit', 'Trái cây'),
  spice('spice', 'Gia vị'),
  plantMilk('plant_milk', 'Sữa thực vật');

  const IngredientCategory(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static IngredientCategory? fromApi(String? value) {
    for (final c in values) {
      if (c.apiValue == value) return c;
    }
    return null;
  }
}

/// A row of the nutrition DB, enough for a list: name, category and energy.
class IngredientSummary {
  const IngredientSummary({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    this.category,
    this.aliases = const [],
    this.altServingLabel,
    this.altServingGrams,
    this.isVegan = true,
  });

  final String id;
  final String name;
  final IngredientCategory? category;

  /// Other names people type ("lạc" for "Đậu phộng").
  final List<String> aliases;
  final int caloriesPer100g;

  /// "1 quả", "1 bìa"… with its weight.
  final String? altServingLabel;
  final double? altServingGrams;
  final bool isVegan;

  /// kcal of [altServingLabel], rounded.
  int? get altServingCalories => altServingGrams == null
      ? null
      : (caloriesPer100g * altServingGrams! / 100).round();

  /// "18 kcal / 100 g · 1 quả ≈ 22 kcal".
  String get energyLine => energyLineOf(
      caloriesPer100g: caloriesPer100g,
      altLabel: altServingLabel,
      altCalories: altServingCalories);
}

/// "18 kcal / 100 g · 1 quả ≈ 22 kcal" (the second part when known).
String energyLineOf(
    {required int caloriesPer100g, String? altLabel, int? altCalories}) {
  final base = '${formatInt(caloriesPer100g)} kcal / 100 g';
  if (altLabel == null || altCalories == null) return base;
  return '$base · $altLabel ≈ ${formatInt(altCalories)} kcal';
}

/// A vitamin or mineral per 100 g, with its share of the daily value.
class Micronutrient {
  const Micronutrient({
    required this.name,
    required this.amount,
    required this.unit,
    this.dvPercent,
  });

  final String name;
  final double amount;
  final String unit;

  /// % of the daily value (FDA reference); `null` when there is none.
  final int? dvPercent;
}

/// "Không nên dùng chung": another food and why (reference only).
class IngredientPairing {
  const IngredientPairing({required this.name, required this.reason});

  final String name;
  final String reason;
}

/// A catalogue recipe that uses the ingredient.
class IngredientRecipe {
  const IngredientRecipe({required this.id, required this.name, this.calories});

  final String id;
  final String name;
  final int? calories;
}

/// Everything the detail screen shows. Values are per 100 g; a value the
/// source doesn't give stays `null` and is not shown.
class IngredientDetail {
  const IngredientDetail({
    required this.summary,
    this.proteinG,
    this.fatG,
    this.carbsG,
    this.fiberG,
    this.sugarG,
    this.micronutrients = const [],
    this.goodFor = const [],
    this.cautionFor = const [],
    this.avoidCombining = const [],
    this.suggestedDishes = const [],
    this.recipes = const [],
    this.allergenIds = const [],
    this.source,
  });

  final IngredientSummary summary;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;
  final double? fiberG;
  final double? sugarG;
  final List<Micronutrient> micronutrients;

  /// "Phù hợp với".
  final List<String> goodFor;

  /// "Cần lưu ý / Không phù hợp với".
  final List<String> cautionFor;
  final List<IngredientPairing> avoidCombining;

  /// "Món gợi ý": dish ideas.
  final List<String> suggestedDishes;

  /// "Công thức có nguyên liệu này".
  final List<IngredientRecipe> recipes;

  /// Allergen ids it contains (`soy` for đậu hũ).
  final List<String> allergenIds;

  /// "Tham khảo: Bảng thành phần thực phẩm Việt Nam / USDA FoodData Central".
  final String? source;

  String get id => summary.id;
  String get name => summary.name;
}

/// The DB row a free-text name refers to: the same id, else the same name or
/// alias (accents and case ignored), else the longest name or alias found as
/// whole words inside it ("Rau muống chẻ" → Rau muống). Names of 3 letters
/// or fewer keep their accents there ("lạc" is not "lắc", "bơ" not "bò").
IngredientSummary? findIngredient(Iterable<IngredientSummary> index,
    {String? id, required String name}) {
  if (id != null) {
    for (final i in index) {
      if (i.id == id) return i;
    }
  }
  String norm(String s) =>
      ' ${foldVietnamese(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  String words(String s) =>
      ' ${s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).join(' ')} ';
  final target = norm(name);
  if (target.trim().isEmpty) return null;
  final accented = words(name);
  IngredientSummary? best;
  var bestLength = 0;
  for (final i in index) {
    for (final term in [i.name, ...i.aliases]) {
      final t = norm(term);
      if (t == target) return i;
      final length = t.trim().length;
      if (length <= bestLength) continue;
      final found =
          length <= 3 ? accented.contains(words(term)) : target.contains(t);
      if (found) {
        best = i;
        bestLength = length;
      }
    }
  }
  return best;
}
