// lib/features/recipe/domain/recipe_scaling.dart
//
// "Nấu cho N người": ingredient amounts for N servings when the recipe is
// written for `base`. Only the amounts change (the energy per serving does
// not). Rounding depends on what the unit can be measured in:
//
// | Class      | Units                                   | Rounding of v = q × f                 | Min |
// |------------|-----------------------------------------|---------------------------------------|-----|
// | Mass       | g, gr, gram, kg                         | grams: <10 → 0,5 · <100 → 1 · <1000 → 5; ≥1000 → kg, 0,05 | 0,5 g |
// | Volume     | ml, l, lít                              | same steps in ml; ≥1000 → lít, 0,05   | 0,5 ml |
// | Whole-only | tép, lá, nhánh, lát, cây, cái, miếng, ổ, hũ, hộp, gói, viên | half up to an integer | 1 |
// | Halvable   | quả, trái, củ, bắp, bông, bó, nắm, chén, bìa, ly, cốc | nearest 0,5            | 0,5 |
// | Spoon      | muỗng canh, muỗng cà phê, thìa, thìa canh, thìa cà phê | nearest 0,5           | 0,5 |
// | Other      | anything else                           | <10 → 0,5; else integer               | 0,5 |
//
// Rows without a quantity keep their text ("vừa ăn").
import 'entities/recipe_detail.dart';

/// Servings the "Nấu cho" stepper allows.
const minServings = 1;
const maxServings = 20;

const _massToGrams = {'g': 1.0, 'gr': 1.0, 'gram': 1.0, 'kg': 1000.0};
const _volumeToMl = {'ml': 1.0, 'l': 1000.0, 'lít': 1000.0};
const _wholeUnits = {
  'tép',
  'lá',
  'nhánh',
  'lát',
  'cây',
  'cái',
  'miếng',
  'ổ',
  'hũ',
  'hộp',
  'gói',
  'viên',
};
const _halvableUnits = {
  'quả',
  'trái',
  'củ',
  'bắp',
  'bông',
  'bó',
  'nắm',
  'chén',
  'bìa',
  'ly',
  'cốc',
};
const _spoonUnits = {
  'muỗng canh',
  'muỗng cà phê',
  'thìa',
  'thìa canh',
  'thìa cà phê',
};

/// An amount after scaling: a quantity in [unit] (`null` → [unit] is a text
/// such as "vừa ăn").
class ScaledAmount {
  const ScaledAmount(this.quantity, this.unit);

  final double? quantity;
  final String unit;

  /// "600 g", "1,05 kg", "1,5 củ", "vừa ăn".
  String get text => formatAmount(quantity, unit);
}

/// [quantity] [unit] for [factor] × the base servings (`factor` = N / base).
/// A factor of 1 returns the amount exactly as written.
ScaledAmount scaleAmount(double? quantity, String unit, double factor) {
  final q = quantity;
  if (q == null || q <= 0 || factor == 1) return ScaledAmount(q, unit);
  final u = unit.trim().toLowerCase();
  final v = q * factor;

  if (_massToGrams[u] case final toGrams?) {
    return _metric(v * toGrams, small: 'g', large: 'kg');
  }
  if (_volumeToMl[u] case final toMl?) {
    return _metric(v * toMl, small: 'ml', large: 'lít');
  }
  if (_wholeUnits.contains(u)) {
    final n = v.round();
    return ScaledAmount(n < 1 ? 1 : n.toDouble(), unit);
  }
  if (_halvableUnits.contains(u) || _spoonUnits.contains(u)) {
    return ScaledAmount(_atLeast(_roundTo(v, 0.5), 0.5), unit);
  }
  final other = v < 10 ? _roundTo(v, 0.5) : v.roundToDouble();
  return ScaledAmount(_atLeast(other, 0.5), unit);
}

/// Grams (or ml) [v] rounded by size; 1000 and above in kg (or lít).
ScaledAmount _metric(double v, {required String small, required String large}) {
  if (v < 1000) {
    final step = v < 10
        ? 0.5
        : v < 100
            ? 1.0
            : 5.0;
    final rounded = _atLeast(_roundTo(v, step), 0.5);
    if (rounded < 1000) return ScaledAmount(rounded, small);
  }
  return ScaledAmount(_roundTo(v / 1000, 0.05), large);
}

double _roundTo(double v, double step) =>
    double.parse(((v / step).round() * step).toStringAsFixed(3));

double _atLeast(double v, double min) => v < min ? min : v;
