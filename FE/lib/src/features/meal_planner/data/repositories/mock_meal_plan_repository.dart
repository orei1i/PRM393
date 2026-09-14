import '../../domain/entities/meal_entities.dart';
import '../../domain/repositories/meal_plan_repository.dart';

class MockMealPlanRepository implements MealPlanRepository {
  static const _breakfast = [
    PlannedMeal(
      name: 'Mango overnight oats',
      kind: 'Breakfast',
      ingredients: ['Oats', 'Soy milk', 'Mango'],
      minutes: 10,
      art: 3,
    ),
    PlannedMeal(
      name: 'Tofu breakfast scramble',
      kind: 'Breakfast',
      ingredients: ['Tofu', 'Spinach', 'Bread'],
      minutes: 15,
      art: 2,
    ),
    PlannedMeal(
      name: 'Berry chia bowl',
      kind: 'Breakfast',
      ingredients: ['Chia seeds', 'Soy milk', 'Berries'],
      minutes: 10,
      art: 0,
    ),
  ];
  static const _mains = [
    PlannedMeal(
      name: 'The everyday green bowl',
      kind: 'Lunch',
      ingredients: ['Chickpeas', 'Quinoa', 'Kale', 'Tahini'],
      minutes: 25,
      art: 0,
    ),
    PlannedMeal(
      name: 'Creamy mushroom pasta',
      kind: 'Lunch',
      ingredients: ['Pasta', 'Mushrooms', 'Cashews'],
      minutes: 30,
      art: 1,
    ),
    PlannedMeal(
      name: 'Ginger tofu & rice',
      kind: 'Lunch',
      ingredients: ['Tofu', 'Rice', 'Broccoli', 'Ginger'],
      minutes: 20,
      art: 2,
    ),
    PlannedMeal(
      name: 'Sunday lentil curry',
      kind: 'Lunch',
      ingredients: ['Lentils', 'Tomatoes', 'Spinach'],
      minutes: 35,
      art: 1,
    ),
    PlannedMeal(
      name: 'Sweet potato black bean bowl',
      kind: 'Lunch',
      ingredients: ['Sweet potato', 'Black beans', 'Avocado'],
      minutes: 30,
      art: 3,
    ),
  ];
  @override
  WeeklyMealPlan generate({
    required DateTime weekStart,
    required int generation,
    required List<String> ingredients,
  }) {
    final ranked = [..._mains];
    int matches(PlannedMeal meal) => meal.ingredients
        .where(
          (i) => ingredients.any(
            (input) => i.toLowerCase().contains(input.toLowerCase()),
          ),
        )
        .length;
    ranked.sort((a, b) {
      final comparison = matches(b).compareTo(matches(a));
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return WeeklyMealPlan(
      generation: generation,
      days: List.unmodifiable(
        List.generate(7, (day) {
          final lunch = ranked[(day + generation) % ranked.length];
          final dinner = ranked[(day + generation + 2) % ranked.length];
          return MealDay(
            date: weekStart.add(Duration(days: day)),
            meals: List.unmodifiable([
              _breakfast[(day + generation) % _breakfast.length],
              lunch,
              PlannedMeal(
                name: dinner.name,
                kind: 'Dinner',
                ingredients: dinner.ingredients,
                minutes: dinner.minutes,
                art: dinner.art,
              ),
            ]),
          );
        }),
      ),
    );
  }
}
