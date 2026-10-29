// test/body_metrics/body_metrics_widget_test.dart
//
// WP-B (item 6): the check-in card on Thực đơn, the "Cập nhật cân nặng"
// sheet, the progress review, "Theo dõi cân nặng" (summary, chart, reminder,
// history) and its entry points (Thực đơn header, Tôi). Minh Anh's seeds
// with the clock pinned to Thứ Năm 29/10/2026 (last weigh-in 8 days ago).
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/core/widgets/guest_gate.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/body_metrics_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/check_in_card.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/progress_review_sheet.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/weight_chart.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';

const _newUserId = 'u_reg_1_1760600000000';

Map<String, Object> _session(String userId, String name) => {
      'vl.access_token': 'mock.jwt',
      'vl.display_name': name,
      'vl.user_id': userId,
      'vl.role': 'User',
    };

Future<SharedPreferences> _pump(WidgetTester tester, Widget home,
    {Map<String, Object>? session,
    Size size = const Size(411, 2400),
    double textScale = 1,
    ThemeData? theme}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(
      session ?? _session('u_me', 'Minh Anh'));
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      plannerClockProvider.overrideWithValue(() => DateTime(2026, 10, 29, 9)),
    ],
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
  return prefs;
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 3000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Minh Anh's daily target at [kg] (Tăng cơ, Nữ, 29 tuổi, Nhẹ).
int _target(double kg) => Energy.dailyTarget(
    Energy.tdee(
        Energy.bmr(
            gender: Gender.female,
            weightKg: kg,
            heightCm: 172,
            age: Energy.ageFrom(1997)),
        ActivityLevel.light),
    0.05);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Finder _chartLabelled(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label && w.child is Row);

Future<void> _openCheckInFromPlanner(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Cập nhật'));
  await _wait(tester, 1000);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
  await _wait(tester, 2000);
}

void main() {
  // Real Roboto metrics (the default test font draws wide squares), so the
  // layout checks below match a phone.
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

  setUp(() {
    MockAuthDb.reset();
    MockProfileRepository.reset();
    MockMealPlannerRepository.reset();
  });

  group('Thực đơn', () {
    testWidgets('check-in card when due; "Để sau" hides it', (tester) async {
      final prefs = await _pump(tester, const MealPlannerScreen());
      await _wait(tester);
      expect(find.byType(CheckInCard), findsOneWidget);
      expect(find.text('Cập nhật cân nặng'), findsOneWidget);
      expect(
          find.text('Đã 8 ngày từ lần cân trước. Cân lại để xem BMI và tiến '
              'độ sau một tuần theo Thực đơn.'),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Cập nhật'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Để sau'));
      await tester.pump();
      expect(find.text('Cập nhật cân nặng'), findsNothing);
      expect(prefs.getString('vl.checkin.snoozed.u_me'), '2026-10-29');
    });

    testWidgets('no card for a new account (no profile, no plan)',
        (tester) async {
      await _pump(tester, const MealPlannerScreen(),
          session: _session(_newUserId, 'Phạm Quang Huy'));
      await _wait(tester);
      expect(find.text('Cập nhật cân nặng'), findsNothing);
      expect(find.text('Theo dõi cân nặng'), findsNothing);
    });

    testWidgets(
        'sheet: validation, 99.9 keeps the input, save → review → '
        '"Về Thực đơn" with the new weight in the header', (tester) async {
      await _pump(tester, const MealPlannerScreen());
      await _wait(tester);
      await _openCheckInFromPlanner(tester);

      expect(find.text('Lần trước: 66,0 kg · 21/10'), findsOneWidget);
      expect(find.text('Chiều cao 172 cm · đổi trong Hồ sơ sức khoẻ'),
          findsOneWidget);
      expect(_field('Vòng eo (cm) — không bắt buộc'), findsOneWidget);
      expect(_field('Tỉ lệ mỡ cơ thể (%) — không bắt buộc'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pump();
      expect(find.text('Nhập cân nặng.'), findsOneWidget);

      await tester.enterText(_field('Cân nặng (kg)'), '65,45');
      await tester.pump();
      expect(find.text('Cân nặng chỉ lấy 1 chữ số thập phân'), findsOneWidget);
      await tester.enterText(_field('Cân nặng (kg)'), '25');
      await tester.pump();
      expect(find.text('Cân nặng từ 30 đến 250 kg'), findsOneWidget);
      await tester.enterText(_field('Vòng eo (cm) — không bắt buộc'), '30');
      await tester.enterText(
          _field('Tỉ lệ mỡ cơ thể (%) — không bắt buộc'), '80');
      await tester.pump();
      expect(find.text('Vòng eo từ 40 đến 200 cm'), findsOneWidget);
      expect(find.text('Tỉ lệ mỡ từ 3 đến 70 %'), findsOneWidget);

      await tester.enterText(_field('Vòng eo (cm) — không bắt buộc'), '70');
      await tester.enterText(
          _field('Tỉ lệ mỡ cơ thể (%) — không bắt buộc'), '26,2');
      await tester.enterText(_field('Cân nặng (kg)'), '99.9');
      await tester.pump();
      await _save(tester);
      expect(find.text('Chưa lưu được cân nặng. Thử lại sau ít phút.'),
          findsOneWidget);
      expect(find.text('99.9'), findsOneWidget, reason: 'input kept');
      expect(find.text('Tiến độ của bạn'), findsNothing);

      await tester.enterText(_field('Cân nặng (kg)'), '65,4');
      await tester.pump();
      expect(find.text('BMI mới ≈ 22,1 · Bình thường'), findsOneWidget);
      await _save(tester);

      expect(find.byType(ProgressReviewSheet), findsOneWidget);
      expect(find.text('Tiến độ của bạn'), findsOneWidget);
      expect(find.text('So với lần cân 21/10 (8 ngày trước)'), findsOneWidget);
      expect(find.text('Cân nặng: 66,0 → 65,4 kg (−0,6 kg)'), findsOneWidget);
      expect(find.text('BMI: 22,3 → 22,1 · Bình thường'), findsOneWidget);
      expect(find.text('Vòng eo: 70 → 70 cm · WHtR 0,41'), findsOneWidget);
      expect(find.textContaining('Tỉ lệ mỡ:'), findsNothing,
          reason: 'the previous weigh-in has no body fat');
      final before = _target(66), after = _target(65.4);
      expect(
          find.text('Mục tiêu năng lượng: ≈ ${Energy.formatKcal(before)} → '
              '≈ ${Energy.formatKcal(after)} kcal/ngày'),
          before == after ? findsNothing : findsOneWidget);
      expect(find.text('Chưa đúng hướng mục tiêu Tăng cơ'), findsOneWidget);
      expect(find.textContaining('giảm hơn 1 kg mỗi tuần'), findsNothing);
      expect(
          find.text(
              'Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế.'),
          findsWidgets);
      expect(find.text('Xem lịch sử'), findsOneWidget);

      await tester.tap(find.text('Về Thực đơn'));
      await _wait(tester, 1500);
      expect(find.byType(ProgressReviewSheet), findsNothing);
      expect(find.byType(MealPlannerScreen), findsOneWidget);
      expect(find.text('Cập nhật cân nặng'), findsNothing,
          reason: 'weighed in today');
      expect(find.text('65,4 kg'), findsOneWidget, reason: 'header weight');
    });

    testWidgets('review "Xem lịch sử" opens "Theo dõi cân nặng"',
        (tester) async {
      await _pump(tester, const MealPlannerScreen());
      await _wait(tester);
      await _openCheckInFromPlanner(tester);
      await tester.enterText(_field('Cân nặng (kg)'), '65,4');
      await _save(tester);
      await tester.tap(find.text('Xem lịch sử'));
      await _wait(tester, 1500);
      expect(find.byType(BodyMetricsScreen), findsOneWidget);
      expect(find.byType(ProgressReviewSheet), findsNothing);
      expect(find.text('Hiện tại 65,4 kg · BMI 22,1 (Bình thường)'),
          findsOneWidget);
    });

    testWidgets('header "Theo dõi cân nặng" opens the screen, not the editor',
        (tester) async {
      await _pump(tester, const MealPlannerScreen());
      await _wait(tester);
      await tester.tap(find.text('Theo dõi cân nặng'));
      await _wait(tester);
      expect(find.byType(BodyMetricsScreen), findsOneWidget);
      expect(find.text('Hồ sơ sức khoẻ'), findsNothing);
    });
  });

  group('Theo dõi cân nặng', () {
    testWidgets('summary, chart (Tháng/Tuần/Tất cả, Cân nặng/BMI), history',
        (tester) async {
      final prefs = await _pump(tester, const BodyMetricsScreen());
      await _wait(tester);
      expect(find.text('Hiện tại 66,0 kg · BMI 22,3 (Bình thường)'),
          findsOneWidget);
      expect(find.text('30 ngày qua: +0,7 kg'), findsOneWidget);
      expect(find.text('Mục tiêu: Tăng cơ'), findsOneWidget);
      expect(
          find.text('Khoảng cân nặng có BMI bình thường: 54,7 – 68,0 kg '
              '(chuẩn châu Á)'),
          findsOneWidget);

      // Tháng (default): the four weigh-ins of the last 30 days.
      expect(find.byType(WeightChart), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(WeightChart), matching: find.byType(CustomPaint)),
          findsOneWidget);
      expect(_chartLabelled('Cân nặng từ 65,3 đến 66,0 kg trong 30 ngày'),
          findsOneWidget);
      expect(find.text('21/10'), findsOneWidget, reason: 'last x label');

      await tester.tap(find.text('Tuần'));
      await tester.pump();
      expect(find.byType(WeightChart), findsNothing);
      expect(
          find.text('Chưa đủ dữ liệu để vẽ biểu đồ — cần ít nhất 2 lần cân '
              'trong khoảng này.'),
          findsOneWidget);

      await tester.tap(find.text('Tất cả'));
      await tester.pump();
      expect(_chartLabelled('Cân nặng từ 65,0 đến 66,0 kg từ 03/09 đến 21/10'),
          findsOneWidget);

      await tester.tap(find.text('BMI'));
      await tester.pump();
      expect(_chartLabelled('BMI từ 22,0 đến 22,3 từ 03/09 đến 21/10'),
          findsOneWidget);
      expect(find.textContaining('Vùng xanh: BMI bình thường (18,5 – 22,9)'),
          findsOneWidget);

      // History, newest first.
      expect(find.text('Lịch sử'), findsOneWidget);
      expect(find.text('Thứ Tư, 21/10'), findsOneWidget);
      expect(find.text('66,0 kg'), findsOneWidget);
      expect(find.text('+0,2 kg'), findsWidgets);
      expect(find.text('Eo 70 cm · WHtR 0,41'), findsOneWidget);
      expect(find.text('Mỡ 27 %'), findsOneWidget);
      expect(find.text('Mỡ 27,8 %'), findsOneWidget);
      expect(find.text('Từ Hồ sơ sức khoẻ'), findsOneWidget);

      // Reminder cadence, kept per account.
      expect(find.text('Nhắc cập nhật cân nặng'), findsOneWidget);
      await tester.tap(find.text('Mỗi tháng'));
      await tester.pump();
      expect(prefs.getString('vl.checkin.cadence.u_me'), 'month');
    });

    testWidgets('app bar "Cập nhật": the review says "Xong", no "Xem lịch sử"',
        (tester) async {
      await _pump(tester, const BodyMetricsScreen());
      await _wait(tester);
      await tester.tap(find.text('Cập nhật'));
      await _wait(tester, 1000);
      await tester.enterText(_field('Cân nặng (kg)'), '65,4');
      await _save(tester);
      expect(find.text('Tiến độ của bạn'), findsOneWidget);
      expect(find.text('Xem lịch sử'), findsNothing);
      expect(find.text('Về Thực đơn'), findsNothing);
      await tester.tap(find.text('Xong'));
      await _wait(tester, 1500);
      expect(find.byType(ProgressReviewSheet), findsNothing);
      expect(find.text('Thứ Năm, 29/10'), findsOneWidget);
      expect(find.text('−0,6 kg'), findsOneWidget);
      expect(find.text('Hiện tại 65,4 kg · BMI 22,1 (Bình thường)'),
          findsOneWidget);
    });

    testWidgets('no profile → set it up', (tester) async {
      await _pump(tester, const BodyMetricsScreen(),
          session: _session(_newUserId, 'Phạm Quang Huy'));
      await _wait(tester);
      expect(find.text('Thiết lập hồ sơ sức khoẻ để theo dõi BMI'),
          findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Thiết lập hồ sơ'), findsOneWidget);
      expect(find.text('Cập nhật'), findsNothing);
    });

    testWidgets('guests see the sign-in gate', (tester) async {
      await _pump(tester, const BodyMetricsScreen(), session: const {});
      await _wait(tester, 500);
      expect(find.byType(GuestGate), findsOneWidget);
      expect(find.byType(WeightChart), findsNothing);
    });
  });

  testWidgets('Tôi: "Theo dõi cân nặng" on the health card', (tester) async {
    await _pump(tester, const ProfileScreen());
    await _wait(tester, 3000);
    expect(find.text('Theo dõi cân nặng'), findsOneWidget);
    await tester.tap(find.text('Theo dõi cân nặng'));
    await _wait(tester);
    expect(find.byType(BodyMetricsScreen), findsOneWidget);
    expect(
        find.text('Hiện tại 66,0 kg · BMI 22,3 (Bình thường)'), findsOneWidget);
  });

  testWidgets('360 dp, text scale 1,3, dark: card, sheets, chart fit',
      (tester) async {
    // Any overflow in the new card, sheets or screen fails the test (the
    // card alone: the rest of Thực đơn is not part of this change).
    await _pump(
        tester,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [CheckInCard()],
          ),
        ),
        size: const Size(360, 2400),
        textScale: 1.3,
        theme: AppTheme.dark());
    await _wait(tester);
    expect(find.text('Cập nhật cân nặng'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'card');
    await _openCheckInFromPlanner(tester);
    expect(tester.takeException(), isNull, reason: 'sheet');
    await tester.enterText(_field('Cân nặng (kg)'), '64');
    await tester.enterText(_field('Vòng eo (cm) — không bắt buộc'), '90');
    await tester.pump();
    await _save(tester);
    expect(find.text('Tiến độ của bạn'), findsOneWidget);
    expect(find.text('Vòng eo/chiều cao ≥ 0,5 — nên lưu ý'), findsOneWidget);
    expect(find.textContaining('Bạn đang giảm hơn 1 kg mỗi tuần.'),
        findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'review');
    await tester.tap(find.text('Xem lịch sử'));
    await _wait(tester);
    expect(find.byType(BodyMetricsScreen), findsOneWidget);
    expect(find.byType(WeightChart), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'screen');
    await tester.tap(find.text('BMI'));
    await tester.tap(find.text('Tất cả'));
    await tester.pump();
    expect(find.byType(WeightChart), findsOneWidget);
    expect(find.text('Eo 90 cm · WHtR 0,52'), findsOneWidget);
  });
}
