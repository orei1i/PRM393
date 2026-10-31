// test/integration_advisor/recipe_energy_card_overflow_test.dart
// Regression: on the recipe page of a signed-in member with meal targets,
// the energy card's "So với mục tiêu: [Bữa tối ▾]" row overflowed by 8,8 px
// at 411 dp. It now wraps; nothing on the page overflows on a 360 / 411 dp
// phone at text scale 1,0 and 1,3.
//
// Deliberately with the default test font (every glyph a square, wider
// than any phone font): the old row overflows here at 411 dp × 1,0 (and
// with real Roboto metrics only from text ×2), so this is the strict check.
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/recipe_energy_card.dart';

import 'advisor_harness.dart';

Future<void> _pumpRecipe(WidgetTester tester,
    {required double width, required double textScale, MealSlot? slot}) async {
  tester.view
    ..physicalSize = Size(width, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(minhAnhPrefs);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      plannerClockProvider.overrideWithValue(advisorNow),
    ],
    child: MaterialApp(
      navigatorObservers: [AppRouteStack()],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RecipeDetailScreen(
          recipeId: 'l5', name: 'Bún riêu chay', contextSlot: slot),
    ),
  ));
  await settle(tester, 3000); // the recipe, the plan, the nutrition index
}

void main() {
  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
  });

  for (final width in [360.0, 411.0]) {
    for (final scale in [1.0, 1.3]) {
      for (final slot in [null, MealSlot.snackPm]) {
        testWidgets(
            '$width dp, text ×$scale, compared with '
            '${slot?.label ?? 'the closest meal'}: no overflow',
            (tester) async {
          await _pumpRecipe(tester, width: width, textScale: scale, slot: slot);
          final card = find.byType(RecipeEnergyCard);
          expect(card, findsOneWidget);
          expect(
              find.descendant(
                  of: card, matching: find.text('So với mục tiêu:')),
              findsOneWidget,
              reason: 'a signed-in member with meal targets');
          expect(
              find.descendant(
                  of: card,
                  matching: find.text((slot ?? MealSlot.dinner).label)),
              findsOneWidget);
          expect(tester.takeException(), isNull);
          await disposeApp(tester);
        });
      }
    }
  }
}
