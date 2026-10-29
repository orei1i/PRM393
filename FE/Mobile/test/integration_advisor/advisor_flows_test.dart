// test/integration_advisor/advisor_flows_test.dart
// WP-D: the advisor-round features working together in the whole app —
// search ↔ recipe ↔ ingredient never stack copies (§6 N9, N10, N11 for
// posts and restaurants), a recipe opened from a Thực đơn meal (card or
// "Đổi …" sheet) compares with that meal and adds to it by default, a
// customized recipe saved into Thực đơn opens again from its card as the
// variant, and a catalogue recipe outside the planner pools (`menu_2`) can
// be added. Clock pinned to Thứ Năm 29/10/2026.
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/widgets/vl_card.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/mock_recipe_book.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_picker_sheet.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_slot_card.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_customization.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_customization_controller.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/recipe_energy_card.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/widgets/restaurant_tile.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/widgets/search_tiles.dart';

import 'advisor_harness.dart';

/// The meal targets of the signed-in member (derived, never hard-coded:
/// the age in the profile uses the real year).
Map<MealSlot, int> _targets(ProviderContainer container) => slotTargets(
    container.read(mealPlanControllerProvider).requireValue.healthProfile!);

/// The "So với mục tiêu" row of the energy card shows [slot].
void _expectCompares(MealSlot slot) {
  final card = find.byType(RecipeEnergyCard);
  expect(find.descendant(of: card, matching: find.text('So với mục tiêu:')),
      findsOneWidget);
  expect(find.descendant(of: card, matching: find.text(slot.label)),
      findsOneWidget);
  // "Vừa với / Cao hơn / Thấp hơn mục tiêu {bữa} …".
  expect(
      find.descendant(
          of: card,
          matching:
              find.textContaining('mục tiêu ${slot.label.toLowerCase()} ')),
      findsOneWidget);
}

/// Whether the add-to-plan sheet's chip [label] is selected.
bool _chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  setUpAll(loadRoboto);

  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
  });

  group('navigation', () {
    testWidgets(
        'N9 search › recipe › "Tìm video & quán liên quan", twice: one '
        'search page, one back to the shell', (tester) async {
      await pumpAdvisorApp(tester, prefs: guestPrefs);
      await pushRoute(tester, SearchScreen.route(initialQuery: 'bun rieu'));
      final dish = find.widgetWithText(SearchRecipeTile, 'Bún riêu chay');
      final related = find.text('Tìm video & quán liên quan');

      for (var round = 1; round <= 2; round++) {
        await tapAndSettle(tester, dish.first, 3000);
        expect(routeNames(tester), ['/', '/search', '/recipe/l5'],
            reason: 'round $round');
        await tester.ensureVisible(related);
        await tapAndSettle(tester, related, 3000);
        expect(routeNames(tester), ['/', '/search'], reason: 'round $round');
        expect(find.byType(SearchScreen, skipOffstage: false), findsOneWidget);
        expect(
            find.byType(RecipeDetailScreen, skipOffstage: false), findsNothing);
      }

      await systemBack(tester);
      expect(routeNames(tester), ['/']);
      await disposeApp(tester);
    });

    testWidgets(
        'N10 recipe › ingredient › the same recipe goes back to it, every '
        'time', (tester) async {
      await pumpAdvisorApp(tester, prefs: guestPrefs);
      await pushRoute(tester, SearchScreen.route(initialQuery: 'bun rieu'));
      await tapAndSettle(tester,
          find.widgetWithText(SearchRecipeTile, 'Bún riêu chay').first, 3000);
      expect(routeNames(tester), ['/', '/search', '/recipe/l5']);

      for (var round = 1; round <= 2; round++) {
        // "Cà chua" is in the nutrition DB: its name opens the ingredient.
        await tapAndSettle(tester, find.text('Cà chua'), 3000);
        final names = routeNames(tester);
        expect(names, hasLength(4), reason: 'round $round');
        expect(names.last, startsWith('/ingredient/'));
        expect(find.byType(IngredientDetailScreen), findsOneWidget);

        final row = find.widgetWithText(ListTile, 'Bún riêu chay');
        await tester.scrollUntilVisible(row, 200,
            scrollable: find
                .descendant(
                    of: find.byType(IngredientDetailScreen),
                    matching: find.byType(Scrollable))
                .first);
        await tapAndSettle(tester, row, 2000);
        expect(routeNames(tester), ['/', '/search', '/recipe/l5'],
            reason: 'back to the open recipe (round $round)');
        expect(find.byType(RecipeDetailScreen, skipOffstage: false),
            findsOneWidget);
        expect(find.byType(IngredientDetailScreen, skipOffstage: false),
            findsNothing);
      }
      await disposeApp(tester);
    });

    testWidgets(
        'post and restaurant pages are named by id, so a search result '
        'goes back to the open page', (tester) async {
      expect(AppRoutes.post('p_1'), '/post/p_1');
      expect(AppRoutes.restaurant('r_1'), '/restaurant/r_1');
      expect(
          RestaurantDetailScreen.route('r_1').settings.name, '/restaurant/r_1');

      await pumpAdvisorApp(tester, prefs: guestPrefs);
      Future<void> searchAgain() =>
          pushRoute(tester, SearchScreen.route(initialQuery: 'bun rieu'));

      // A restaurant result.
      await searchAgain();
      await tester.ensureVisible(find.byType(RestaurantTile).first);
      await tapAndSettle(tester, find.byType(RestaurantTile).first, 3000);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      final restaurant = routeNames(tester).last!;
      expect(restaurant, startsWith('/restaurant/'));
      expect(routeNames(tester), ['/', '/search', restaurant]);
      await searchAgain();
      expect(routeNames(tester), ['/', '/search', restaurant, '/search']);
      await tester.ensureVisible(find.byType(RestaurantTile).first);
      await tapAndSettle(tester, find.byType(RestaurantTile).first, 2000);
      expect(routeNames(tester), ['/', '/search', restaurant],
          reason: 'back to the open restaurant, not a copy');

      // A post result.
      await systemBack(tester);
      expect(routeNames(tester), ['/', '/search']);
      await tester.ensureVisible(find.byType(SearchPostTile).first);
      await tapAndSettle(tester, find.byType(SearchPostTile).first, 3000);
      expect(find.byType(PostDetailScreen), findsOneWidget);
      final post = routeNames(tester).last!;
      expect(post, startsWith('/post/'));
      expect(routeNames(tester), ['/', '/search', post]);
      await searchAgain();
      await tester.ensureVisible(find.byType(SearchPostTile).first);
      await tapAndSettle(tester, find.byType(SearchPostTile).first, 2000);
      expect(routeNames(tester), ['/', '/search', post],
          reason: 'back to the open post, not a copy');
      expect(
          find.byType(PostDetailScreen, skipOffstage: false), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('Thực đơn ↔ recipe page', () {
    testWidgets(
        'a meal card opens its recipe compared with that meal; "Thêm vào '
        'Thực đơn" defaults to the same day and meal', (tester) async {
      final container = await pumpAdvisorApp(tester);
      container.read(shellTabProvider.notifier).select(ShellTab.planner);
      await settle(tester, 1000);
      final state = container.read(mealPlanControllerProvider).requireValue;
      expect(state.selectedDate, DateTime(2026, 10, 29));
      final lunch = state.selectedDay!.meals[MealSlot.lunch]!;
      expect(lunch.hasDetail, isTrue);

      final name = find.descendant(
          of: find.byType(MealSlotCard), matching: find.text(lunch.name));
      await tester.ensureVisible(name);
      await tapAndSettle(tester, name, 3000);
      expect(routeNames(tester), ['/', '/recipe/${lunch.id}']);
      _expectCompares(MealSlot.lunch);

      await tapAndSettle(tester, find.text('Thêm vào Thực đơn'), 1500);
      expect(_chipSelected(tester, 'T5 29/10'), isTrue);
      expect(_chipSelected(tester, 'Bữa trưa'), isTrue);
      expect(find.text('Món này đã có trong bữa trưa'), findsOneWidget,
          reason: 'the same dish is already in that meal');
      await disposeApp(tester);
    });

    testWidgets(
        'a customized recipe added to Friday dinner opens from its card as '
        'the variant, compared with dinner; "Xem công thức" in the "Đổi '
        'phụ chiều" sheet compares with phụ chiều', (tester) async {
      final container = await pumpAdvisorApp(tester);
      final targets = _targets(container);
      await pushRoute(
          tester, RecipeDetailScreen.route('l5', name: 'Bún riêu chay'));
      expect(find.text('580 kcal / phần'), findsOneWidget);

      // Riêu đậu hũ → riêu nấm (E1: 514 kcal).
      await tapAndSettle(
          tester, find.byTooltip('Thành phần chính — không bỏ được'));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Đổi riêu'));
      await tapAndSettle(tester, find.text('Nấm rơm băm nhuyễn · 300 g'), 300);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Áp dụng'));
      expect(find.text('≈ 514 kcal / phần'), findsOneWidget);

      await tapAndSettle(tester, find.text('Thêm vào Thực đơn'), 1500);
      await tapAndSettle(
          tester, find.widgetWithText(ChoiceChip, 'T6 30/10'), 300);
      await tapAndSettle(
          tester, find.widgetWithText(ChoiceChip, 'Bữa tối'), 300);
      await tapAndSettle(
          tester, find.text('Thêm vào bữa tối · T6 30/10'), 3000);
      expect(
          find.text('Đã thêm «Bún riêu chay (tuỳ chỉnh)» vào bữa tối, '
              'Thứ Sáu, 30/10.'),
          findsOneWidget);
      final variant = MockRecipeBook.userRecipes('u_me').single;
      final variantId = variant['id'] as String;
      expect(variant['caloriesCache'], 514);

      // "Xem Thực đơn": the tab, on Friday, with the variant at dinner.
      await tapAndSettle(tester, find.text('Xem Thực đơn'), 1000);
      expect(routeNames(tester), ['/']);
      expect(container.read(shellTabProvider), ShellTab.planner);
      final state = container.read(mealPlanControllerProvider).requireValue;
      expect(state.selectedDate, DateTime(2026, 10, 30));
      final dinner = state.selectedDay!.meals[MealSlot.dinner]!;
      expect(dinner.id, variantId);
      expect(dinner.source, MealSource.userRecipe);
      final card = find.ancestor(
          of: find.text('Bún riêu chay (tuỳ chỉnh)'),
          matching: find.byType(MealSlotCard));
      expect(card, findsOneWidget);
      expect(
          find.descendant(of: card, matching: find.text('Công thức của tôi')),
          findsOneWidget);

      // The card opens the variant, compared with dinner — not with the
      // meal closest to 514 kcal.
      expect(defaultCompareSlot(targets, 514), isNot(MealSlot.dinner),
          reason: 'precondition: the context decides, not the closest meal');
      await tester.ensureVisible(card);
      await tapAndSettle(tester, find.text('Bún riêu chay (tuỳ chỉnh)'), 3000);
      expect(routeNames(tester), ['/', '/recipe/$variantId']);
      expect(
          find.textContaining('Biến thể của «Bún riêu chay»'), findsOneWidget);
      expect(find.text('514 kcal / phần'), findsOneWidget);
      _expectCompares(MealSlot.dinner);
      await tapAndSettle(tester, find.text('Thêm vào Thực đơn'), 1500);
      expect(_chipSelected(tester, 'T6 30/10'), isTrue);
      expect(find.text('Món này đã có trong bữa tối'), findsOneWidget);
      await systemBack(tester, 600); // the sheet
      await systemBack(tester); // the variant

      expect(routeNames(tester), ['/']);

      // "Đổi phụ chiều" › "Công thức của tôi" › "Xem công thức".
      final swap = find.byTooltip('Đổi phụ chiều');
      await tester.ensureVisible(swap);
      await tapAndSettle(tester, swap, 1500);
      expect(find.byType(MealPickerSheet), findsOneWidget);
      await tapAndSettle(
          tester, find.widgetWithText(Tab, 'Công thức của tôi'), 1500);
      final tile = find
          .ancestor(
              of: find.descendant(
                  of: find.byType(MealPickerSheet),
                  matching: find.text('Bún riêu chay (tuỳ chỉnh)')),
              matching: find.byType(VLCard))
          .first;
      await tapAndSettle(
          tester,
          find.descendant(of: tile, matching: find.byTooltip('Xem công thức')),
          3000);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      _expectCompares(MealSlot.snackPm);
      await tapAndSettle(tester, find.text('Thêm vào Thực đơn'), 1500);
      expect(_chipSelected(tester, 'T6 30/10'), isTrue);
      expect(_chipSelected(tester, MealSlot.snackPm.label), isTrue);
      expect(find.text('Thêm vào phụ chiều · T6 30/10'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets(
        '"menu_2" (a scanner idea, not in the planner pools) is added from '
        'its page as "Từ công thức"', (tester) async {
      final container = await pumpAdvisorApp(tester);
      final targets = _targets(container);
      await pushRoute(tester, RecipeDetailScreen.route('menu_2'));
      const name = 'Canh cà chua đậu hũ rau thơm';
      expect(find.text('260 kcal / phần'), findsOneWidget);

      final slot = defaultCompareSlot(targets, 260)!;
      final meal = slot.label.toLowerCase();
      _expectCompares(slot);
      await tapAndSettle(tester, find.text('Thêm vào Thực đơn'), 1500);
      await tapAndSettle(tester, find.text('Thêm vào $meal · T5 29/10'), 3000);
      expect(find.text('Đã thêm «$name» vào $meal, Thứ Năm, 29/10.'),
          findsOneWidget);
      expect(find.textContaining('Chưa thêm được món'), findsNothing);
      final placed = container
          .read(mealPlanControllerProvider)
          .requireValue
          .plan!
          .dayFor(DateTime(2026, 10, 29))!
          .meals[slot]!;
      expect(placed.id, 'menu_2');
      expect(placed.name, name);
      expect(placed.source, MealSource.recipe);

      await tapAndSettle(tester, find.text('Xem Thực đơn'), 1000);
      final card = find.ancestor(
          of: find.text(name), matching: find.byType(MealSlotCard));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Từ công thức')),
          findsOneWidget);
      await disposeApp(tester);
    });
  });
}
