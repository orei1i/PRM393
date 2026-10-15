// lib/features/scanner/domain/entities/detected_ingredient.dart

import '../vegan_check.dart';

/// Box in 0…1 coordinates of the analysed frame (top-left origin).
class NormalizedBox {
  const NormalizedBox(
      {required this.left,
      required this.top,
      required this.width,
      required this.height});

  final double left;
  final double top;
  final double width;
  final double height;
}

class IngredientAlternative {
  const IngredientAlternative(
      {required this.name, required this.confidence, this.isVegan});

  final String name;
  final double confidence;

  /// Server's vegan flag for this candidate; `null` → local check.
  final bool? isVegan;
}

/// One food seen in the fridge. Confirm-only on purpose: the scan says
/// *what* is there (name, how sure the model is) and whether it is vegan,
/// never how much, matching `user_ingredients`, which has no quantity. Only
/// vegan items can be saved to the fridge.
class DetectedIngredient {
  const DetectedIngredient({
    required this.id,
    required this.name,
    required this.confidence,
    required this.isVegan,
    this.nonVeganReason,
    this.veganAlternatives = const [],
    this.box,
    this.alternatives = const [],
    this.confirmed = true,
    this.manual = false,
    this.userVerified = false,
  });

  /// Below this the item enters the tray unconfirmed (dashed, needs a tap).
  static const double confirmThreshold = 0.7;

  final String id;
  final String name;
  final double confidence;

  /// Thuần chay? Server's `isVegan`, or the local check ([classifyVegan]).
  final bool isVegan;

  /// "Có nguồn gốc động vật: trứng"… only when not vegan.
  final String? nonVeganReason;

  /// Vegan swaps to suggest ("Đậu hũ non"); only when not vegan.
  final List<String> veganAlternatives;
  final NormalizedBox? box;
  final List<IngredientAlternative> alternatives;
  final bool confirmed;

  /// Added by the user, not detected.
  final bool manual;

  /// Low-confidence detection the user confirmed (or renamed) in the review
  /// sheet. The model score no longer matters, so the UI shows "Đã xác nhận".
  final bool userVerified;

  /// Can go into the fridge: confirmed and vegan.
  bool get savable => confirmed && isVegan;

  VeganVerdict get veganVerdict => isVegan
      ? const VeganVerdict.vegan()
      : VeganVerdict.nonVegan(
          reason: nonVeganReason ?? 'Có nguồn gốc động vật',
          veganAlternatives: veganAlternatives);

  /// Vegan verdict if this item turns out to be [candidate]: its own for the
  /// detected label, the server's flag for a listed alternative, otherwise
  /// the local check (a name typed in "Loại khác…").
  VeganVerdict veganVerdictFor(String candidate) {
    final key = candidate.trim().toLowerCase();
    if (key == name.trim().toLowerCase()) return veganVerdict;
    final alternative =
        alternatives.where((a) => a.name.trim().toLowerCase() == key);
    return resolveVegan(candidate,
        serverIsVegan: alternative.firstOrNull?.isVegan);
  }

  DetectedIngredient copyWith({
    String? name,
    double? confidence,
    VeganVerdict? vegan,
    bool? confirmed,
    bool? userVerified,
  }) {
    return DetectedIngredient(
      id: id,
      name: name ?? this.name,
      confidence: confidence ?? this.confidence,
      isVegan: vegan?.isVegan ?? isVegan,
      nonVeganReason: vegan == null ? nonVeganReason : vegan.nonVeganReason,
      veganAlternatives:
          vegan == null ? veganAlternatives : vegan.veganAlternatives,
      box: box,
      alternatives: alternatives,
      confirmed: confirmed ?? this.confirmed,
      manual: manual,
      userVerified: userVerified ?? this.userVerified,
    );
  }
}

/// One AI menu suggestion built from the scanned ingredients.
class MenuSuggestion {
  const MenuSuggestion({
    required this.id,
    required this.name,
    required this.calories,
    required this.prepMinutes,
    required this.usedIngredients,
    required this.missingIngredients,
    this.allergens = const [],
  });

  final String id;
  final String name;
  final int calories;
  final int prepMinutes;
  final List<String> usedIngredients;
  final List<String> missingIngredients;

  /// Allergen ids (`peanut`, `soy`…) the dish contains.
  final List<String> allergens;
}
