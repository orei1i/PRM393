// integration_test_be/pantry_be_test.dart
import 'package:flutter_test/flutter_test.dart';
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

    beTest('adding the same name refreshes the row', () async {
      final list =
          await pantry.addItems(const [AddPantryItemDto(ingredient: 'Đậu hũ')]);
      expect(list.where((p) => p.ingredient == 'Đậu hũ'), hasLength(1));
    });

    beTest('non-vegan food is refused by the app (B13 workaround)', () async {
      await expectApiError(
        pantry.addItems(const [AddPantryItemDto(ingredient: 'Trứng gà')]),
        status: 422,
        code: 'not_vegan',
      );
      final list = await pantry.getPantry();
      expect(list.map((p) => p.ingredient), isNot(contains('Trứng gà')));
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
