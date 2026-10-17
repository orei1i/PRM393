// test/planner/scanner_vegan_test.dart
//
// The fridge scanner only says what each food is and whether it is vegan
// (thuần chay). Non-vegan foods are never saved, and come with a reason and
// vegan swaps.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/scanner/data/mock_scanner_repository.dart';
import 'package:veganlife_mobile/features/scanner/data/models/scan_result_model.dart';
import 'package:veganlife_mobile/features/scanner/data/scanner_api_service.dart';
import 'package:veganlife_mobile/features/scanner/domain/vegan_check.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';

/// Records what "Gợi ý món từ nguyên liệu này" sends.
class _RecordingScanner extends MockScannerRepository {
  GenerateMenuRequestDto? lastRequest;

  @override
  Future<List<MenuSuggestionDto>> generateMenu(GenerateMenuRequestDto request) {
    lastRequest = request;
    return super.generateMenu(request);
  }
}

void main() {
  group('classifyVegan', () {
    test('plants (even with an animal word in the name) are vegan', () {
      for (final name in [
        'Bông cải xanh',
        'Đậu hũ',
        'Cà chua',
        'Cà rốt',
        'Rau chân vịt', // "vịt" here is spinach
        'rau chan vit',
        'Cỏ mực',
        'Nấm mỡ', // "mỡ" here is a mushroom
        'Nấm đùi gà',
        'Đậu gà',
        'Cải bó xôi', // "bó", not "bò"
        'cai bo xoi',
        'Sữa đậu nành',
        'Sữa yến mạch',
        'Yến mạch',
        'Bơ đậu phộng',
        'Rau diếp cá',
        'Gà chay',
        'Nước mắm chay',
        'Thịt thực vật',
      ]) {
        final verdict = classifyVegan(name);
        expect(verdict.isVegan, isTrue, reason: name);
        expect(verdict.nonVeganReason, isNull, reason: name);
        expect(verdict.veganAlternatives, isEmpty, reason: name);
      }
    });

    test('animal foods are not vegan, with a reason and swaps', () {
      void check(String name, String reason, List<String> swaps) {
        final verdict = classifyVegan(name);
        expect(verdict.isVegan, isFalse, reason: name);
        expect(verdict.label, 'Không thuần chay');
        expect(verdict.nonVeganReason, reason, reason: name);
        expect(verdict.veganAlternatives, containsAll(swaps), reason: name);
      }

      check('Trứng gà', 'Có nguồn gốc động vật: trứng', ['Đậu hũ non']);
      check('Sữa bò', 'Chứa sữa bò', ['Sữa hạt']);
      check('Mật ong', 'Mật ong (từ ong)', ['Siro phong']);
      check('Nước mắm Phú Quốc', 'Làm từ cá hoặc tôm lên men',
          ['Nước tương', 'Nước mắm chay']);
      check('Kim chi cải thảo', 'Có thể chứa nước mắm', ['Kim chi chay']);
      check('Thịt bò', 'Có nguồn gốc động vật: thịt bò', ['Đậu hũ']);
      check('thit heo', 'Có nguồn gốc động vật: thịt heo', ['Đậu hũ']);
      check('Cá hồi', 'Có nguồn gốc động vật: cá hồi', ['Nấm bào ngư']);
      check('Tôm sú', 'Có nguồn gốc động vật: tôm', ['Đậu hũ']);
      check('Phô mai', 'Làm từ sữa động vật', ['Phô mai chay']);
      check('Bơ động vật', 'Làm từ sữa động vật', ['Bơ thực vật']);
      check('Mỡ heo', 'Có nguồn gốc động vật: mỡ heo', ['Dầu thực vật']);
      check('Gelatin', 'Làm từ da, xương động vật', ['Bột rau câu']);
      check('Yến sào', 'Làm từ tổ chim yến', ['Nấm tuyết']);
    });

    test('every suggested swap is itself vegan', () {
      for (final name in [
        'Trứng gà',
        'Sữa bò',
        'Sữa chua',
        'Mật ong',
        'Nước mắm',
        'Kim chi',
        'Dầu hào',
        'Hạt nêm',
        'Phô mai',
        'Bơ lạt',
        'Sữa dê',
        'Gelatin',
        'Yến sào',
        'Tóp mỡ',
        'Mực',
        'Thịt gà',
      ]) {
        final verdict = classifyVegan(name);
        expect(verdict.isVegan, isFalse, reason: name);
        expect(verdict.veganAlternatives, isNotEmpty, reason: name);
        for (final swap in verdict.veganAlternatives) {
          expect(classifyVegan(swap).isVegan, isTrue, reason: '$name → $swap');
        }
      }
    });

    test("the server's isVegan wins; missing details come from the local check",
        () {
      expect(resolveVegan('Phô mai', serverIsVegan: true).isVegan, isTrue);
      final fromServer = resolveVegan('Bánh quy bơ',
          serverIsVegan: false,
          serverReason: 'Chứa bơ sữa',
          serverAlternatives: const ['Bánh quy yến mạch']);
      expect(fromServer.isVegan, isFalse);
      expect(fromServer.nonVeganReason, 'Chứa bơ sữa');
      expect(fromServer.veganAlternatives, ['Bánh quy yến mạch']);
      final filledIn = resolveVegan('Trứng vịt', serverIsVegan: false);
      expect(filledIn.nonVeganReason, 'Có nguồn gốc động vật: trứng');
      expect(filledIn.veganAlternatives, ['Đậu hũ non']);
      expect(resolveVegan('Trứng vịt').isVegan, isFalse);
    });
  });

  group('scan DTO', () {
    test('reads isVegan / nonVeganReason / veganAlternatives (also as BIT)',
        () {
      final egg = DetectedIngredientDto.fromJson({
        'id': 'd1',
        'label': 'Trứng gà',
        'confidence': 0.94,
        'isVegan': 0,
        'nonVeganReason': 'Có nguồn gốc động vật: trứng',
        'veganAlternatives': ['Đậu hũ non'],
      });
      expect(egg.isVegan, isFalse);
      final entity = egg.toEntity();
      expect(entity.isVegan, isFalse);
      expect(entity.nonVeganReason, 'Có nguồn gốc động vật: trứng');
      expect(entity.veganAlternatives, ['Đậu hũ non']);
      expect(entity.savable, isFalse, reason: 'confirmed but not vegan');
      expect(egg.toJson()['isVegan'], isFalse);
      expect(egg.toJson().containsKey('freshness'), isFalse);

      // The server's flag wins over the local check.
      final server = DetectedIngredientDto.fromJson({
        'id': 'd2',
        'label': 'Sữa bò',
        'confidence': 0.9,
        'isVegan': true,
      }).toEntity();
      expect(server.isVegan, isTrue);
    });
  });

  group('scanner tray', () {
    Future<ProviderContainer> scanned({ScannerApiService? api}) async {
      final container = ProviderContainer(overrides: [
        scannerApiProvider.overrideWithValue(api ?? MockScannerRepository()),
        userAllergiesProvider.overrideWith((ref) async => const <String>[]),
      ]);
      addTearDown(container.dispose);
      await container
          .read(scannerControllerProvider.notifier)
          .analyze(Uint8List(0));
      return container;
    }

    test('summary counts vegan and non-vegan; only vegan items are savable',
        () async {
      final container = await scanned();
      var state = container.read(scannerControllerProvider);
      expect(state.items, hasLength(7));
      expect(state.summary, '7 thực phẩm · 5 thuần chay · 2 không thuần chay');
      expect(state.nonVeganItems.map((i) => i.name), ['Trứng gà', 'Sữa bò']);
      // "Rau chân vịt" (58 %) still needs confirming.
      expect(state.savableItems.map((i) => i.name),
          ['Bông cải xanh', 'Đậu hũ', 'Cà chua', 'Cà rốt']);

      final notifier = container.read(scannerControllerProvider.notifier)
        ..confirm('det_leafy');
      state = container.read(scannerControllerProvider);
      expect(state.savableItems, hasLength(5));
      expect(state.savableItems.any((i) => !i.isVegan), isFalse);

      // Picking a swap adds it as a vegan item.
      final swap = notifier.addManual('Đậu hũ non');
      expect(swap!.isVegan, isTrue);
      expect(notifier.addManual('đậu hũ non'), isNull, reason: 'already there');
      state = container.read(scannerControllerProvider);
      expect(state.savableItems, hasLength(6));
      expect(state.summary, '8 thực phẩm · 6 thuần chay · 2 không thuần chay');
    });

    test('typed names are classified locally', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(scannerControllerProvider.notifier);
      final honey = notifier.addManual('Mật ong rừng')!;
      expect(honey.isVegan, isFalse);
      expect(honey.nonVeganReason, 'Mật ong (từ ong)');
      expect(honey.veganAlternatives, contains('Siro phong'));
      expect(honey.manual, isTrue);
      final state = container.read(scannerControllerProvider);
      expect(state.savableItems, isEmpty);
      expect(state.summary, '1 thực phẩm · 1 không thuần chay');

      notifier.addManual('Nấm rơm');
      expect(container.read(scannerControllerProvider).summary,
          '2 thực phẩm · 1 thuần chay · 1 không thuần chay');
    });

    test('dish ideas are built from vegan items only', () async {
      final api = _RecordingScanner();
      final container = await scanned(api: api);
      await container.read(scannerControllerProvider.notifier).generateMenu();
      final sent = api.lastRequest!;
      expect(sent.ingredients.map((i) => i.name),
          ['Bông cải xanh', 'Đậu hũ', 'Cà chua', 'Cà rốt']);
      final json = sent.toJson();
      expect(json.toString(), isNot(contains('Trứng')));
      expect(json.toString(), isNot(contains('freshness')));
      expect(json.containsKey('preferUseSoon'), isFalse);
      expect(container.read(scannerControllerProvider).menuStatus,
          MenuStatus.ready);
    });

    test('nothing vegan → no dish ideas, a clear message', () async {
      final container = ProviderContainer(overrides: [
        userAllergiesProvider.overrideWith((ref) async => const <String>[]),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(scannerControllerProvider.notifier)
        ..addManual('Sữa bò');
      await notifier.generateMenu();
      final state = container.read(scannerControllerProvider);
      expect(state.menuStatus, MenuStatus.error);
      expect(state.menuError, contains('thuần chay'));
    });
  });

  group('pantry: "Thêm vào tủ"', () {
    setUp(MockMealPlannerRepository.reset);

    testWidgets('refuses a non-vegan food, offers swaps, adds a picked one',
        (tester) async {
      tester.view
        ..physicalSize = const Size(411, 1400)
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
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          pantryApiProvider
              .overrideWithValue(MockPantryRepository(userId: 'u_me')),
        ],
        child: const MaterialApp(home: PantryScreen()),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Gạo lứt'), findsOneWidget);
      expect(find.textContaining('Dùng sớm'), findsNothing);
      expect(find.textContaining('Tươi'), findsNothing);
      Finder source(String label) =>
          find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label);
      expect(source('Tự thêm'), findsOneWidget, reason: 'Gạo lứt');
      expect(source('Quét'), findsNWidgets(3));

      await tester.enterText(find.byType(TextField), 'Thịt bò');
      await tester.tap(find.byTooltip('Thêm vào tủ'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Thịt bò không thuần chay nên không thêm vào tủ.'),
          findsOneWidget);
      expect(find.text('Có nguồn gốc động vật: thịt bò'), findsOneWidget);
      expect(find.text('Gợi ý thay thế:'), findsOneWidget);
      expect(MockPantryRepository.itemsOf('u_me').map((i) => i.ingredient),
          isNot(contains('Thịt bò')));

      await tester.tap(find.widgetWithText(ActionChip, 'Mì căn'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Thịt bò không thuần chay nên không thêm vào tủ.'),
          findsNothing);
      // The new row, with its energy from the nutrition DB.
      expect(find.text('Mì căn'), findsOneWidget);
      expect(find.text('121 kcal / 100 g · 1 miếng ≈ 61 kcal'), findsOneWidget);
      expect(MockPantryRepository.itemsOf('u_me').map((i) => i.ingredient),
          contains('Mì căn'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
