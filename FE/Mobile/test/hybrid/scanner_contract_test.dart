// test/hybrid/scanner_contract_test.dart
// The real vision upload, and dish ideas that never touch the member's plan.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/scanner/data/models/scan_result_model.dart';
import 'package:veganlife_mobile/features/scanner/data/scanner_api_service.dart';
import 'package:veganlife_mobile/features/scanner/domain/entities/detected_ingredient.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';

import 'planner_test_support.dart';

const _suggestions = '/meal-plans/000000000000000000000000/swap-suggestions';
const _mine = '/users/me/recipes';
const _profile = '/health-profile/me';
final _scan = '${Env.apiOrigin}/vision/scan';

Map<String, dynamic> _recipe(String id, String name, List<String> ingredients,
        {List<String> allergens = const []}) =>
    {
      'id': id.padLeft(24, '0'),
      'name': name,
      'imageUrl': null,
      'calories': 400,
      'proteinG': 10,
      'allergens': allergens,
      'dietTags': <String>[],
      'prepMinutes': 20,
      'ingredients': ingredients,
      'instructions': ['Nấu'],
    };

DetectedIngredient _food(String name) =>
    DetectedIngredient(id: name, name: name, confidence: 1, isVegan: true);

FakeBackend _catalog(List<Map<String, dynamic>> recipes) => FakeBackend()
  ..on('GET $_suggestions', 200, envelope(recipes))
  ..on('GET $_mine', 200, envelope(const <Object>[]));

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  group('scan upload', () {
    test('goes to the root route as multipart `image`; the result parses',
        () async {
      final backend = FakeBackend()
        ..on('POST $_scan', 200, fixture('scanner_fixture_scan.json'));
      final c = await backendContainer(backend);
      final result = await c
          .read(scannerApiProvider)
          .scanImage(Uint8List.fromList([1, 2, 3]));

      final form = backend.requests('POST $_scan').single.data as FormData;
      expect(form.files.single.key, 'image');
      expect(form.files.single.value.length, 3);

      expect(result.scanId, startsWith('scn_'));
      final items = result.items.map((i) => i.toEntity()).toList();
      final broccoli = items.first;
      expect(broccoli.name, 'Bông cải xanh');
      expect(broccoli.isVegan, isTrue);
      expect(broccoli.box?.left, 0.06);
      expect(broccoli.box?.width, 0.3);
      expect(broccoli.alternatives.single.name, 'Súp lơ');
      final egg = items.firstWhere((i) => !i.isVegan);
      expect(egg.name, 'Trứng gà');
      expect(egg.nonVeganReason, 'Có nguồn gốc động vật: trứng');
      expect(egg.veganAlternatives, isNotEmpty);
    });

    test('no bytes: the label, and nothing is sent', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend);
      await expectLater(
          c.read(scannerApiProvider).scanImage(Uint8List(0)),
          throwsA(isA<ApiException>().having((e) => e.message, 'message',
              'Chưa có ảnh để quét. Hãy chụp hoặc chọn ảnh khác.')));
      expect(backend.seen, isEmpty);
    });

    test('the controller shows it as the scan error', () async {
      final c = await backendContainer(FakeBackend());
      await c.read(scannerControllerProvider.notifier).analyze(Uint8List(0));
      final state = c.read(scannerControllerProvider);
      expect(state.status, ScanStatus.error);
      expect(state.errorMessage,
          'Chưa có ảnh để quét. Hãy chụp hoặc chọn ảnh khác.');
    });
  });

  group('dish ideas from the catalogue', () {
    Future<List<MenuSuggestionDto>> ideas(
      FakeBackend backend,
      List<String> names, {
      List<String> exclude = const [],
    }) async {
      final c = await backendContainer(backend);
      return c.read(scannerApiProvider).generateMenu(GenerateMenuRequestDto(
          ingredients: names.map(_food).toList(), excludeAllergens: exclude));
    }

    test('best match first; what is used and what is missing', () async {
      final backend = _catalog([
        _recipe('1', 'Canh', ['Cà chua', 'Hành lá']),
        _recipe('2', 'Sốt', ['Đậu hũ non', 'cà chua', 'Tỏi']),
        _recipe('3', 'Cháo', ['Gạo']),
      ]);
      final menu = await ideas(backend, ['Đậu hũ', 'Cà chua']);
      expect(menu.map((m) => m.name), ['Sốt', 'Canh']);
      expect(menu.first.id, hasLength(24));
      expect(menu.first.calories, 400);
      expect(menu.first.prepMinutes, 20);
      expect(menu.first.usedIngredients, ['Đậu hũ non', 'cà chua']);
      expect(menu.first.missingIngredients, ['Tỏi']);
    });

    test('no dish with an allergen: tagged or named in free text', () async {
      final backend = _catalog([
        _recipe('1', 'Gỏi lạc', ['Cà chua'], allergens: ['peanut']),
        _recipe('2', 'Cuốn', ['Cà chua', 'Lá lốt']),
        _recipe('3', 'Lá lốt nướng', ['Cà chua']),
        _recipe('4', 'An toàn', ['Cà chua']),
      ]);
      final menu =
          await ideas(backend, ['Cà chua'], exclude: ['peanut', 'lá lốt']);
      expect(menu.map((m) => m.name), ['An toàn']);
    });

    test('at most 5, nothing without a match', () async {
      final backend = _catalog([
        for (var i = 0; i < 8; i++) _recipe('$i', 'Món $i', ['Cà chua']),
        _recipe('9', 'Khác', ['Gạo']),
      ]);
      expect(await ideas(backend, ['Cà chua']), hasLength(5));
      expect(await ideas(backend, ['Sầu riêng']), isEmpty);
    });

    test('never touches the plan: only the two catalogue reads', () async {
      final backend = _catalog([
        _recipe('1', 'Canh', ['Cà chua']),
      ]);
      await ideas(backend, ['Cà chua']);
      expect(backend.calls, ['GET $_suggestions', 'GET $_mine']);
      expect(backend.calls.where((p) => !p.startsWith('GET')), isEmpty);
      expect(backend.calls.join(), isNot(contains('from-ingredients')));
    });

    test('through the controller: confirmed vegan items, allergies excluded',
        () async {
      final backend = _catalog([
        _recipe('1', 'Gỏi đậu phộng', ['Cà chua'], allergens: ['peanut']),
        _recipe('2', 'Canh', ['Cà chua']),
      ])
        ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'));
      final c = await backendContainer(backend);
      final notifier = c.read(scannerControllerProvider.notifier);
      notifier
        ..addManual('Cà chua')
        ..addManual('Trứng gà');
      await notifier.generateMenu();
      final state = c.read(scannerControllerProvider);
      expect(state.menuStatus, MenuStatus.ready);
      expect(state.menu.map((m) => m.name), ['Canh']);
      expect(backend.calls.where((p) => !p.startsWith('GET')), isEmpty);
    });
  });
}
