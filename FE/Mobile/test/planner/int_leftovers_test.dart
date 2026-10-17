// test/planner/int_leftovers_test.dart
// Split from test/int_leftovers_test.dart: the chef-suggestion target day
// (member side).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';

Future<void> _pumpApp(WidgetTester tester, Widget home,
    {Size size = const Size(411, 1400)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'vl.access_token': 'mock.jwt',
    'vl.display_name': 'Minh Anh',
    'vl.user_id': 'u_me',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: home),
  ));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  group('chef suggestion target day (member side)', () {
    test('DTO reads targetDate; the label names the meal and the day', () {
      final dto = ChefSuggestionDto.fromJson({
        'id': 'sg_1',
        'chefId': 'u_chef_tam',
        'chefName': 'Lê Quang Tâm',
        'slot': 'dinner',
        'targetDate': '2026-10-17',
        'recipe': {
          'id': 'cs_1',
          'name': 'Bún gạo lứt xào',
          'caloriesCache': 480
        },
      });
      expect(dto.targetDate, DateTime(2026, 10, 17));
      final s = dto.toEntity();
      expect(s.targetDate, DateTime(2026, 10, 17));
      expect(s.scheduleLabel, 'Cho bữa tối · Thứ Bảy, 17/10');

      final dayOnly = ChefSuggestionDto.fromJson({
        'id': 'sg_2',
        'targetDate': '2026-10-19',
        'recipe': {'id': 'cs_2', 'name': 'Cháo'},
      }).toEntity();
      expect(dayOnly.scheduleLabel, 'Cho Thứ Hai, 19/10');

      final none = ChefSuggestionDto.fromJson({
        'id': 'sg_3',
        'slot': 'lunch',
        'targetDate': null,
        'recipe': {'id': 'cs_3', 'name': 'Cơm'},
      }).toEntity();
      expect(none.targetDate, isNull);
      expect(none.scheduleLabel, isNull);
    });

    test('Minh Anh\'s seeded dinner suggestion is for tomorrow', () async {
      final list =
          await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
      final dinner = list
          .map((d) => d.toEntity())
          .firstWhere((s) => s.slot == MealSlot.dinner);
      expect(dinner.targetDate,
          dateOnly(DateTime.now().add(const Duration(days: 1))));
    });

    testWidgets('"Từ chuyên gia" shows "Cho bữa tối · <Thứ>, dd/MM"',
        (tester) async {
      await _pumpApp(tester, const MealPlannerScreen(),
          size: const Size(411, 2600));
      await _wait(tester, 3000);
      await tester.tap(find.byTooltip('Đổi bữa sáng'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final chefTab = find.descendant(
          of: find.byType(TabBar), matching: find.text('Từ chuyên gia'));
      await tester.ensureVisible(chefTab); // the tab row scrolls
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chefTab);
      await _wait(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(find.text('Cho bữa tối · ${formatLongDate(tomorrow)}'),
          findsOneWidget);
      expect(find.text('Lê Quang Tâm đề xuất cho bữa sáng'), findsOneWidget);
      expect(find.text('Lê Quang Tâm đề xuất'), findsOneWidget);
      await _wait(tester, 1000);
    });
  });
}
