// test/recipe_customization/recipe_detail_customize_test.dart
// The recipe page as a live preview (items 1–4): guests change servings,
// swap the riêu through the lock sheet, leave out an optional row and copy
// the shopping list without signing in; saving asks them to sign in and
// then carries on with the changes; members add the dish (or the saved
// variant) to Thực đơn and jump to the tab.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/core/widgets/shimmer.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/meal_planner_mock_data.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/mock_recipe_book.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_customization_controller.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/recipe_ingredient_row.dart';

import '../helpers/session_helpers.dart';

/// Thursday 29/10/2026, 9:00.
DateTime _now() => DateTime(2026, 10, 29, 9);

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context)
                .push(RecipeDetailScreen.route('l5', name: 'Bún riêu chay')),
            child: const Text('Mở công thức'),
          ),
        ),
      );
}

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(411, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      plannerClockProvider.overrideWithValue(_now),
    ],
    child: MaterialApp(
      navigatorObservers: [AppRouteStack()],
      home: const _Home(),
    ),
  ));
  return ProviderScope.containerOf(tester.element(find.byType(_Home)));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _signIn(WidgetTester tester) async {
  final done = signInAs(tester, minhAnhAccount);
  await tester.pump(const Duration(seconds: 2));
  await done;
  await tester.pump();
}

Future<void> _openRecipe(WidgetTester tester) async {
  await tester.tap(find.text('Mở công thức'));
  await _wait(tester, 2500); // the recipe, then the nutrition DB index
}

/// Taps without scrolling: the page is tall enough for the header and the
/// whole "Nguyên liệu" tab (scrolling would build the header away).
Future<void> _tap(WidgetTester tester, Finder finder, [int ms = 600]) async {
  await tester.tap(finder);
  await _wait(tester, ms);
}

/// The riêu through the lock: "Thành phần chính" → "Đổi riêu" → riêu nấm.
Future<void> _swapRieuToMushroom(WidgetTester tester,
    {String amount = '300 g'}) async {
  await _tap(tester, find.byTooltip('Thành phần chính — không bỏ được'));
  expect(find.text('Thành phần chính'), findsWidgets);
  expect(
      find.text('«Đậu hũ» tạo nên phần riêu — linh hồn của Bún riêu chay. '
          'Bỏ đi thì món không còn là Bún riêu chay, nên không thể bỏ.'),
      findsOneWidget);
  expect(
      find.text('Bạn có thể đổi sang: Nấm rơm băm nhuyễn, Đậu nành ngâm xay.'),
      findsOneWidget);
  await _tap(tester, find.widgetWithText(FilledButton, 'Đổi riêu'));
  expect(find.text('Đổi riêu — giữ đúng món'), findsOneWidget);
  expect(find.text('Giữ nguyên: Đậu hũ · $amount'), findsOneWidget);
  expect(find.text('−66 kcal/phần'), findsOneWidget);
  expect(find.text('+16 kcal/phần'), findsOneWidget);
  await _tap(tester, find.text('Nấm rơm băm nhuyễn · $amount'), 300);
  await _tap(tester, find.widgetWithText(FilledButton, 'Áp dụng'));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  // Real Roboto metrics (shipped with the SDK), like m3_widgets_test.
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
      'guest: servings, swap through the lock, leave out, copy the list; '
      'saving signs in and keeps the changes; the variant links back',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final container = await _pumpApp(tester);
    await _openRecipe(tester);
    expect(find.text('580 kcal / phần'), findsOneWidget);
    expect(find.text('cho 2 phần'), findsOneWidget);
    expect(find.text('Mỗi phần: 580 kcal'), findsOneWidget);
    expect(find.text('Năng lượng'), findsOneWidget);
    expect(find.text('Đăng nhập để so với mục tiêu bữa ăn của bạn'),
        findsOneWidget);

    // "Nấu cho 3 người": amounts only.
    await _tap(tester, find.byTooltip('Tăng số người'), 300);
    expect(find.text('3 người'), findsOneWidget);
    expect(find.text('cho 3 phần'), findsOneWidget);
    expect(find.text('600 g'), findsOneWidget);
    expect(find.text('1,5 củ'), findsOneWidget);
    expect(find.text('Về 2 người'), findsOneWidget);
    expect(find.text('580 kcal / phần'), findsOneWidget);
    expect(find.text('Tổng 3 phần: 1.740 kcal'), findsOneWidget);
    expect(find.text('Tham gia cộng đồng VeganLife'), findsNothing);

    // The riêu is a signature: no "Bỏ", only same-role swaps.
    expect(find.byTooltip('Bỏ Đậu hũ'), findsNothing);
    expect(find.textContaining('Thành phần chính'), findsOneWidget);
    await _swapRieuToMushroom(tester, amount: '450 g');
    expect(find.text('≈ 514 kcal / phần'), findsOneWidget);
    expect(find.text('Năng lượng (ước tính)'), findsOneWidget);
    expect(
        find.text('Mỗi phần: ≈ 514 kcal (gốc 580 kcal, −66)'), findsOneWidget);
    expect(find.text('Tổng 3 phần: ≈ 1.542 kcal'), findsOneWidget);
    expect(find.text('Thay cho Đậu hũ'), findsOneWidget);
    expect(find.text('Hoàn tác'), findsOneWidget);
    expect(find.text('Đã chỉnh 1 nguyên liệu'), findsOneWidget);
    expect(
        find.text('Bạn đang xem thử — đăng nhập để lưu công thức đã chỉnh '
            'hoặc thêm vào Thực đơn.'),
        findsOneWidget);

    // Leave out the optional rau muống.
    await _tap(tester, find.byTooltip('Bỏ Rau muống chẻ'), 300);
    expect(find.text('Đã bỏ'), findsOneWidget);
    expect(find.text('Thêm lại'), findsOneWidget);
    expect(find.text('≈ 495 kcal / phần'), findsOneWidget);
    expect(find.text('Đã chỉnh 2 nguyên liệu'), findsOneWidget);

    await _tap(tester, find.text('Sao chép danh sách đi chợ'), 300);
    expect(
        copied,
        'Đi chợ: Bún riêu chay (3 người)\n'
        '- Bún tươi: 600 g\n'
        '- Cà chua: 6 quả\n'
        '- Nấm rơm băm nhuyễn: 450 g\n'
        '- Nấm rơm: 300 g\n'
        '- Củ cải trắng: 1,5 củ\n'
        '- Bắp ngô: 3 bắp\n'
        '- Mắm ruốc chay: 1,5 muỗng canh\n'
        '- Hành tím: 4,5 củ');
    expect(find.text('Đã sao chép danh sách đi chợ'), findsOneWidget);

    // "Thêm vào Thực đơn" asks to sign in; "Để sau" changes nothing.
    await _tap(tester, find.text('Thêm vào Thực đơn'));
    expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
    await _tap(tester, find.text('Để sau'));
    expect(find.text('Tham gia cộng đồng VeganLife'), findsNothing);
    expect(find.text('≈ 495 kcal / phần'), findsOneWidget);

    // Save → sign in → the dialog opens with the changes intact.
    await _tap(tester, find.text('Lưu thành công thức của tôi'));
    expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, 'Đăng nhập'));
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('Thành viên')); // test-account chip
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump(const Duration(seconds: 2));
    await _wait(tester, 1000);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Lưu công thức đã chỉnh'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Bún riêu chay (tuỳ chỉnh)'),
        findsOneWidget);
    expect(find.text('≈ 495 kcal / phần'), findsOneWidget,
        reason: 'signing in kept the preview');
    expect(find.byType(Shimmer), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pump();
    expect(find.text('Đang lưu…'), findsOneWidget);
    await _wait(tester, 1500);
    expect(find.text('Lưu công thức đã chỉnh'), findsNothing);
    expect(find.text('Đã lưu vào Công thức của tôi'), findsOneWidget);
    final saved = MockRecipeBook.userRecipes('u_me').single;
    expect(saved['caloriesCache'], 495);
    expect(saved['basedOnRecipeId'], 'l5');

    // "Xem" opens the variant; its link goes back to the open original.
    await tester.tap(find.text('Xem'));
    await _wait(tester, 2000);
    expect(find.textContaining('Biến thể của «Bún riêu chay»'), findsOneWidget);
    expect(find.text('495 kcal / phần'), findsOneWidget);
    expect(
        find.text('Đã đổi Đậu hũ → Nấm rơm băm nhuyễn · Đã bỏ Rau muống chẻ'),
        findsOneWidget);
    expect(
        find.byType(RecipeDetailScreen, skipOffstage: false), findsNWidgets(2));
    await tester.tap(find.textContaining('Biến thể của «Bún riêu chay»'));
    await _wait(tester, 1000);
    expect(find.byType(RecipeDetailScreen, skipOffstage: false), findsOneWidget,
        reason: 'back to the original, not a copy');
    expect(find.text('≈ 495 kcal / phần'), findsOneWidget);
    expect(
        container.read(recipeCustomizationProvider('l5')).choices.changeCount,
        2);
    await _dispose(tester);
  });

  testWidgets('signing in on the recipe page keeps the tab and the content',
      (tester) async {
    await _pumpApp(tester);
    await _openRecipe(tester);
    await tester.tap(find.widgetWithText(Tab, 'Cách làm'));
    await _wait(tester, 750);
    expect(find.textContaining('Hầm củ cải và bắp ngô'), findsOneWidget);
    await _signIn(tester);
    await _wait(tester, 500);
    expect(find.byType(Shimmer), findsNothing);
    expect(find.textContaining('Hầm củ cải và bắp ngô'), findsOneWidget);
    await _wait(tester, 1500);
    await _dispose(tester);
  });

  testWidgets(
      'member: compares with the closest meal, adds the dish to Friday '
      'dinner as "Từ công thức", then "Xem Thực đơn" opens the tab',
      (tester) async {
    final container = await _pumpApp(tester);
    await _signIn(tester);
    await _openRecipe(tester);

    final profile =
        HealthProfileDto.fromJson(mockHealthProfileJson(syncProvider: 'none'))
            .toEntity();
    final dinner = slotTargets(profile)[MealSlot.dinner]!;
    final target = Energy.formatKcal(dinner);
    expect(find.text('So với mục tiêu:'), findsOneWidget);
    expect(find.text('Bữa tối'), findsOneWidget);
    expect(
        find.text('Vừa với mục tiêu bữa tối (≈ $target kcal)'), findsOneWidget);

    await _tap(tester, find.text('Thêm vào Thực đơn'), 1500);
    expect(find.text('Ngày'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'T5 29/10'))
            .selected,
        isTrue,
        reason: 'today by default');
    expect(
        find.widgetWithText(ChoiceChip, 'Phụ tối (bữa thêm)'), findsOneWidget);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'T6 30/10'), 300);
    expect(
        find.text('Thực đơn tính 1 phần cho bạn: 580 kcal · mục tiêu bữa tối '
            '≈ $target kcal'),
        findsOneWidget);
    expect(find.textContaining('Đang có: '), findsOneWidget);
    await _tap(tester, find.text('Thêm vào bữa tối · T6 30/10'), 2000);

    expect(find.text('Đã thêm «Bún riêu chay» vào bữa tối, Thứ Sáu, 30/10.'),
        findsOneWidget);
    final state = container.read(mealPlanControllerProvider).requireValue;
    final friday = DateTime(2026, 10, 30);
    final meal = state.plan!.dayFor(friday)!.meals[MealSlot.dinner]!;
    expect(meal.id, 'l5');
    expect(meal.source, MealSource.recipe);
    expect(meal.portion, 1);
    expect(state.selectedDate, friday);

    await tester.tap(find.text('Xem Thực đơn'));
    await _wait(tester, 600);
    expect(container.read(shellTabProvider), ShellTab.planner);
    expect(find.byType(RecipeDetailScreen), findsNothing);
    await _dispose(tester);
  });

  testWidgets(
      'member: a changed recipe is saved first and placed as '
      '"Công thức của tôi" with the previewed energy', (tester) async {
    final container = await _pumpApp(tester);
    await _signIn(tester);
    await _openRecipe(tester);
    await _swapRieuToMushroom(tester);
    expect(find.text('≈ 514 kcal / phần'), findsOneWidget);

    await _tap(tester, find.text('Thêm vào Thực đơn'), 1500);
    expect(
        find.text('Món đã chỉnh sẽ được lưu vào Công thức của tôi trước khi '
            'thêm.'),
        findsOneWidget);
    expect(find.textContaining('Thực đơn tính 1 phần cho bạn: ≈ 514 kcal'),
        findsOneWidget);
    await _tap(tester, find.text('Thêm vào bữa tối · T5 29/10'), 3000);

    expect(
        find.text('Đã thêm «Bún riêu chay (tuỳ chỉnh)» vào bữa tối, '
            'Thứ Năm, 29/10.'),
        findsOneWidget);
    final meal = container
        .read(mealPlanControllerProvider)
        .requireValue
        .plan!
        .dayFor(DateTime(2026, 10, 29))!
        .meals[MealSlot.dinner]!;
    expect(meal.source, MealSource.userRecipe);
    expect(meal.id, startsWith('ur_'));
    expect(meal.nutrition.calories, 514);
    expect(MockRecipeBook.userRecipes('u_me'), hasLength(1));

    // Same changes again: the saved variant is reused, not saved twice.
    await _tap(tester, find.text('Thêm vào Thực đơn'), 1500);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Bữa trưa'), 300);
    await _tap(tester, find.text('Thêm vào bữa trưa · T5 29/10'), 2000);
    expect(MockRecipeBook.userRecipes('u_me'), hasLength(1));
    expect(MockRecipeCommunityStore.variantCount, 1);
    await _dispose(tester);
  });

  testWidgets('the swap sheet tags options against the member\'s allergies',
      (tester) async {
    await _pumpApp(tester);
    await _signIn(tester);
    await _openRecipe(tester);
    // Minh Anh is allergic to peanuts only: nothing here conflicts.
    expect(find.textContaining('bạn đã khai báo dị ứng'), findsNothing);
    final bun = find.ancestor(
        of: find.text('Bún tươi'), matching: find.byType(RecipeIngredientRow));
    await _tap(tester, find.descendant(of: bun, matching: find.text('Đổi')));
    expect(find.text('Đổi Bún tươi'), findsOneWidget);
    expect(find.text('Chưa rõ năng lượng'), findsOneWidget);
    await _tap(tester, find.text('Bánh phở tươi · 400 g'), 300);
    await _tap(tester, find.widgetWithText(FilledButton, 'Áp dụng'));
    expect(find.text('≈ 580 kcal / phần'), findsOneWidget);
    expect(
        find.text('Chưa có số liệu dinh dưỡng của «Bánh phở tươi» — năng '
            'lượng là ước tính.'),
        findsOneWidget);
    await _tap(tester, find.text('Đặt lại'), 300);
    expect(find.text('580 kcal / phần'), findsOneWidget);
    await _dispose(tester);
  });
}
