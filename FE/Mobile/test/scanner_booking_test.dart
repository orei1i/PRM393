// test/scanner_booking_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/chef/domain/chef_specialties.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef/presentation/widgets/booking_sheet.dart';
import 'package:veganlife_mobile/features/commerce/data/models/order_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/chef_application_screen.dart';
import 'package:veganlife_mobile/features/scanner/domain/entities/detected_ingredient.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/bounding_box_overlay.dart';

void main() {
  group('scanner: confirming a low-confidence item', () {
    const spinach = DetectedIngredient(
      id: 'det_leafy',
      name: 'Rau chân vịt',
      confidence: 0.58,
      isVegan: true,
      alternatives: [
        IngredientAlternative(name: 'Rau muống', confidence: 0.21),
        IngredientAlternative(name: 'Cải thìa', confidence: 0.12),
      ],
      confirmed: false,
    );

    DetectedIngredient confirmAs(String name) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(scannerControllerProvider.notifier)
        ..restore(spinach, 0)
        ..confirm(spinach.id, name: name);
      final state = container.read(scannerControllerProvider);
      expect(state.pendingCount, 0);
      return state.items.single;
    }

    test('an alternative takes its own score and is user-verified', () {
      final item = confirmAs('Rau muống');
      expect(item.name, 'Rau muống');
      expect(item.confidence, 0.21);
      expect(item.confirmed, isTrue);
      expect(item.userVerified, isTrue);
    });

    test('the detected label is no longer shown as uncertain', () {
      final item = confirmAs('Rau chân vịt');
      expect(item.confidence, 0.58);
      expect(item.confirmed, isTrue);
      expect(item.userVerified, isTrue);
    });

    test('a typed name counts as certain', () {
      final item = confirmAs('Cải bó xôi');
      expect(item.name, 'Cải bó xôi');
      expect(item.confidence, 1.0);
      expect(item.userVerified, isTrue);
      expect(item.isVegan, isTrue, reason: '"bó" is not "bò"');
    });

    test('a typed non-vegan name is checked again and not savable', () {
      final item = confirmAs('Trứng cút');
      expect(item.isVegan, isFalse);
      expect(item.nonVeganReason, 'Có nguồn gốc động vật: trứng');
      expect(item.veganAlternatives, ['Đậu hũ non']);
      expect(item.savable, isFalse);
    });
  });

  test('detection chips are clamped inside the preview', () {
    // A 400 × 800 preview with 4 px insets.
    const bounds = Rect.fromLTRB(4, 4, 396, 796);
    DetectionChipPlacement place(Rect box) => layoutDetectionChips([
          DetectionChips(
              box: box, label: const Size(120, 22), badge: const Size(60, 20)),
        ], bounds: bounds)
            .single;
    bool inside(Rect r) =>
        r.left >= bounds.left &&
        r.top >= bounds.top &&
        r.right <= bounds.right &&
        r.bottom <= bounds.bottom;

    // Box cropped off the left / top edge.
    final cropped = place(const Rect.fromLTWH(-90, -30, 150, 120));
    expect(cropped.label.topLeft, const Offset(4, 4));
    expect(inside(cropped.badge), isTrue);
    // Label that would run past the right edge.
    expect(place(const Rect.fromLTWH(350, 322, 60, 100)).label.topLeft,
        const Offset(276, 300));
    // Vegan badge of a box cropped at the bottom-right corner.
    final corner = place(const Rect.fromLTWH(330, 700, 120, 150));
    expect(inside(corner.badge), isTrue);
    expect(inside(corner.label), isTrue);
    // Fully visible: the name on the top edge, the badge in the corner.
    final plain = place(const Rect.fromLTWH(100, 122, 200, 100));
    expect(plain.label.topLeft, const Offset(100, 100));
    expect(plain.badge.topLeft, const Offset(236, 198));
  });

  group('add a scanned dish to the meal plan', () {
    test('mock repository updates the current plan and flags allergens',
        () async {
      final repo = MockMealPlannerRepository();
      final today = dateOnly(DateTime.now());
      final day = await repo.addMealToCurrentPlan(AddMealRequestDto(
        date: today,
        slot: MealSlot.lunch,
        name: 'Gỏi cuốn chay',
        calories: 450,
        prepMinutes: 20,
        ingredients: const ['Bánh tráng', 'Đậu phộng rang', 'Nấm mèo'],
        sourceId: 'menu_x',
      ));
      final lunch = day.meals['lunch']!;
      expect(lunch.name, 'Gỏi cuốn chay');
      expect(lunch.nutrition.calories, 450);
      expect(lunch.allergens, contains('peanut'));
      // Whole-word match: "nấm mèo" is not sesame ("mè").
      expect(lunch.allergens, isNot(contains('sesame')));

      final plan = await repo.getCurrentMealPlan();
      final saved = plan!.days.firstWhere((d) => isSameDay(d.date, today));
      expect(saved.meals['lunch']!.id, lunch.id);
    });

    test('controller adds to today, warns about allergies and can undo',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(mealPlanControllerProvider.notifier);

      final added = await controller.addMealToToday(
        slot: MealSlot.dinner,
        name: 'Bánh mì bơ đậu phộng',
        calories: 480,
        ingredients: const ['Bánh mì', 'Đậu phộng'],
        sourceId: 'menu_peanut',
      );
      // Mock profile is allergic to peanut: flagged like the planner does.
      expect(added.allergenConflicts, ['peanut']);
      expect(added.replaced, isNotNull);

      var state = container.read(mealPlanControllerProvider).requireValue;
      expect(isSameDay(state.selectedDate, DateTime.now()), isTrue);
      expect(state.selectedDay!.meals[MealSlot.dinner]!.name,
          'Bánh mì bơ đậu phộng');
      expect(state.selectedDay!.conflictCount(state.profile.allergies),
          greaterThan(0));

      await controller.undoAddMeal(added);
      state = container.read(mealPlanControllerProvider).requireValue;
      expect(state.selectedDay!.meals[MealSlot.dinner]!.id, added.replaced!.id);
    });
  });

  group('booking sheet', () {
    final chef = Chef(
      id: 'chef_1',
      name: 'Lê Quang Tâm',
      headline: 'Đầu bếp chay',
      specialties: const ['Ẩm thực chay Việt'],
      rating: 4.9,
      reviewCount: 10,
      yearsExperience: 8,
      city: 'Huế',
      startingPriceVnd: 350000,
      services: const [
        ChefService(
            id: 'svc_1',
            chefId: 'chef_1',
            title: 'Tư vấn thực đơn gia đình 7 ngày',
            description:
                'Gọi video 60 phút + file thực đơn & danh sách đi chợ.',
            type: ServiceType.consult,
            durationMinutes: 60,
            price: 350000),
        ChefService(
            id: 'svc_2',
            chefId: 'chef_1',
            title: 'Dạy nấu 3 món chay qua video',
            description: 'Nấu cùng chef, nguyên liệu tự chuẩn bị.',
            type: ServiceType.consult,
            durationMinutes: 180,
            price: 1200000),
      ],
      availableSlots: [
        for (var d = 1; d <= 6; d++)
          for (final h in [9, 14, 19])
            DateTime.now().add(Duration(days: d)).copyWith(
                hour: h, minute: 0, second: 0, millisecond: 0, microsecond: 0),
      ],
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<OrderDto>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => BookingSheet(chef: chef),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('submit bar is pinned above the gesture bar and keyboard',
        (tester) async {
      tester.view
        ..physicalSize = const Size(600, 700)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 24, bottom: 24)
        ..viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);

      await openSheet(tester);
      final submit =
          find.widgetWithText(FilledButton, 'Tiếp tục thanh toán · 350.000đ');
      // Reachable without scrolling, clear of the 24 px gesture bar.
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(700 - 24));
      expect(find.text('Chưa chọn giờ'), findsOneWidget);

      // Typing the note: the bar rides on top of the keyboard.
      await tester.showKeyboard(find.byType(TextField));
      tester.view
        ..viewInsets = const FakeViewPadding(bottom: 300)
        ..padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(700 - 300));
    });
  });

  testWidgets('chef application: submit scrolls to and focuses the bad field',
      (tester) async {
    tester.view
      ..physicalSize = const Size(400, 560)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ChefApplicationScreen())));

    await tester.tap(find.text(chefSpecialties.first));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Số năm kinh nghiệm'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Thành phố'), 'Huế');
    final bio = find.widgetWithText(TextFormField, 'Giới thiệu');
    await tester.enterText(bio, 'Quá ngắn');
    await tester.enterText(
        find.widgetWithText(TextField,
            'VD: Chứng chỉ Đầu bếp chuyên nghiệp — CĐ Du lịch Sài Gòn'),
        'Chứng chỉ Bếp chay');
    await tester.ensureVisible(find.byTooltip('Thêm chứng chỉ'));
    await tester.tap(find.byTooltip('Thêm chứng chỉ'));
    await tester.pump();

    final submit = find.widgetWithText(FilledButton, 'Gửi hồ sơ');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final bioEditable = tester.widget<EditableText>(
        find.descendant(of: bio, matching: find.byType(EditableText)));
    expect(bioEditable.focusNode.hasFocus, isTrue);
    final rect = tester.getRect(bio);
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.top, lessThan(560));
    expect(find.text('Viết ít nhất 50 ký tự để học viên hiểu về bạn.'),
        findsOneWidget);
    expect(find.text('Hồ sơ chưa hợp lệ: giới thiệu.'), findsOneWidget);
  });
}
