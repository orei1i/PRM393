// integration_test_be/ingredient_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('ingredient', skip: be.skipReason, () {
    late IngredientApiService ingredients;

    setUpAll(() async {
      final me = await be.newUser(name: 'FE IT Ingredient');
      final catalog = RecipeCatalog(me.dio, userId: me.id);
      ingredients = RemoteIngredientApiService(me.dio, catalog: () => catalog);
    });

    beTest('search ignores accents', () async {
      final rows = await ingredients.search('dau hu');
      expect(rows, isNotEmpty);
      expect(rows.first.name.toLowerCase(), contains('đậu'));
    });

    beTest('the category reaches the entity', () async {
      final rows = await ingredients.search('ca chua');
      expect(rows.first.toEntity().category?.apiValue, 'veg');
    });

    beTest('an empty query lists them all', () async {
      expect((await ingredients.search('')).length, greaterThan(10));
    });

    beTest('detail: macros, and recipes from the catalogue', () async {
      final tofu = (await ingredients.search('dau hu')).first;
      final detail = await ingredients.detail(tofu.id);
      expect(detail.summary.name, tofu.name);
      expect(detail.proteinG, isNotNull);
      expect(detail.recipes, isNotEmpty);
    });

    beTest('an unknown id is a Vietnamese 404', () async {
      await expectApiError(
        ingredients.detail('000000000000000000000000'),
        status: 404,
      );
    });

    beTest('a mock recipe row stays with the mock', () async {
      final detail = await ingredients.detail('ing_dau_hu');
      expect(detail.summary.name, 'Đậu hũ');
      await expectApiError(
        ingredients.detail('khong_co_trong_mock'),
        status: 404,
        code: 'not_found',
      );
    });

    beTest('a guest can search and open one', () async {
      final guest = RemoteIngredientApiService(be.guestDio());
      final rows = await guest.search('dau hu');
      expect(rows, isNotEmpty);
      final detail = await guest.detail(rows.first.id);
      expect(detail.proteinG, isNotNull);
    });
  });
}
