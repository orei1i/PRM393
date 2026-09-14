enum MeasurementUnit { metric, imperial }

class BmiProfile {
  const BmiProfile({
    required this.heightCm,
    required this.weightKg,
    required this.bmi,
  });
  final double heightCm, weightKg, bmi;
  String get classification => bmi < 18.5
      ? 'Below the standard adult reference range'
      : bmi < 25
      ? 'Within the standard adult reference range'
      : bmi < 30
      ? 'Above the standard adult reference range'
      : 'Above the standard adult reference range';
}

class IngredientItem {
  const IngredientItem({required this.name, this.checked = false});
  final String name;
  final bool checked;
  IngredientItem toggle() => IngredientItem(name: name, checked: !checked);
}

class PlannedMeal {
  const PlannedMeal({
    required this.name,
    required this.kind,
    required this.ingredients,
    required this.minutes,
    required this.art,
  });
  final String name, kind;
  final List<String> ingredients;
  final int minutes, art;
}

class MealDay {
  const MealDay({required this.date, required this.meals});
  final DateTime date;
  final List<PlannedMeal> meals;
}

class WeeklyMealPlan {
  const WeeklyMealPlan({required this.days, this.generation = 0});
  final List<MealDay> days;
  final int generation;
}
