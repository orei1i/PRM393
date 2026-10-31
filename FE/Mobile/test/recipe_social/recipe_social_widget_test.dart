// test/recipe_social/recipe_social_widget_test.dart
// Reviews, rating and private notes on the recipe page (item 5): guests
// read reviews and are asked to sign in to write (then the sheet opens);
// a member's 4★ moves the header line to "4,5 · 6 đánh giá"; edit (#fail
// keeps the text) and delete with confirmation; the note card in "Cách
// làm"; private recipes have no "Đánh giá" tab; "Xem thêm đánh giá".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/user_avatar.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_review_model.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';

import '../helpers/session_helpers.dart';

class _Home extends StatelessWidget {
  const _Home(this.recipeId);

  final String recipeId;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).push(RecipeDetailScreen.route(recipeId)),
            child: const Text('Mở công thức'),
          ),
        ),
      );
}

Future<void> _pumpApp(WidgetTester tester, String recipeId) async {
  tester.view
    ..physicalSize = const Size(411, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      plannerClockProvider.overrideWithValue(() => DateTime(2026, 10, 29, 9)),
    ],
    child: MaterialApp(
      navigatorObservers: [AppRouteStack()],
      home: _Home(recipeId),
    ),
  ));
}

/// Frames for mock latency without waiting on endless animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder, [int ms = 600]) async {
  await tester.tap(finder);
  await _wait(tester, ms);
}

Future<void> _open(WidgetTester tester) =>
    _tap(tester, find.text('Mở công thức'), 2500);

Future<void> _signIn(WidgetTester tester) async {
  final done = signInAs(tester, minhAnhAccount);
  await tester.pump(const Duration(seconds: 2));
  await done;
  await _wait(tester, 1500);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Finder get _reviewText =>
    find.widgetWithText(TextFormField, 'Nhận xét (không bắt buộc)');

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

  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
  });

  testWidgets(
      'guest reads reviews; writing signs in then opens the sheet; write, '
      'edit (#fail keeps the text) and delete move the header line',
      (tester) async {
    await _pumpApp(tester, 'l5');
    await _open(tester);
    expect(find.widgetWithText(Tab, 'Đánh giá'), findsOneWidget);
    expect(find.text('★ 4,6 · 5 đánh giá'), findsOneWidget);

    // The header line opens the tab.
    await _tap(tester, find.text('★ 4,6 · 5 đánh giá'), 1000);
    expect(find.text('4,6'), findsOneWidget);
    expect(find.text('5 đánh giá'), findsOneWidget);
    expect(find.text('Lê Quang Tâm'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(find.textContaining('(đã sửa)'), findsOneWidget);
    expect(find.text('Bạn đã nấu món này?'), findsOneWidget);
    expect(find.text('Hoàng Nam'), findsOneWidget);

    // "Viết đánh giá" asks a guest to sign in; "Để sau" changes nothing.
    await _tap(tester, find.text('Viết đánh giá'));
    expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
    await _tap(tester, find.text('Để sau'));
    expect(find.text('Đánh giá công thức'), findsNothing);

    // Sign in from the sheet → the review sheet opens.
    await _tap(tester, find.text('Viết đánh giá'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Đăng nhập'));
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('Thành viên'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump(const Duration(seconds: 2));
    await _wait(tester, 2000);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Đánh giá công thức'), findsOneWidget);

    // Stars are required; the text is optional but ≥ 10 characters.
    await _tap(tester, find.text('Gửi đánh giá'), 300);
    expect(find.text('Chọn số sao'), findsOneWidget);
    await _tap(tester, find.byTooltip('4 sao'), 300);
    expect(find.text('Ngon'), findsOneWidget);
    await tester.enterText(_reviewText, 'Ngắn');
    await _tap(tester, find.text('Gửi đánh giá'), 300);
    expect(find.text('Nhận xét cần ít nhất 10 ký tự'), findsOneWidget);
    await tester.enterText(_reviewText, 'Riêu nấm ngon, dễ nấu cho cả nhà.');
    await tester.tap(find.text('Gửi đánh giá'));
    await tester.pump();
    expect(find.text('Đang gửi…'), findsOneWidget);
    await _wait(tester, 1500);
    expect(find.text('Đánh giá công thức'), findsNothing);
    expect(find.text('Đã gửi đánh giá'), findsOneWidget);
    expect(find.text('★ 4,5 · 6 đánh giá'), findsOneWidget);
    expect(find.text('4,5'), findsOneWidget);
    expect(find.text('6 đánh giá'), findsOneWidget);
    expect(find.text('Đánh giá của bạn'), findsOneWidget);
    expect(find.text('Riêu nấm ngon, dễ nấu cho cả nhà.'), findsOneWidget);

    // Edit: a failing save keeps the sheet and the text.
    await _tap(tester, find.text('Sửa'));
    expect(find.text('Sửa đánh giá của bạn'), findsOneWidget);
    expect(
        find.widgetWithText(TextFormField, 'Riêu nấm ngon, dễ nấu cho cả nhà.'),
        findsOneWidget);
    await tester.enterText(_reviewText, 'Lần này thử #fail nhé');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'), 1500);
    expect(find.text('Chưa gửi được đánh giá. Thử lại nhé.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Lần này thử #fail nhé'),
        findsOneWidget);
    await _tap(tester, find.byTooltip('5 sao'), 300);
    await tester.enterText(_reviewText, 'Lần này thêm nấm, ngon hơn hẳn.');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'), 1500);
    expect(find.text('Sửa đánh giá của bạn'), findsNothing);
    expect(find.text('Đã cập nhật đánh giá'), findsOneWidget);
    expect(find.text('★ 4,7 · 6 đánh giá'), findsOneWidget);
    expect(find.text('Lần này thêm nấm, ngon hơn hẳn.'), findsOneWidget);

    // Delete with confirmation.
    await _tap(tester, find.widgetWithText(TextButton, 'Xoá'), 300);
    expect(find.text('Xoá đánh giá của bạn?'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, 'Huỷ'), 300);
    expect(find.text('Đánh giá của bạn'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, 'Xoá'), 300);
    await _tap(tester, find.widgetWithText(FilledButton, 'Xoá'), 1200);
    expect(find.text('Đã xoá đánh giá'), findsOneWidget);
    expect(find.text('★ 4,6 · 5 đánh giá'), findsOneWidget);
    expect(find.text('Bạn đã nấu món này?'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets(
      'notes: a guest is asked to sign in; a member adds, edits (#fail keeps '
      'the text) and deletes the note in "Cách làm"', (tester) async {
    await _pumpApp(tester, 'l5');
    await _open(tester);
    await _tap(tester, find.widgetWithText(Tab, 'Cách làm'), 750);
    expect(find.text('Ghi chú của tôi'), findsOneWidget);
    expect(find.text('Chỉ mình bạn thấy'), findsOneWidget);
    expect(
        find.text('Thêm ghi chú riêng: mẹo nêm nếm, điều chỉnh cho lần sau…'),
        findsOneWidget);
    expect(find.textContaining('Hầm củ cải và bắp ngô'), findsOneWidget,
        reason: 'the steps stay below');
    await _tap(tester, find.text('Thêm ghi chú'));
    expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
    await _tap(tester, find.text('Để sau'));

    await _signIn(tester);
    await _tap(tester, find.text('Thêm ghi chú'), 1000);
    expect(find.text('Ghi chú của tôi'), findsNWidgets(2), reason: 'sheet');
    await tester.enterText(
        find.byType(TextField), 'Nêm mắm ruốc sau cùng cho thơm.');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'), 1200);
    expect(find.text('Đã lưu ghi chú'), findsOneWidget);
    expect(find.text('Nêm mắm ruốc sau cùng cho thơm.'), findsOneWidget);
    expect(find.text('Cập nhật vừa xong'), findsOneWidget);

    await _tap(tester, find.text('Sửa'));
    await tester.enterText(find.byType(TextField), 'Thử ghi chú #fail');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'), 1200);
    expect(find.text('Chưa lưu được ghi chú. Thử lại nhé.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Thử ghi chú #fail'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Lần sau bớt mắm ruốc.');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lưu'), 1200);
    expect(find.text('Lần sau bớt mắm ruốc.'), findsOneWidget);

    await _tap(tester, find.text('Sửa'));
    await _tap(tester, find.text('Xoá ghi chú'), 300);
    expect(find.text('Xoá ghi chú?'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, 'Xoá'), 1200);
    expect(find.text('Đã xoá ghi chú'), findsOneWidget);
    expect(find.text('Lần sau bớt mắm ruốc.'), findsNothing);
    expect(find.text('Thêm ghi chú'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets(
      'a saved variant (private) has no "Đánh giá" tab or rating line but '
      'takes notes; a catalogue recipe without reviews invites one',
      (tester) async {
    final variant = await tester.runAsync(() async =>
        (await MockRecipeCommunityRepository(userId: 'u_me').createVariant(
                'l5',
                const CreateVariantRequestDto(
                    name: 'Bún riêu nấm', swaps: {'rieu': 'rieu_nam'})))
            .toEntity());
    await _pumpApp(tester, variant!.id);
    await _signIn(tester);
    await _open(tester);
    expect(find.text('Bún riêu nấm'), findsWidgets);
    expect(find.widgetWithText(Tab, 'Nguyên liệu'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Đánh giá'), findsNothing);
    expect(find.textContaining('đánh giá'), findsNothing);
    expect(find.text('Chưa có đánh giá'), findsNothing);
    await _tap(tester, find.widgetWithText(Tab, 'Cách làm'), 1200);
    expect(find.text('Ghi chú của tôi'), findsOneWidget);
    expect(find.text('Thêm ghi chú'), findsOneWidget);
    await _dispose(tester);

    await _pumpApp(tester, 'menu_3');
    await _open(tester);
    expect(find.text('Chưa có đánh giá'), findsOneWidget);
    await _tap(tester, find.text('Chưa có đánh giá'), 1000);
    expect(find.text('Chưa có đánh giá'), findsNWidgets(2));
    expect(find.text('Hãy là người đầu tiên chia sẻ cảm nhận về món này.'),
        findsOneWidget);
    expect(find.text('Viết đánh giá'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('"Xem thêm đánh giá" loads the next page', (tester) async {
    await tester.runAsync(() => Future.wait([
          for (var i = 0; i < 12; i++)
            MockRecipeCommunityRepository(userId: 'u_p$i').upsertMyReview(
                'menu_3', const UpsertReviewRequestDto(rating: 3)),
        ]));
    await _pumpApp(tester, 'menu_3');
    await _open(tester);
    expect(find.text('★ 3,0 · 12 đánh giá'), findsOneWidget);
    await _tap(tester, find.widgetWithText(Tab, 'Đánh giá'), 1000);
    expect(find.byType(UserAvatar), findsNWidgets(10));
    await _tap(tester, find.text('Xem thêm đánh giá'), 1200);
    expect(find.byType(UserAvatar), findsNWidgets(12));
    expect(find.text('Xem thêm đánh giá'), findsNothing);
    await _dispose(tester);
  });
}
