import '../entities/nutrition_entities.dart';

abstract interface class NutritionRepository {
  List<NutritionTip> get quickActions;
  List<FoodSubstitution> get substitutions;
  Stream<String> streamResponse(String prompt);
}
