// integration_test_be/pantry_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/text_search.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/pantry_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('pantry', skip: be.skipReason, () {
    late PantryApiService pantry;

    setUpAll(() async {
      final me = await be.newUser(name: 'FE IT Pantry');
      pantry = RemotePantryApiService(me.dio);
    });

    beTest('a new account has an empty fridge', () async {
      expect(await pantry.getPantry(), isEmpty);
    });

    beTest('add returns the whole list', () async {
      final list = await pantry.addItems(const [
        AddPantryItemDto(ingredient: 'Đậu hũ'),
        AddPantryItemDto(ingredient: 'Cà chua'),
      ]);
      expect(list.map((p) => p.ingredient), containsAll(['Đậu hũ', 'Cà chua']));
      expect(list, hasLength(2));
    });

    beTest('B34: adding the same name changes the row, even without accents',
        () async {
      final list =
          await pantry.addItems(const [AddPantryItemDto(ingredient: 'dau hu')]);
      expect(list.where((p) => foldVietnamese(p.ingredient) == 'dau hu'),
          hasLength(1));
      expect(list, hasLength(2));
    });

    beTest('B38: a second add keeps the amount', () async {
      await pantry.addItems(const [
        AddPantryItemDto(ingredient: 'Gạo lứt', quantity: 300, unit: 'g'),
      ]);
      final list = await pantry
          .addItems(const [AddPantryItemDto(ingredient: 'gao lut')]);
      final row = list.singleWhere((p) => p.ingredient == 'Gạo lứt');
      expect(row.quantity, 300);
      expect(row.unit, 'g');
      await pantry.removeItem(row.id);
    });

    beTest('an amount sent on purpose replaces the old one', () async {
      await pantry.addItems(const [
        AddPantryItemDto(ingredient: 'Gạo lứt', quantity: 300, unit: 'g'),
      ]);
      final list = await pantry.addItems(const [
        AddPantryItemDto(ingredient: 'Gạo lứt', quantity: 100),
      ]);
      final row = list.singleWhere((p) => p.ingredient == 'Gạo lứt');
      expect(row.quantity, 100);
      await pantry.removeItem(row.id);
    });

    beTest('non-vegan food is refused by the app before any request', () async {
      await expectApiError(
        pantry.addItems(const [AddPantryItemDto(ingredient: 'Trứng gà')]),
        status: 422,
        code: 'not_vegan',
      );
      final list = await pantry.getPantry();
      expect(list.map((p) => p.ingredient), isNot(contains('Trứng gà')));
    });

    beTest('B13: what only the BE calls non-vegan is refused and taken out',
        () async {
      final user = await be.newUser(name: 'FE IT Pantry Bo');
      final fridge = RemotePantryApiService(user.dio);
      await expectLater(
        fridge.addItems(const [
          AddPantryItemDto(ingredient: 'Bơ'),
          AddPantryItemDto(ingredient: 'Cà chua'),
        ]),
        throwsA(isA<PantryRefusedException>()
            .having((e) => e.names, 'names', ['Bơ']).having(
                (e) => e.items.map((p) => p.ingredient), 'items', [
          'Cà chua'
        ]).having((e) => e.message, 'message', contains('Máy chủ xếp Bơ'))),
      );
      final list = await fridge.getPantry();
      expect(list.map((p) => p.ingredient), ['Cà chua']);
    });

    beTest('B13: a row the BE called non-vegan says so when it is listed',
        () async {
      final user = await be.newUser(name: 'FE IT Pantry Row');
      await user.raw('POST', '/users/me/ingredients', data: {
        'items': [
          {'ingredient': 'Thịt bò'},
          {'ingredient': 'Đậu hũ'},
        ],
      });
      final rows = {
        for (final p in await RemotePantryApiService(user.dio).getPantry())
          p.ingredient: p.toEntity().serverSaysNotVegan,
      };
      expect(rows, {'Thịt bò': true, 'Đậu hũ': false});
    });

    beTest('B14: an allergy on a standard allergen warns', () async {
      final user = await be.newUser(name: 'FE IT Pantry Allergy');
      await user.raw('PUT', '/health-profile/me', data: {
        'heightCm': 170,
        'weightKg': 66,
        'goal': 'maintain',
        'gender': 'Female',
        'birthYear': 1997,
        'activityLevel': 'light',
        'allergies': [
          {'allergenId': 'peanut', 'name': 'Đậu phộng'},
          {'allergenId': 'soy', 'name': 'Đậu nành'},
        ],
        'dietaryRestrictions': <String>[],
      });
      final list = await RemotePantryApiService(user.dio).addItems(const [
        AddPantryItemDto(ingredient: 'Đậu phộng'),
        AddPantryItemDto(ingredient: 'Đậu hũ'),
        AddPantryItemDto(ingredient: 'Cà chua'),
      ]);
      final warnings = {for (final p in list) p.ingredient: p.allergyWarning};
      expect(warnings['Đậu phộng'], 'Cảnh báo dị ứng: peanut');
      expect(warnings['Đậu hũ'], 'Cảnh báo dị ứng: soy');
      expect(warnings['Cà chua'], isNull);
    });

    beTest('edit quantity and expiry, delete, then "Hoàn tác"', () async {
      final first = (await pantry.getPantry()).first;
      final edited = await pantry.updateItem(
        first.id,
        UpdatePantryItemDto(
            quantity: 300, unit: 'g', expiryDate: DateTime(2030, 1, 5)),
      );
      expect(edited.quantity, 300);
      expect(edited.unit, 'g');
      expect(edited.expiryDate!.year, 2030);

      await pantry.removeItem(first.id);
      expect(
        (await pantry.getPantry()).map((p) => p.id),
        isNot(contains(first.id)),
      );

      final restored = await pantry.restoreItem(
        AddPantryItemDto(
          ingredient: edited.ingredient,
          quantity: edited.quantity,
          unit: edited.unit,
          expiryDate: edited.expiryDate,
        ),
        index: 0,
      );
      final row =
          restored.singleWhere((p) => p.ingredient == edited.ingredient);
      expect(row.quantity, 300);
      expect(row.expiryDate!.year, 2030);
    });

    beTest('"Xoá hết"', () async {
      await pantry.clear();
      expect(await pantry.getPantry(), isEmpty);
    });

    beTest('a guest has no fridge', () async {
      await expectApiError(
        RemotePantryApiService(be.guestDio()).getPantry(),
        status: 401,
      );
    });
  });
}
