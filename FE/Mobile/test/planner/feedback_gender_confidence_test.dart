// test/planner/feedback_gender_confidence_test.dart
// Tester feedback: only Nam and Nữ in the health profile form, with an old "Khác"
// asked again on save; the scan shows no percentages.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/scanner/domain/entities/detected_ingredient.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/confirm_ingredient_sheet.dart';

Future<void> _pump(WidgetTester tester, Widget home,
    {Size size = const Size(411, 2400),
    double textScale = 1,
    ThemeData? theme}) async {
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
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

SegmentedButton<Gender> _segments(WidgetTester tester) =>
    tester.widget(find.byType(SegmentedButton<Gender>));

/// Minh Anh with an old "Khác" saved. Returns the store to read it back.
Future<MockMealPlannerRepository> _savedAsOther(WidgetTester tester) async {
  final repo = MockMealPlannerRepository(userId: 'u_me');
  final save = repo.updateHealthProfile(const UpdateHealthProfileRequestDto(
    heightCm: 172,
    weightKg: 66,
    goal: HealthGoal.maintain,
    allergies: [],
    dietaryRestrictions: [],
    gender: Gender.other,
    birthYear: 1997,
  ));
  await tester.pump(const Duration(seconds: 2));
  await save;
  return repo;
}

void main() {
  setUp(MockMealPlannerRepository.reset);

  group('gender', () {
    testWidgets('only Nam and Nữ, for a new or a saved profile',
        (tester) async {
      await _pump(tester, const HealthProfileEditScreen());
      await _wait(tester);
      expect(_segments(tester).segments.map((s) => s.value),
          [Gender.male, Gender.female]);
      expect(find.text('Khác'), findsNothing);
      expect(_segments(tester).selected, {Gender.female});
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'an old "Khác": no crash, nothing selected, leaving asks nothing; '
        '"Lưu" asks for a choice; choosing saves', (tester) async {
      final repo = await _savedAsOther(tester);
      await _pump(tester, const HealthProfileEditScreen());
      await _wait(tester);
      expect(tester.takeException(), isNull);
      expect(_segments(tester).selected, isEmpty);
      expect(find.text('Khác'), findsNothing);
      expect(find.text('Bỏ thay đổi?'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pump();
      expect(find.text(HealthProfileEditScreen.genderRequiredMessage),
          findsOneWidget);
      final still = repo.getHealthProfile();
      await tester.pump(const Duration(seconds: 1));
      expect((await still)!.gender, 'Other', reason: 'nothing was sent');

      await tester.tap(find.text('Nam'));
      await tester.pump();
      expect(find.text(HealthProfileEditScreen.genderRequiredMessage),
          findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester, 2000);
      final saved = repo.getHealthProfile();
      await tester.pump(const Duration(seconds: 1));
      expect((await saved)!.gender, 'Male');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('recognizer confidence', () {
    const low = DetectedIngredient(
      id: 'd1',
      name: 'Rau chân vịt',
      confidence: 0.58,
      isVegan: true,
      confirmed: false,
      alternatives: [
        IngredientAlternative(name: 'Rau muống', confidence: 0.21)
      ],
    );

    testWidgets('the confirm sheet shows no percentages, and fits',
        (tester) async {
      await _pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(
                  child: ConfirmIngredientSheet(item: low))),
          size: const Size(360, 1200),
          textScale: 1.3,
          theme: AppTheme.dark());
      await tester.pump();
      expect(find.text('Rau chân vịt'), findsOneWidget);
      expect(find.text('Rau muống'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
