// test/resilience/unit_guards_test.dart
// Small places where a bad value used to throw: a target of 0 kcal (recipe page,
// "So với mục tiêu"), a link that doesn't parse.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/json_helpers.dart';
import 'package:veganlife_mobile/core/utils/open_url.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_customization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a null in a list of texts never reads as the word "null"', () {
    expect(readStringList(<Object?>[null, 'soy', null]), ['soy']);
    expect(readStringList(null), isEmpty);
  });

  test('a day target of 0 kcal gives no meal targets', () {
    expect(MealPattern.kcalTargets(MealPattern.standard, 0), isEmpty);
    expect(MealPattern.kcalTargets(MealPattern.standard, -5), isEmpty);
    expect(MealPattern.kcalTargets(MealPattern.standard, 2000), isNotEmpty);
  });

  test('comparing with a 0 kcal target has a message, not a crash', () {
    const comparison =
        SlotComparison(slot: MealSlot.lunch, target: 0, energy: 400);
    expect(comparison.deviation, 0);
    expect(comparison.message, isNotEmpty);
  });

  test('a link that does not parse just does not open', () async {
    expect(await openExternalUrl('http://['), isFalse);
  });

  test('no handler on the phone (no plugin here) just does not open', () async {
    expect(await openExternalUrl('https://example.com/a'), isFalse);
  });
}
