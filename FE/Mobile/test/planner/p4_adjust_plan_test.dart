// test/planner/p4_adjust_plan_test.dart
//
// P4 (TestPRM p18): "Chỉnh thực đơn với AI". The AI proposes changes, the
// member ticks which to keep, nothing changes before "Áp dụng thay đổi".
// Proposed dishes are always vegan and allergy-safe.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/allergy_match.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/plan_adjustment.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/adjust_plan_sheet.dart';
import 'package:veganlife_mobile/features/scanner/domain/vegan_check.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

/// Wednesday 14/10: the seeded week runs Mon 12/10 → Sun 18/10.
final _wed = DateTime(2026, 10, 14, 9);
final _wedDate = DateTime(2026, 10, 14);

Matcher _apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status));

Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() async {
    final dir =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File('$dir/roboto-$weight.ttf');
      if (file.existsSync()) {
        roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await roboto.load();
  });

  setUp(MockMealPlannerRepository.reset);

  group('mock AI rules', () {
    late MockMealPlannerRepository repo;

    setUp(() async {
      repo = MockMealPlannerRepository(userId: 'u_me', clock: () => _wed);
      await repo.getCurrentMealPlan();
    });

    Future<PlanAdjustment> ask(String message,
            {AdjustScope scope = AdjustScope.day}) async =>
        (await repo.adjustPlan(AdjustPlanRequestDto(
                message: message, scope: scope, date: _wedDate)))
            .toEntity();

    void expectSafe(Iterable<PlanChange> changes, List<String> allergies) {
      for (final c in changes) {
        final to = c.to;
        if (to == null) continue;
        expect(classifyVegan(to.name).isVegan, isTrue, reason: to.name);
        expect(
            allergyConflicts(
                tags: to.allergens, texts: [to.name], userAllergies: allergies),
            isEmpty,
            reason: to.name);
      }
    }

    test('"Ít tinh bột hơn cho bữa tối", today: one lower-carb dinner',
        () async {
      final p = await ask('Ít tinh bột hơn cho bữa tối');
      expect(p.changes, hasLength(1));
      final c = p.changes.single;
      expect(c.slot, MealSlot.dinner);
      expect(c.action, PlanChangeAction.replace);
      expect(isSameDay(c.date, _wedDate), isTrue);
      expect(c.from!.name, 'Đậu hũ kho nấm rơm');
      expect(c.to!.nutrition.carbsG!, lessThan(c.from!.nutrition.carbsG! - 5));
      expect(
          c.kcalDelta, c.to!.nutrition.calories - c.from!.nutrition.calories);
      expect(c.label,
          'Thứ Tư · Bữa tối: Đậu hũ kho nấm rơm → ${c.to!.name} (${c.kcalLabel})');
      expect(p.reply, contains('1 thay đổi cho hôm nay'));
      expectSafe(p.changes, const ['peanut']);
    });

    test('"Cả tuần" covers today and the days after', () async {
      final p =
          await ask('it tinh bot hon cho bua toi', scope: AdjustScope.week);
      final days = p.changes.map((c) => c.date.day).toSet();
      expect(days, isNotEmpty);
      expect(days.every((d) => d >= 14 && d <= 18), isTrue);
      for (final c in p.changes) {
        expect(
            c.to!.nutrition.carbsG!, lessThan(c.from!.nutrition.carbsG! - 5));
      }
      expect(p.reply, contains('cho cả tuần'));
      expectSafe(p.changes, const ['peanut']);
    });

    test('adding a snack: none when she has it; "phụ sáng" for the week',
        () async {
      final has = await ask('Thêm một bữa phụ chiều', scope: AdjustScope.week);
      expect(has.changes, isEmpty);
      expect(has.reply, contains('đã có phụ chiều'));

      final p = await ask('Thêm bữa phụ sáng', scope: AdjustScope.week);
      expect(p.changes, hasLength(5), reason: 'Wed → Sun');
      for (final c in p.changes) {
        expect(c.action, PlanChangeAction.add);
        expect(c.slot, MealSlot.snackAm);
        expect(c.from, isNull);
        expect(c.kcalDelta, c.to!.nutrition.calories);
        expect(c.label, startsWith('${weekdayLong(c.date)} · Phụ sáng: Thêm '));
      }
      expectSafe(p.changes, const ['peanut']);
    });

    test('"Thay các món có nấm" replaces every mushroom dish', () async {
      final p = await ask('Thay các món có nấm', scope: AdjustScope.week);
      expect(p.changes, isNotEmpty);
      for (final c in p.changes) {
        expect(mentionsAllergy('nấm', [c.from!.name]), isTrue,
            reason: c.from!.name);
        expect(mentionsAllergy('nấm', [c.to!.name]), isFalse,
            reason: c.to!.name);
      }
      expectSafe(p.changes, const ['peanut']);
    });

    test('"Giảm còn 1.600 kcal/ngày" lightens today to ≈ 1.600 kcal', () async {
      final plan = (await repo.getCurrentMealPlan())!;
      final wed = plan.days.firstWhere((d) => isSameDay(d.date, _wedDate));
      final before =
          wed.meals.values.fold<int>(0, (s, r) => s + r.nutrition.calories);
      expect(before, greaterThan(1650));
      final p = await ask('Giảm còn 1.600 kcal/ngày');
      expect(p.changes, isNotEmpty);
      final after = before + p.changes.fold<int>(0, (s, c) => s + c.kcalDelta);
      expect(after, lessThanOrEqualTo(1600 * 1.03));
      expect(p.changes.every((c) => c.kcalDelta < 0), isTrue);
      expectSafe(p.changes, const ['peanut']);
    });

    test('"Bữa sáng nhanh dưới 15 phút": only quick breakfasts', () async {
      final p =
          await ask('Bữa sáng nhanh dưới 15 phút', scope: AdjustScope.week);
      expect(p.changes, isNotEmpty);
      for (final c in p.changes) {
        expect(c.slot, MealSlot.breakfast);
        expect(c.from!.prepMinutes!, greaterThan(15));
        expect(c.to!.prepMinutes!, lessThanOrEqualTo(15));
      }
      expectSafe(p.changes, const ['peanut']);
    });

    test('an unknown request gets examples; #fail → 503; empty → 400',
        () async {
      final p = await ask('hát cho mình nghe một bài');
      expect(p.changes, isEmpty);
      expect(p.reply, startsWith('Mình chưa hiểu yêu cầu. Bạn thử:'));
      await expectLater(ask('Ít tinh bột #fail'), _apiError(503));
      await expectLater(ask('   '), _apiError(400));
    });

    test('never proposes the member\'s allergies, tagged or typed', () async {
      const allergies = ['peanut', 'soy', 'Nấm'];
      await repo.updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 172,
        weightKg: 66,
        goal: HealthGoal.leanMuscle,
        allergies: allergies,
        dietaryRestrictions: [],
      ));
      for (final message in [
        'Ít tinh bột hơn cho bữa tối',
        'Thêm bữa phụ sáng',
        'Giảm còn 1.600 kcal/ngày',
        'Bữa sáng nhanh dưới 15 phút',
      ]) {
        final p = await ask(message, scope: AdjustScope.week);
        expectSafe(p.changes, allergies);
      }
    });

    test('apply only the ticked changes; twice → 409; unknown → 404', () async {
      final p = await ask('Thay các món có nấm', scope: AdjustScope.week);
      expect(p.changes.length, greaterThan(1));
      final keep = p.changes.first;
      final skip = p.changes[1];
      final plan = (await repo
              .applyAdjustment(proposalId: p.proposalId, changeIds: [keep.id]))
          .toEntity();
      final kept = plan.dayFor(keep.date)!.meals[keep.slot]!;
      expect(kept.id, keep.to!.id);
      expect(kept.source, MealSource.ai);
      expect(plan.dayFor(skip.date)!.meals[skip.slot]!.id, skip.from!.id,
          reason: 'unticked: unchanged');
      await expectLater(
          repo.applyAdjustment(proposalId: p.proposalId, changeIds: [skip.id]),
          _apiError(409));
      await expectLater(
          repo.applyAdjustment(proposalId: 'adj_nope', changeIds: ['c1']),
          _apiError(404));
      final again = await ask('Thay các món có nấm');
      await expectLater(
          repo.applyAdjustment(proposalId: again.proposalId, changeIds: []),
          _apiError(400));
    });

    test('the wire format round-trips', () async {
      final dto = await repo.adjustPlan(AdjustPlanRequestDto(
          message: 'Ít tinh bột hơn cho bữa tối',
          scope: AdjustScope.day,
          date: _wedDate));
      final again = PlanAdjustmentDto.fromJson(dto.toJson()).toEntity();
      expect(again.proposalId, dto.proposalId);
      expect(again.changes.single.to!.id, dto.changes.single.to!.id);
      expect(again.changes.single.slot, MealSlot.dinner);
      expect(
          AdjustPlanRequestDto(
                  message: 'x', scope: AdjustScope.week, date: _wedDate)
              .toJson(),
          {'message': 'x', 'scope': 'week', 'date': '2026-10-14'});
    });
  });

  group('controller', () {
    test('propose changes nothing; apply updates the planner', () async {
      SharedPreferences.setMockInitialValues(_minhAnh);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        plannerClockProvider.overrideWithValue(() => _wed),
      ]);
      addTearDown(container.dispose);
      container.listen(mealPlanControllerProvider, (_, __) {});
      final before = await container.read(mealPlanControllerProvider.future);
      final notifier = container.read(mealPlanControllerProvider.notifier);
      final p = await notifier.proposeAdjustment(
          'Ít tinh bột hơn cho bữa tối', AdjustScope.day);
      expect(
          container
              .read(mealPlanControllerProvider)
              .requireValue
              .selectedDay!
              .meals[MealSlot.dinner]!
              .id,
          before.selectedDay!.meals[MealSlot.dinner]!.id);
      final applied = await notifier.applyAdjustment(p, {p.changes.single.id});
      expect(applied, 1);
      expect(
          container
              .read(mealPlanControllerProvider)
              .requireValue
              .selectedDay!
              .meals[MealSlot.dinner]!
              .id,
          p.changes.single.to!.id);
    });
  });

  group('sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(411, 1800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(_minhAnh);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          plannerClockProvider.overrideWithValue(() => _wed),
        ],
        child: const MaterialApp(home: MealPlannerScreen()),
      ));
      await _wait(tester, 3000);
      await tester.tap(find.text('Chỉnh thực đơn với AI'));
      await _wait(tester, 750);
      expect(find.byType(AdjustPlanSheet), findsOneWidget);
    }

    testWidgets(
        'pill → chips → proposal with checkboxes → "Áp dụng thay đổi" '
        'updates the dinner', (tester) async {
      await openSheet(tester);
      // Suggestion chips (a horizontal row: the first ones are on screen).
      for (final example in adjustPlanExamples.take(2)) {
        expect(find.widgetWithText(ActionChip, example), findsOneWidget);
      }
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('Cả tuần'), findsOneWidget);

      await tester
          .tap(find.widgetWithText(ActionChip, 'Ít tinh bột hơn cho bữa tối'));
      await _wait(tester, 2000);
      final row = find.byType(CheckboxListTile);
      expect(row, findsOneWidget);
      final label = tester
          .widget<Text>(find.descendant(of: row, matching: find.byType(Text)))
          .data!;
      expect(label, startsWith('Thứ Tư · Bữa tối: Đậu hũ kho nấm rơm → '));
      final newDish = label
          .substring('Thứ Tư · Bữa tối: Đậu hũ kho nấm rơm → '.length)
          .replaceFirst(RegExp(r' \(.*\)$'), '');

      // Unticking everything disables "Áp dụng thay đổi".
      await tester.tap(row);
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Áp dụng thay đổi'))
              .onPressed,
          isNull);
      await tester.tap(row);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Áp dụng thay đổi'));
      await _wait(tester, 2000);
      expect(find.byType(AdjustPlanSheet), findsNothing);
      expect(find.text('Đã áp dụng 1 thay đổi vào thực đơn.'), findsOneWidget);
      expect(find.text(newDish), findsOneWidget);
      expect(find.text('Đậu hũ kho nấm rơm'), findsNothing);
      await _wait(tester, 5000); // snackbar
    });

    testWidgets('typed request; "Bỏ qua" keeps the plan; unknown → examples',
        (tester) async {
      await openSheet(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Bạn muốn chỉnh gì?'),
          'Thay các món có nấm');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 2000);
      expect(find.text('Thay các món có nấm'), findsWidgets);
      expect(find.byType(CheckboxListTile), findsWidgets);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Bỏ qua'));
      await tester.pump();
      expect(find.text('Đã bỏ qua đề xuất này.'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Bạn muốn chỉnh gì?'), 'xin chào');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 2000);
      expect(find.textContaining('Mình chưa hiểu yêu cầu. Bạn thử:'),
          findsOneWidget);

      await tester.tap(find.byTooltip('Đóng'));
      await _wait(tester, 1000);
      expect(find.byType(AdjustPlanSheet), findsNothing);
      expect(find.text('Đậu hũ kho nấm rơm'), findsOneWidget,
          reason: 'nothing applied');
    });
  });
}
