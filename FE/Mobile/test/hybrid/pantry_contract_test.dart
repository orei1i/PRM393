// test/hybrid/pantry_contract_test.dart
// The fridge and the nutrition DB against recorded BE answers.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/ingredient/data/models/ingredient_model.dart';
import 'package:veganlife_mobile/features/ingredient/domain/entities/ingredient.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/pantry_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/pantry_controller.dart';

import 'planner_test_support.dart';

const _pantry = '/users/me/ingredients';

FakeBackend _fridge() => FakeBackend()
  ..on('GET $_pantry', 200, fixture('pantry_fixture_list.json'))
  ..on('POST $_pantry', 200, fixture('pantry_fixture_add.json'));

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  group('fridge', () {
    test('adding returns the whole list: the BE answers with touched rows only',
        () async {
      final backend = _fridge()
        ..on(
            'POST $_pantry',
            200,
            envelope((fixtureData<List<dynamic>>('pantry_fixture_add.json'))
                .take(1)
                .toList()));
      final c = await backendContainer(backend);
      final list = await c
          .read(pantryApiProvider)
          .addItems(const [AddPantryItemDto(ingredient: 'Đậu hũ')]);
      expect(list.length, 4);
      expect(backend.calls, ['GET $_pantry', 'POST $_pantry', 'GET $_pantry']);
    });

    test('a second add keeps the amount of the row (B38)', () async {
      final backend = _fridge();
      final rows = fixtureData<List<dynamic>>('pantry_fixture_list.json')
          .cast<Map<String, dynamic>>();
      final row = rows.firstWhere((r) => r['quantity'] != null);
      final c = await backendContainer(backend);
      await c.read(pantryApiProvider).addItems([
        AddPantryItemDto(
            ingredient: (row['ingredient'] as String).toUpperCase()),
        const AddPantryItemDto(ingredient: 'Tên chưa có trong tủ'),
      ]);
      final items = backend.bodyOf('POST $_pantry')['items'] as List;
      expect((items.first as Map)['quantity'], row['quantity']);
      expect((items.last as Map).containsKey('quantity'), isFalse);
    });

    test('with an amount given the list is not read first', () async {
      final backend = _fridge();
      final c = await backendContainer(backend);
      await c.read(pantryApiProvider).addItems(
          const [AddPantryItemDto(ingredient: 'Đậu hũ', quantity: 300)]);
      expect(backend.calls, ['POST $_pantry', 'GET $_pantry']);
      expect((backend.bodyOf('POST $_pantry')['items'] as List).single,
          containsPair('quantity', 300.0));
    });

    group('a row the BE calls non-vegan (B13)', () {
      FakeBackend refusing() {
        var rows = <Map<String, dynamic>>[];
        final backend = FakeBackend();
        backend.routes['GET $_pantry'] = (_) => (200, envelope(rows));
        backend.routes['POST $_pantry'] = (request) {
          final items =
              ((request.data as Map<String, dynamic>)['items'] as List)
                  .cast<Map<String, dynamic>>();
          final added = [
            for (final item in items)
              {
                'id': 'id_${item['ingredient']}',
                'ingredient': item['ingredient'],
                'quantity': 1,
                'unit': 'phần',
                'isVegan': item['ingredient'] != 'Bơ',
              },
          ];
          rows = [...rows, ...added];
          return (200, envelope(added));
        };
        backend.routes['DELETE $_pantry/id_Bơ'] = (_) {
          rows = rows.where((r) => r['id'] != 'id_Bơ').toList();
          return (200, envelope(null));
        };
        return backend;
      }

      test('it is taken back out and refused, saying who decided', () async {
        final backend = refusing();
        final c = await backendContainer(backend);
        await c.read(pantryControllerProvider.future);
        final verdict =
            await c.read(pantryControllerProvider.notifier).addManual('Bơ');
        expect(verdict.isVegan, isFalse);
        expect(verdict.byServerOnly, isTrue);
        expect(verdict.veganAlternatives, isEmpty);
        expect(backend.requests('DELETE $_pantry/id_Bơ'), hasLength(1));
        expect(c.read(pantryControllerProvider).requireValue, isEmpty);
      });

      test('the rest of a scan stays, and the message names the refused one',
          () async {
        final backend = refusing();
        final c = await backendContainer(backend);
        await c.read(pantryControllerProvider.future);
        await expectLater(
          c.read(pantryControllerProvider.notifier).addFromScan(const [
            ScannedPantryItem(name: 'Cà chua', isVegan: true),
            ScannedPantryItem(name: 'Bơ', isVegan: true),
          ]),
          throwsA(isA<PantryRefusedException>()
              .having((e) => e.names, 'names', ['Bơ'])
              .having((e) => e.statusCode, 'status', 422)
              .having((e) => e.message, 'message', contains('Máy chủ xếp Bơ'))),
        );
        expect(
            c
                .read(pantryControllerProvider)
                .requireValue
                .map((p) => p.ingredient),
            ['Cà chua']);
      });

      test('a row that is already there says so', () {
        final row = PantryItemDto.fromJson({
          'id': 'x',
          'ingredient': 'Bơ',
          'isVegan': false,
        }).toEntity();
        expect(row.serverSaysNotVegan, isTrue);
        expect(
            PantryItemDto.fromJson({'id': 'x', 'ingredient': 'Cà'})
                .toEntity()
                .serverSaysNotVegan,
            isFalse);
      });
    });

    test('a food that is not vegan is refused before any request', () async {
      final backend = _fridge();
      final c = await backendContainer(backend);
      await expectLater(
          c
              .read(pantryApiProvider)
              .addItems(const [AddPantryItemDto(ingredient: 'Trứng gà')]),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', 422)
              .having((e) => e.code, 'code', 'not_vegan')
              .having((e) => e.message, 'message',
                  'Trứng gà không thuần chay nên không lưu vào tủ.')));
      expect(backend.seen, isEmpty);
    });

    test('recorded rows carry amount, unit and warnings', () async {
      final row = PantryItemDto.fromJson({
        ...(fixtureData<List<dynamic>>('pantry_fixture_add.json').first
            as Map<String, dynamic>),
        'allergyWarning': 'Chứa đậu nành',
      }).toEntity();
      expect(row.ingredient, 'Đậu hũ');
      expect(row.quantity, 200);
      expect(row.unit, 'g');
      expect(row.expiryDate, isNull);
      expect(row.allergyWarning, 'Chứa đậu nành');
      expect(IngredientCategory.fromApi(row.category),
          IngredientCategory.plantProtein);
    });

    test('editing sends amount, unit and only a date that is set', () async {
      final backend = FakeBackend()
        ..on('PUT $_pantry/p1', 200, fixture('pantry_fixture_put.json'));
      final c = await backendContainer(backend);
      final row = await c.read(pantryApiProvider).updateItem(
          'p1',
          UpdatePantryItemDto(
              quantity: 300, unit: 'g', expiryDate: DateTime(2026, 11, 5)));
      expect(backend.bodyOf('PUT $_pantry/p1'),
          {'quantity': 300.0, 'unit': 'g', 'expiryDate': '2026-11-05'});
      expect(row.quantity, 300);
      expect(row.expiryDate, isNotNull);
      expect(
          const UpdatePantryItemDto(quantity: 1, unit: 'phần')
              .toJson()
              .containsKey('expiryDate'),
          isFalse);
    });

    test('the controller replaces the edited row', () async {
      final backend = _fridge();
      final c = await backendContainer(backend);
      final items = await c.read(pantryControllerProvider.future);
      final first = items.first;
      backend.on(
          'PUT $_pantry/${first.id}',
          200,
          envelope({
            'id': first.id,
            'ingredient': first.ingredient,
            'quantity': 2,
            'unit': 'gói',
          }));
      await c
          .read(pantryControllerProvider.notifier)
          .updateItem(first, quantity: 2, unit: 'gói');
      final after = c.read(pantryControllerProvider).requireValue;
      expect(after.first.unit, 'gói');
      expect(after.length, items.length);
    });

    test('"Hoàn tác" keeps the amount and the date', () async {
      final backend = _fridge()..on('DELETE $_pantry/x', 200, envelope(null));
      final c = await backendContainer(backend);
      final notifier = c.read(pantryControllerProvider.notifier);
      await c.read(pantryControllerProvider.future);
      final item = PantryItem(
          id: 'x',
          ingredient: 'Đậu hũ',
          quantity: 200,
          unit: 'g',
          expiryDate: DateTime(2026, 11, 5));
      await notifier.remove(item);
      await notifier.restore(item);
      expect(backend.bodyOf('POST $_pantry')['items'], [
        {
          'ingredient': 'Đậu hũ',
          'quantity': 200.0,
          'unit': 'g',
          'expiryDate': '2026-11-05',
        },
      ]);
    });

    test('"Sắp hết hạn" within 3 days, expired included', () {
      PantryItem expiring(DateTime? at) =>
          PantryItem(id: 'x', ingredient: 'y', expiryDate: at);
      expect(expiring(null).expiresSoon(testNow), isFalse);
      expect(expiring(DateTime(2026, 11, 3)).expiresSoon(testNow), isTrue);
      expect(expiring(DateTime(2026, 11, 4)).expiresSoon(testNow), isFalse);
      expect(expiring(DateTime(2026, 10, 1)).expiresSoon(testNow), isTrue);
    });
  });

  group('nutrition DB', () {
    test('macros at the root; an unknown one stays null', () {
      final detail = IngredientDetailDto.fromJson({
        ...fixtureData<Map<String, dynamic>>('pantry_fixture_ingredient.json'),
        'sugarG': null,
      }).toEntity();
      expect(detail.summary.caloriesPer100g, 76);
      expect(detail.proteinG, 8.1);
      expect(detail.carbsG, 1.9);
      expect(detail.fatG, 4.8);
      expect(detail.fiberG, 0.3);
      expect(detail.sugarG, isNull);
      expect(detail.allergenIds, ['soy']);
      expect(detail.summary.category, IngredientCategory.plantProtein);
    });

    test('per100g still wins', () {
      final detail = IngredientDetailDto.fromJson({
        'id': 'a',
        'name': 'b',
        'per100g': {'calories': 10, 'proteinG': 1.5},
        'proteinG': 99,
      }).toEntity();
      expect(detail.proteinG, 1.5);
    });

    test('the BE\'s "vegetable" is the app\'s vegetable group', () {
      expect(IngredientCategory.fromApi('vegetable'), IngredientCategory.veg);
      expect(IngredientCategory.fromApi('veg'), IngredientCategory.veg);
      expect(IngredientCategory.veg.apiValue, 'veg');
    });

    test('a mock recipe\'s ingredient id stays with the mock', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend);
      final row = (await MockIngredientRepository().search('')).first;
      final detail = await c.read(ingredientApiProvider).detail(row.id);
      expect(detail.summary.id, row.id);
      expect(backend.seen, isEmpty);
    });

    test('recipes come from the catalogue, when it can be read', () async {
      const id = '6ae595c796695f5c139fa95d';
      final backend = FakeBackend()
        ..on('GET /ingredients/$id', 200,
            fixture('pantry_fixture_ingredient.json'))
        ..on('GET /meal-plans/current', 404, notFound('Chưa có.'))
        ..on('POST /meal-plans/from-ingredients', 200,
            fixture('recipe_fixture_swap.json'))
        ..on('GET /users/me/recipes', 200, envelope(const <Object>[]));
      final c = await backendContainer(backend);
      final detail = await c.read(ingredientApiProvider).detail(id);
      expect(detail.recipes, isNotEmpty);
      expect(detail.recipes.first.calories, isNotNull);

      // A guest can't read it: the page still opens.
      final guest = FakeBackend()
        ..on('GET /ingredients/$id', 200,
            fixture('pantry_fixture_ingredient.json'))
        ..on('GET /meal-plans/current', 401, null);
      final g = await backendContainer(guest, signedIn: false);
      expect((await g.read(ingredientApiProvider).detail(id)).recipes, isEmpty);
    });
  });
}
