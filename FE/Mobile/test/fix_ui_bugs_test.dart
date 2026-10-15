// test/fix_ui_bugs_test.dart
//
// Regression tests for the UI bugs B50, B64, X01, B39, B37, B63, B56f, B40c
// and A17 (screenshots in FE/_screenshots/final/mobile).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/chef/data/mock_chef_repository.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef/presentation/widgets/booking_sheet.dart';
import 'package:veganlife_mobile/features/chef/presentation/widgets/purchase_sheet.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/data/models/order_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/chef_suggestion_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/pantry_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/user_recipe_form_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/macro_progress_bar.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_picker_sheet.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_slot_card.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/pantry_section.dart';
import 'package:veganlife_mobile/features/scanner/data/mock_scanner_repository.dart';
import 'package:veganlife_mobile/features/scanner/data/scan_image_source.dart';
import 'package:veganlife_mobile/features/scanner/domain/entities/detected_ingredient.dart';
import 'package:veganlife_mobile/features/scanner/domain/scan_mode.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scan_mode_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/bounding_box_overlay.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/mock_fridge_preview.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/scan_button.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/scanned_ingredients_sheet.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

/// "Chọn ảnh" without a real gallery.
class _FakeGallery implements ScanImageSource {
  _FakeGallery(this.result);

  final Uint8List? result;
  int calls = 0;

  @override
  Future<Uint8List?> pickFromGallery() async {
    calls++;
    return result;
  }
}

Future<SharedPreferences> _prefs([Map<String, Object> values = _minhAnh]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<SharedPreferences> _pump(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> session = _minhAnh,
  Size size = const Size(411, 913),
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(session);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: home),
  ));
  return prefs;
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Unmounts the tree and lets pending mock timers finish.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

ProviderContainer _container(SharedPreferences prefs) {
  final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  // Real Roboto metrics (shipped with the SDK): the default test font draws
  // every glyph as a wide square, which would make every chip too wide.
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
    MockCommerceDb.reset();
    MockMealPlannerRepository.reset();
  });

  // ------------------------------------------------------------------ B50 --
  group('B50 scanner overlay: collision-aware chips', () {
    late List<DetectedIngredient> seeded;
    setUpAll(() async {
      final result = await MockScannerRepository().scanImage(Uint8List(0));
      seeded = result.items.map((d) => d.toEntity()).toList();
    });

    for (final (name, frame) in [
      ('16:9 camera', const Size(720, 1280)),
      ('3:4 sample fridge', MockFridgePreview.frameSize),
    ]) {
      testWidgets(
          'seeded scan, $name: no chip covers another chip or a '
          'neighbouring box, all inside the preview', (tester) async {
        tester.view
          ..physicalSize = const Size(411, 913)
          ..devicePixelRatio = 1
          ..padding = const FakeViewPadding(top: 24);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: BoundingBoxOverlay(
                items: seeded, frameSize: frame, onTapItem: (_) {}),
          ),
        ));
        await tester.pump(const Duration(seconds: 2)); // pop-in animations
        expect(tester.takeException(), isNull);

        const viewport = Rect.fromLTWH(0, 0, 411, 913);
        final boxes = {
          for (final i in seeded)
            i.id: tester
                .getRect(find.byKey(ValueKey('scan-box-${i.id}')))
                .intersect(viewport),
        };
        final chips = <String, Rect>{
          for (final i in seeded) ...{
            'label ${i.id}':
                tester.getRect(find.byKey(BoundingBoxOverlay.labelKey(i.id))),
            'badge ${i.id}':
                tester.getRect(find.byKey(BoundingBoxOverlay.badgeKey(i.id))),
          },
        };

        final entries = chips.entries.toList();
        for (final (a, chip) in entries.indexed) {
          expect(
              chip.value.left >= 0 &&
                  chip.value.right <= 411 &&
                  chip.value.top >= 24 && // below the status bar
                  chip.value.bottom <= 913,
              isTrue,
              reason: '${chip.key} ${chip.value} is cut off');
          for (final other in entries.skip(a + 1)) {
            expect(chip.value.overlaps(other.value), isFalse,
                reason: '${chip.key} ${chip.value} covers '
                    '${other.key} ${other.value}');
          }
        }
        // Name chips keep clear of the other boxes.
        for (final i in seeded) {
          for (final o in seeded.where((o) => o.id != i.id)) {
            expect(chips['label ${i.id}']!.overlaps(boxes[o.id]!), isFalse,
                reason: '${i.name} chip on the ${o.name} box');
          }
        }
        // The reported cases.
        expect(chips['badge det_egg']!.overlaps(chips['badge det_milk']!),
            isFalse);
        expect(find.text('Không thuần chay'), findsNWidgets(2));
        expect(
            chips['label det_carrot']!.top - boxes['det_egg']!.bottom >= 2 ||
                !chips['label det_carrot']!
                    .inflate(2)
                    .overlaps(boxes['det_egg']!),
            isTrue,
            reason: '"Cà rốt 91%" touches the Trứng gà box');
      });
    }

    test(
        'a badge too wide for its box is centred on it, not pushed over '
        'the neighbour', () {
      const bounds = Rect.fromLTRB(4, 28, 407, 909);
      final placed = layoutDetectionChips(const [
        // Trứng gà and Sữa bò side by side, Sữa bò narrower than its badge.
        DetectionChips(
            box: Rect.fromLTRB(-25, 392, 159, 502),
            label: Size(90, 22),
            badge: Size(112, 20)),
        DetectionChips(
            box: Rect.fromLTRB(180, 365, 267, 502),
            label: Size(85, 22),
            badge: Size(112, 20)),
      ], bounds: bounds);
      expect(placed[0].badge.overlaps(placed[1].badge), isFalse);
      expect(placed[1].badge.center.dx, closeTo((180 + 267) / 2, 0.5));
      expect(placed[1].badge.left, greaterThan(159));
    });
  });

  // ------------------------------------------------------------------ B64 --
  group('B64 service type labels', () {
    Chef tam(ChefService service) => Chef(
          id: 'u_chef_tam',
          name: 'Lê Quang Tâm',
          headline: '',
          specialties: const [],
          rating: 5,
          reviewCount: 1,
          yearsExperience: 1,
          city: '',
          startingPriceVnd: service.price,
          services: [service],
        );

    for (final (type, title) in [
      (ServiceType.vipMenu, 'Mua Thực đơn VIP'),
      (ServiceType.course, 'Mua Khoá học'),
    ]) {
      testWidgets('purchase sheet reads "$title"', (tester) async {
        final service = ChefService(
            id: 'svc_x',
            chefId: 'u_chef_tam',
            title: 'Thực đơn VIP 30 ngày cho gia đình',
            type: type,
            price: 1500000);
        await _pump(
            tester,
            Scaffold(
                body: PurchaseSheet(chef: tam(service), service: service)));
        expect(find.text(title), findsOneWidget);
        expect(find.text('Mua ${type.label.toLowerCase()}'), findsNothing);
      });
    }
  });

  // ------------------------------------------------------------------ X01 --
  group('X01 chef suggestion without macros', () {
    MockChefSuggestionRepository tamSends() => MockChefSuggestionRepository(
          chefUserId: () => 'u_chef_tam',
          chefName: () => 'Lê Quang Tâm',
          isChef: () => true,
        );

    test('macros stay null end to end; kcal kept', () async {
      await tamSends().send(
          'u_me',
          SendChefSuggestionDto(
              name: 'Salad đậu gà sốt me',
              calories: 380,
              slot: MealSlot.dinner,
              targetDate: DateTime.now().add(const Duration(days: 1))));
      final mine =
          await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
      final salad = mine
          .map((d) => d.toEntity())
          .firstWhere((s) => s.recipe.name == 'Salad đậu gà sốt me');
      final n = salad.recipe.nutrition;
      expect(n.calories, 380);
      expect(n.proteinG, isNull);
      expect(n.carbsG, isNull);
      expect(n.fatG, isNull);
      expect(n.summary(), isNull);
      expect(n.summary(macros: const [Macro.protein]), isNull);
      // A seeded suggestion with macros keeps them.
      final chao = mine
          .map((d) => d.toEntity())
          .firstWhere((s) => s.recipe.name.startsWith('Cháo yến mạch'));
      expect(chao.recipe.nutrition.proteinG, 13);
    });

    testWidgets('"Từ chuyên gia" shows no "Đạm 0 g"', (tester) async {
      await tester.runAsync(() => tamSends().send(
          'u_me',
          const SendChefSuggestionDto(
              name: 'Salad đậu gà sốt me', calories: 380)));
      await _pump(tester, const MealPlannerScreen(),
          size: const Size(411, 2600));
      await _wait(tester, 3000);
      await tester.tap(find.byTooltip('Đổi bữa sáng'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final chefTab = find.descendant(
          of: find.byType(TabBar), matching: find.text('Từ chuyên gia'));
      await tester.ensureVisible(chefTab);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chefTab);
      await _wait(tester);
      expect(find.text('Salad đậu gà sốt me'), findsOneWidget);
      expect(find.textContaining('Đạm 0 g'), findsNothing);
      expect(find.textContaining('380 kcal'), findsOneWidget);
      expect(find.textContaining('Đạm 13 g'), findsOneWidget,
          reason: 'known macros are still shown');
      await _dispose(tester);
    });
  });

  // ------------------------------------------------------------------ B39 --
  group('B39 typed-in dish: no made-up macros', () {
    test('only the entered protein is stored; totals mark the estimate',
        () async {
      final container = _container(await _prefs());
      await container.read(mealPlanControllerProvider.future);
      final added = await container
          .read(mealPlanControllerProvider.notifier)
          .addManualMeal(
              slot: MealSlot.lunch,
              name: 'Bánh cuốn chay nhân nấm',
              calories: 420,
              proteinG: 15);
      final n = added.recipe.nutrition;
      expect(n.proteinG, 15);
      expect(n.carbsG, isNull);
      expect(n.fatG, isNull);
      expect(n.fiberG, isNull);
      expect(n.summary(), 'Đạm 15 g');

      final day =
          container.read(mealPlanControllerProvider).requireValue.selectedDay!;
      expect(day.meals[MealSlot.lunch]!.nutrition.carbsG, isNull,
          reason: 'the slot keeps its own figures');
      expect(day.estimatedMacros, {Macro.carbs, Macro.fat, Macro.fiber});
      expect(day.mealsWithEstimates.map((r) => r.name),
          ['Bánh cuốn chay nhân nấm']);
      final others = day.meals.entries
          .where((e) => e.key != MealSlot.lunch)
          .fold<double>(0, (sum, e) => sum + (e.value.nutrition.carbsG ?? 0));
      expect(day.totals.carbsG, others + 58, reason: '420 kcal × 55 % / 4');
      expect(day.totals.proteinG, greaterThanOrEqualTo(15),
          reason: 'the real 15 g counts');
    });

    test('"Công thức của tôi" stores no estimated macros either', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      final created = await repo.createMyRecipe(const CreateRecipeRequestDto(
        name: 'Miến xào rau củ',
        calories: 480,
        ingredients: [
          RecipeIngredientInput(name: 'Miến dong', quantity: 100, unit: 'g')
        ],
        steps: ['Xào.'],
      ));
      final n = created.toEntity().nutrition;
      expect(n.calories, 480);
      expect(n.proteinG, isNull);
      expect(n.carbsG, isNull);
      expect(n.fatG, isNull);
    });

    testWidgets('slot shows only "Đạm 15 g"; the day card says "ước tính"',
        (tester) async {
      const recipe = Recipe(
        id: 'mn_1',
        name: 'Bánh cuốn chay nhân nấm',
        nutrition: Nutrition(calories: 420, proteinG: 15),
        source: MealSource.manual,
      );
      final day = MealPlanDay(date: DateTime(2026, 10, 15), meals: {
        MealSlot.lunch: recipe,
      });
      await _pump(
        tester,
        Scaffold(
          body: ListView(children: [
            DailyMacroCard(
              date: day.date,
              totals: day.totals,
              targets: const Nutrition(
                  calories: 1850,
                  proteinG: 90,
                  carbsG: 240,
                  fatG: 60,
                  fiberG: 32),
              estimated: day.estimatedMacros,
              estimatedDishes: [for (final r in day.mealsWithEstimates) r.name],
            ),
            MealSlotCard(
              slot: MealSlot.lunch,
              recipe: recipe,
              userAllergies: const [],
              isSwapping: false,
              onSwap: () {},
            ),
          ]),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Đạm 15 g'), findsOneWidget);
      expect(find.textContaining('Tinh bột 58'), findsNothing);
      expect(find.textContaining('Béo 12'), findsNothing);
      // Day card: protein is real, carbs/fat/fibre are marked.
      expect(find.textContaining('ước tính'), findsOneWidget);
      expect(find.textContaining('"Bánh cuốn chay nhân nấm"'), findsOneWidget);
      expect(find.textContaining('≈58'), findsOneWidget);
      expect(find.textContaining('≈15'), findsNothing);
    });

    testWidgets('a day without estimates has no "ước tính" note',
        (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: DailyMacroCard(
            date: DateTime(2026, 10, 15),
            totals: const Nutrition(
                calories: 420, proteinG: 15, carbsG: 50, fatG: 10, fiberG: 6),
            targets: const Nutrition(
                calories: 1850,
                proteinG: 90,
                carbsG: 240,
                fatG: 60,
                fiberG: 32),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('ước tính'), findsNothing);
      expect(find.textContaining('≈'), findsNothing);
    });
  });

  // ------------------------------------------------------------------ B37 --
  group('B37 validation messages follow the value', () {
    testWidgets('"Công thức của tôi": the kcal error clears once valid',
        (tester) async {
      await _pump(tester, const UserRecipeFormScreen());
      await tester.tap(find.text('Lưu'));
      await tester.pump();
      const kcalError = 'Năng lượng từ 50 đến 3000 kcal.';
      expect(find.text(kcalError), findsOneWidget);
      expect(find.text('Nhập tên món (ít nhất 2 ký tự).'), findsOneWidget);

      final kcal =
          find.widgetWithText(TextFormField, 'Năng lượng mỗi phần (kcal)');
      await tester.enterText(kcal, '20');
      await tester.pump();
      expect(find.text(kcalError), findsOneWidget, reason: 'still invalid');
      await tester.enterText(kcal, '480');
      await tester.pump();
      expect(find.text(kcalError), findsNothing);
      // Other fields keep their own messages until fixed.
      expect(find.text('Nhập tên món (ít nhất 2 ký tự).'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên món'), 'Miến xào rau củ');
      await tester.pump();
      expect(find.text('Nhập tên món (ít nhất 2 ký tự).'), findsNothing);
    });

    testWidgets('"Công thức của tôi": no messages before the first "Lưu"',
        (tester) async {
      await _pump(tester, const UserRecipeFormScreen());
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Năng lượng mỗi phần (kcal)'),
          '20');
      await tester.pump();
      expect(find.text('Năng lượng từ 50 đến 3000 kcal.'), findsNothing);
    });

    testWidgets('"Tự nhập món": the kcal error clears once valid',
        (tester) async {
      await _pump(
          tester,
          const Scaffold(
              body: MealPickerSheet(slot: MealSlot.lunch, allergies: [])));
      await _wait(tester, 1500);
      await tester.tap(find.text('Tự nhập món'));
      await _wait(tester, 500);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên món'), 'Bánh cuốn chay');
      final kcal = find.widgetWithText(TextFormField, 'Năng lượng (kcal)');
      await tester.enterText(kcal, '20');
      await tester.pump();
      final submit = find.widgetWithText(FilledButton, 'Thêm vào bữa trưa');
      await tester.ensureVisible(submit);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Từ 50 đến 3000 kcal.'), findsOneWidget);
      await tester.enterText(kcal, '420');
      await tester.pump();
      expect(find.text('Từ 50 đến 3000 kcal.'), findsNothing);
      await _dispose(tester);
    });
  });

  // ------------------------------------------------------------------ B63 --
  group('B63 no double booking', () {
    late DateTime now;
    late String userId;
    final chefs = MockChefRepository();
    final buyer = MockCommerceRepository(
        currentUserId: () => userId, currentUserName: () => 'Minh Anh');

    setUp(() {
      now = DateTime(2026, 10, 15, 9);
      MockCommerceDb.reset(clock: () => now);
      userId = 'u_me';
    });

    TypeMatcher<ApiException> apiError(int status, [String? code]) =>
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', status)
            .having((e) => e.code, 'code', code ?? anything);

    test('a time overlapping one of my consultations (any chef) → 409',
        () async {
      // Minh Anh is seeded with ThS. DD Phạm Thu Hà, in 2 days at 19:30.
      final clash = DateTime(2026, 10, 17, 19, 30);
      final tam = await chefs.getChef('u_chef_tam');
      expect(tam.availableSlots.any((s) => s.isAtSameMomentAs(clash)), isTrue,
          reason: 'free on Tâm\'s side');
      await expectLater(
          buyer.createOrder(CreateOrderRequestDto(
              serviceId: 'svc_tam_consult', startAt: clash)),
          throwsA(apiError(409, 'schedule_conflict').having(
              (e) => e.message,
              'message',
              allOf(contains('Bạn đã có lịch lúc 19:30'),
                  contains('chọn giờ khác')))));
      // Someone else can still book it.
      userId = 'u_someone';
      await buyer.createOrder(
          CreateOrderRequestDto(serviceId: 'svc_tam_consult', startAt: clash));
    });

    test('an unpaid hold counts until its QR expires', () async {
      final tamSlots = (await chefs.getChef('u_chef_tam')).availableSlots;
      final haSlots = (await chefs.getChef('u_thu_ha')).availableSlots;
      final common =
          tamSlots.firstWhere((s) => haSlots.any((h) => h.isAtSameMomentAs(s)));
      final held = await buyer.createOrder(CreateOrderRequestDto(
          serviceId: 'svc_tam_consult', startAt: common, note: '#expire'));
      expect(held.consultation!.status.apiValue, 'AwaitingPayment');

      await expectLater(
          buyer.createOrder(CreateOrderRequestDto(
              serviceId: 'svc_ha_quick', startAt: common)),
          throwsA(apiError(409, 'schedule_conflict')));

      now = now.add(const Duration(seconds: 31)); // the QR expired
      final ok = await buyer.createOrder(
          CreateOrderRequestDto(serviceId: 'svc_ha_quick', startAt: common));
      expect(ok.status.apiValue, 'Pending');
      // Renewing the expired QR now clashes with the Hà booking.
      await expectLater(buyer.renewPayment(held.id),
          throwsA(apiError(409, 'schedule_conflict')));
    });

    test('the chef detail lists held times as bookedSlots', () async {
      final tam = await chefs.getChef('u_chef_tam');
      final nam = DateTime(2026, 10, 17, 14); // Hoàng Nam, paid
      expect(tam.bookedSlots.any((s) => s.isAtSameMomentAs(nam)), isTrue);
      expect(tam.availableSlots.any((s) => s.isAtSameMomentAs(nam)), isFalse);
      expect(tam.toEntity().bookedSlots, isNotEmpty);
    });

    testWidgets(
        'the picker greys out my clash ("Bạn có lịch") and a held time '
        '("Đã kín")', (tester) async {
      MockCommerceDb.reset(); // real clock: the sheet reads real bookings
      final chef = (await tester
              .runAsync(() => MockChefRepository().getChef('u_chef_tam')))!
          .toEntity();
      await _pump(tester, Scaffold(body: BookingSheet(chef: chef)),
          size: const Size(411, 1400));
      await _wait(tester, 1500); // my consultations
      final day2 = DateTime.now().add(const Duration(days: 2));
      await tester.tap(find.text(formatDayMonth(day2)));
      await tester.pump();

      ChoiceChip chipOf(String time) => tester.widget<ChoiceChip>(find
          .ancestor(of: find.text(time), matching: find.byType(ChoiceChip))
          .first);
      expect(find.text('Bạn có lịch'), findsOneWidget);
      expect(find.text('Đã kín'), findsOneWidget);
      expect(chipOf('19:30').onSelected, isNull, reason: 'Hà at 19:30');
      expect(chipOf('14:00').onSelected, isNull, reason: 'Hoàng Nam');
      expect(chipOf('09:00').onSelected, isNotNull);
      expect(find.textContaining('bạn đã có lịch tư vấn trùng giờ'),
          findsOneWidget);

      await tester.tap(find.text('19:30'));
      await tester.pump();
      expect(find.text('Chưa chọn giờ'), findsOneWidget);
      await tester.tap(find.text('09:00'));
      await tester.pump();
      expect(find.text('Chưa chọn giờ'), findsNothing);
      await _dispose(tester);
    });
  });

  // ----------------------------------------------------------------- B56f --
  group('B56f a mode picked in the scanner is remembered', () {
    Future<(SharedPreferences, _FakeGallery)> openFromButton(
        WidgetTester tester) async {
      final gallery = _FakeGallery(null);
      final prefs = await _pump(
        tester,
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ScanButton(
                onScan: (mode) => Navigator.of(context)
                    .push(IngredientScannerScreen.route(mode: mode)),
              ),
            ),
          ),
        ),
        session: {..._minhAnh, ScanModeController.storageKey: 'gallery'},
        overrides: [scanImageSourceProvider.overrideWithValue(gallery)],
      );
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
      await tester.tap(find.byType(ScanButton));
      await _wait(tester, 1500);
      expect(gallery.calls, 1);
      expect(find.text('Chưa có ảnh nào được chọn'), findsOneWidget);
      return (prefs, gallery);
    }

    testWidgets('"Chụp bằng camera" → camera, and the button shows it',
        (tester) async {
      final (prefs, _) = await openFromButton(tester);
      await tester.tap(find.text('Chụp bằng camera'));
      await _wait(tester, 1000);
      expect(prefs.getString(ScanModeController.storageKey), 'camera');

      await tester.tap(find.byTooltip('Đóng'));
      await _wait(tester, 1000);
      expect(find.byType(IngredientScannerScreen), findsNothing);
      expect(
          find.descendant(
              of: find.byType(ScanButton),
              matching: find.byIcon(scanModeIcon(ScanMode.camera))),
          findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('"Nhập tay" → manual', (tester) async {
      final (prefs, _) = await openFromButton(tester);
      await tester.tap(find.text('Nhập tay'));
      await _wait(tester, 1000);
      expect(prefs.getString(ScanModeController.storageKey), 'manual');
      await tester.tap(find.byTooltip('Đóng'));
      await _wait(tester, 1000);
      expect(
          find.descendant(
              of: find.byType(ScanButton),
              matching: find.byIcon(Icons.keyboard_alt_rounded)),
          findsOneWidget);
      await _dispose(tester);
    });
  });

  // ----------------------------------------------------------------- B40c --
  group('B40c pantry source', () {
    test('addFromScan: detected → "Quét", typed or swapped → "Tự thêm"',
        () async {
      final container = _container(await _prefs());
      await container.read(pantryControllerProvider.future);
      await container
          .read(pantryControllerProvider.notifier)
          .addFromScan(const [
        ScannedPantryItem(name: 'Cà rốt'),
        ScannedPantryItem(name: 'Đậu hũ non', source: PantrySource.manual),
      ]);
      PantrySource sourceOf(String name) => MockPantryRepository.itemsOf('u_me')
          .firstWhere((p) => p.ingredient == name)
          .toEntity()
          .source;
      expect(sourceOf('Cà rốt'), PantrySource.scan);
      expect(sourceOf('Đậu hũ non'), PantrySource.manual);
      expect(
          container
              .read(pantryControllerProvider)
              .requireValue
              .firstWhere((p) => p.ingredient == 'Đậu hũ non')
              .scannedAt,
          isNull);
    });

    testWidgets(
        'a vegan swap saved from the sample scan is "Tự thêm" in the fridge',
        (tester) async {
      await _pump(tester, const IngredientScannerScreen(mode: ScanMode.gallery),
          overrides: [
            scanImageSourceProvider.overrideWithValue(_FakeGallery(null))
          ]);
      await _wait(tester, 1000);
      await tester.tap(find.text('Dùng ảnh tủ lạnh mẫu'));
      await tester.pump(const Duration(seconds: 3)); // mock vision
      await _wait(tester, 1200);

      final tray = find
          .descendant(
              of: find.byType(ScannedIngredientsSheet),
              matching: find.byType(Scrollable))
          .first;
      Future<void> reveal(Finder finder) =>
          tester.scrollUntilVisible(finder, 120, scrollable: tray);
      // Like the member: down to the non-vegan foods, then their swaps.
      await reveal(find.text('Không thuần chay — không lưu'));
      await reveal(find.text('Có nguồn gốc động vật: trứng'));
      final swap = find.widgetWithText(ActionChip, 'Đậu hũ non');
      await reveal(swap);
      await tester.ensureVisible(swap);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(swap);
      await tester.pump();
      await reveal(find.text('Lưu vào tủ lạnh (5)'));
      await tester.tap(find.text('Lưu vào tủ lạnh (5)'));
      await tester.pump(const Duration(seconds: 2));

      final fridge = {
        for (final p in MockPantryRepository.itemsOf('u_me'))
          p.ingredient: p.toEntity().source,
      };
      expect(fridge['Đậu hũ non'], PantrySource.manual);
      expect(fridge['Bông cải xanh'], PantrySource.scan);
      expect(fridge['Cà rốt'], PantrySource.scan);

      // The Thực đơn chip shows the matching icon.
      await tester.pumpWidget(const SizedBox());
      await _pump(
          tester,
          Scaffold(
              body: SingleChildScrollView(
                  child: PantrySection(onGenerate: () {}))));
      await _wait(tester, 1000);
      Finder chipIcon(String name, IconData icon) => find.descendant(
          of: find.widgetWithText(InputChip, name),
          matching: find.byIcon(icon));
      expect(chipIcon('Đậu hũ non', Icons.edit_outlined), findsOneWidget);
      expect(chipIcon('Bông cải xanh', Icons.document_scanner_outlined),
          findsOneWidget);
      await _dispose(tester);
    });
  });

  // ------------------------------------------------------------------ A17 --
  group('A17 search section headers', () {
    testWidgets('"Xem tất cả quán" sits at the right end of its row',
        (tester) async {
      await _pump(tester, const SearchScreen(initialQuery: 'bun rieu'),
          session: const {}, size: const Size(411, 2400));
      await _wait(tester, 3000);
      final all =
          tester.getRect(find.byKey(const ValueKey('search-all-restaurants')));
      expect(all.right, closeTo(411 - 8, 0.5));
      final title = tester.getRect(find.text('Quán gợi ý'));
      expect(title.left, closeTo(16, 0.5));
      expect(all.left, greaterThan(411 / 2),
          reason: 'not in the middle of the row');
      await _dispose(tester);
    });

    testWidgets('"Xoá lịch sử" too', (tester) async {
      await _pump(tester, const SearchScreen(), session: const {
        'vl.recent_searches': ['phở chay']
      });
      await tester.pump();
      final clear =
          tester.getRect(find.widgetWithText(TextButton, 'Xoá lịch sử'));
      expect(clear.right, closeTo(411 - 16, 0.5));
      await _dispose(tester);
    });

    testWidgets('large text: the action wraps instead of overflowing',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, const SearchScreen(initialQuery: 'bun rieu'),
          session: const {}, size: const Size(360, 2400));
      await _wait(tester, 3000);
      expect(tester.takeException(), isNull);
      final all =
          tester.getRect(find.byKey(const ValueKey('search-all-restaurants')));
      expect(all.right, closeTo(360 - 8, 0.5));
      await _dispose(tester);
    });
  });
}
