// lib/features/scanner/domain/entities/detected_ingredient.dart

enum Freshness {
  fresh('fresh', 'Tươi'),
  useSoon('use_soon', 'Dùng sớm'),
  pastPrime('past_prime', 'Kém tươi'),
  unknown('unknown', 'Chưa rõ');

  const Freshness(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static Freshness fromApi(String? value) =>
      values.firstWhere((f) => f.apiValue == value, orElse: () => Freshness.unknown);
}

/// Box in 0…1 coordinates of the analysed frame (top-left origin).
class NormalizedBox {
  const NormalizedBox({required this.left, required this.top, required this.width, required this.height});

  final double left;
  final double top;
  final double width;
  final double height;
}

class IngredientAlternative {
  const IngredientAlternative({required this.name, required this.confidence});

  final String name;
  final double confidence;
}

class DetectedIngredient {
  const DetectedIngredient({
    required this.id,
    required this.name,
    required this.confidence,
    required this.freshness,
    this.box,
    this.quantity = 1,
    this.unit = 'phần',
    this.alternatives = const [],
    this.confirmed = true,
    this.manual = false,
  });

  /// Below this the item enters the tray unconfirmed (dashed, needs a tap).
  static const double confirmThreshold = 0.7;

  final String id;
  final String name;
  final double confidence;
  final Freshness freshness;
  final NormalizedBox? box;
  final double quantity;
  final String unit;
  final List<IngredientAlternative> alternatives;
  final bool confirmed;

  /// Added by the user, not detected.
  final bool manual;

  DetectedIngredient copyWith({
    String? name,
    double? quantity,
    String? unit,
    Freshness? freshness,
    bool? confirmed,
  }) {
    return DetectedIngredient(
      id: id,
      name: name ?? this.name,
      confidence: confidence,
      freshness: freshness ?? this.freshness,
      box: box,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      alternatives: alternatives,
      confirmed: confirmed ?? this.confirmed,
      manual: manual,
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
  });

  final String id;
  final String name;
  final int calories;
  final int prepMinutes;
  final List<String> usedIngredients;
  final List<String> missingIngredients;
}
