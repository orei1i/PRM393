// test/recipe_customization/backend_recipe_items_test.dart
// The table behind customizing real BE recipes, against the BE's own seed file:
// one entry per recipe with exactly its rows, signature rows, energy close to the
// BE's calories, and substitutes that pass the vegan and allergy checks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/allergy_match.dart';
import 'package:veganlife_mobile/features/recipe/data/backend_recipe_items.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/scanner/domain/vegan_check.dart';

/// Close enough for reference amounts; the app shows the BE's figure anyway.
const _tolerance = 0.10;

typedef _Seed = ({String name, int kcal, List<String> rows});

/// `("Tên", 420, …, new[] { "Yến mạch", "Hạt chia" })` of `RecipeSeedData.cs`.
List<_Seed> _seeds() {
  final source = File('../../BE/InfrastructureLayer/Seed/RecipeSeedData.cs')
      .readAsStringSync();
  return [
    for (final m in RegExp(
            r'^\s*\("([^"]+)", (\d+),.*new\[\] \{([^}]*)\}\),?\s*$',
            multiLine: true)
        .allMatches(source))
      (
        name: m.group(1)!,
        kcal: int.parse(m.group(2)!),
        rows: [
          for (final r in RegExp(r'"([^"]+)"').allMatches(m.group(3)!))
            r.group(1)!,
        ],
      ),
  ];
}

List<Map<String, Object?>> _subs(Map<String, Object?> row) =>
    (row['substitutes'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();

double _kcalOf(Map<String, Object?> row) =>
    ((row['nutrition']! as Map<String, Object?>)['calories']! as num)
        .toDouble();

List<String> _allergens(Map<String, Object?> row) =>
    (row['allergens']! as List<Object?>).cast<String>();

void main() {
  final seeds = _seeds();

  test('the seed file was read', () => expect(seeds, hasLength(29)));

  test('every BE seed recipe has an entry with exactly its rows', () {
    for (final seed in seeds) {
      final items = backendRecipeItemsFor(seed.name);
      expect(items, isNotNull, reason: seed.name);
      expect([for (final r in items!.rows) r['name']], seed.rows,
          reason: seed.name);
    }
    expect(backendRecipeItemsJson(), hasLength(seeds.length),
        reason: 'no entry for anything else');
  });

  test('every entry has a signature row and something to swap', () {
    for (final seed in seeds) {
      final rows = backendRecipeItemsFor(seed.name)!.rows;
      expect(rows.where((r) => r['isSignature'] == true), isNotEmpty,
          reason: seed.name);
      expect(rows.where((r) => _subs(r).isNotEmpty), isNotEmpty,
          reason: seed.name);
    }
  });

  test('computed energy per serving is close to the BE calories', () {
    for (final seed in seeds) {
      final items = backendRecipeItemsFor(seed.name)!;
      final total = items.rows.map(_kcalOf).reduce((a, b) => a + b);
      expect(total / items.servings, closeTo(seed.kcal, seed.kcal * _tolerance),
          reason: seed.name);
    }
  });

  test('every row has an amount and a role; every substitute has energy', () {
    for (final seed in seeds) {
      for (final row in backendRecipeItemsFor(seed.name)!.rows) {
        final name = '${seed.name} / ${row['name']}';
        expect(row['quantity'], greaterThan(0), reason: name);
        expect(row['unit'], isNotEmpty, reason: name);
        expect(row['role'], isNotEmpty, reason: name);
        for (final sub in _subs(row)) {
          expect(sub['quantity'], greaterThan(0),
              reason: '$name → ${sub['name']}');
          expect(_kcalOf(sub), greaterThan(0),
              reason: '$name → ${sub['name']}');
        }
      }
    }
  });

  test('a signature row only offers substitutes of its role', () {
    for (final seed in seeds) {
      for (final row in backendRecipeItemsFor(seed.name)!.rows) {
        if (row['isSignature'] != true) continue;
        for (final sub in _subs(row)) {
          expect(sub['role'], row['role'],
              reason: '${seed.name} / ${row['name']} → ${sub['name']}');
        }
        expect(row['isOptional'], isNot(true), reason: '${row['name']}');
      }
    }
  });

  test('no row or substitute conflicts with the vegan check', () {
    for (final seed in seeds) {
      for (final row in backendRecipeItemsFor(seed.name)!.rows) {
        for (final food in [row, ..._subs(row)]) {
          final verdict = classifyVegan(food['name']! as String);
          expect(verdict.isVegan, isTrue,
              reason: '${seed.name} / ${food['name']}: '
                  '${verdict.nonVeganReason}');
        }
      }
    }
  });

  test('allergens are annotated, and allergenic rows have a way out', () {
    for (final seed in seeds) {
      for (final row in backendRecipeItemsFor(seed.name)!.rows) {
        for (final food in [row, ..._subs(row)]) {
          final name = food['name']! as String;
          expect(_allergens(food), containsAll(detectDishAllergens(name)),
              reason: '${seed.name} / $name');
        }
        if (_subs(row).isEmpty) continue;
        for (final allergen in _allergens(row)) {
          expect(
              _subs(row).any((s) => !_allergens(s).contains(allergen)), isTrue,
              reason: '${seed.name} / ${row['name']} has no option without '
                  '$allergen');
        }
      }
    }
  });

  group('recipeFromBackend', () {
    Map<String, dynamic> response(String name, List<Object?> rows) => {
          'id': '6ae595c796695f5c139fa99b',
          'name': name,
          'calories': 450,
          'allergens': ['gluten'],
          'ingredients': rows,
          'instructions': ['Nấu'],
        };

    const dish = 'Đậu hũ sốt cà chua & cơm lứt';
    const rows = ['Đậu hũ', 'Cà chua', 'Gạo lứt', 'Hành boa-rô', 'Nước tương'];

    test('a seed recipe gets the table, keeping the BE figures', () {
      final recipe = recipeFromBackend(response(dish, rows)).toEntity();
      expect(recipe.isReadOnly, isFalse);
      expect(recipe.isFromBackend, isTrue);
      expect(recipe.isCustomizable, isTrue);
      expect(recipe.caloriesCache, 450,
          reason: 'the BE figure is the one shown');
      expect(recipe.servings, 2);
      expect(recipe.ingredient('dau_hu')!.isSignature, isTrue);
      expect(recipe.ingredient('dau_hu')!.amount, '400 g');
      expect(recipe.allergens, containsAll(['gluten', 'soy']),
          reason: 'what the BE tags, and what the rows contain');
    });

    test('the name matches without accents or case', () {
      final recipe =
          recipeFromBackend(response('ĐẬU HŨ SỐT cà chua  & cơm lứt', rows))
              .toEntity();
      expect(recipe.isCustomizable, isTrue);
    });

    test('a row the table does not know is kept as the BE wrote it', () {
      final recipe =
          recipeFromBackend(response(dish, [...rows, 'Rau răm'])).toEntity();
      expect(recipe.ingredients.map((i) => i.name), [...rows, 'Rau răm']);
      expect(recipe.ingredients.last.isFreeText, isTrue);
    });

    test('an unknown name stays read-only', () {
      final recipe =
          recipeFromBackend(response('Món mới', ['Đậu hũ'])).toEntity();
      expect(recipe.isReadOnly, isTrue);
      expect(recipe.servings, isNull, reason: 'never made up');
    });

    test('ingredientItems from the BE wins over the table', () {
      final recipe = recipeFromBackend({
        ...response(dish, rows),
        'servings': 4,
        'ingredientItems': [
          {
            'key': 'mien',
            'name': 'Miến',
            'quantity': 100,
            'unit': 'g',
            'isSignature': true,
            'substitutes': [
              {'key': 'bun', 'name': 'Bún', 'quantity': 100, 'unit': 'g'},
            ],
          },
        ],
      }).toEntity();
      expect(recipe.ingredients.single.name, 'Miến');
      expect(recipe.servings, 4);
      expect(recipe.isCustomizable, isTrue);
    });
  });

  group('a variant saved with POST /recipes, read back', () {
    const dish = 'Đậu hũ sốt cà chua & cơm lứt';

    Map<String, dynamic> saved(List<String> rows) => {
          'id': '6ae5962596695f5c139fa9b6',
          'name': 'Đậu hũ sốt (tuỳ chỉnh)',
          'calories': 400,
          'ingredients': rows,
          'instructions': [savedVariantNote(dish, 2), 'Nấu'],
        };

    test('the note is taken out of the steps and gives the origin', () {
      final json = withSavedVariantItems(saved(['Đậu hũ 400 g']));
      expect(json['instructions'], ['Nấu']);
      expect(json['basedOnName'], dish);
      expect(json['servings'], 2);
      expect(json['nutritionEstimated'], isTrue);
    });

    test('rows find their way back: signature kept, the original offered', () {
      final json = withSavedVariantItems(
          saved(['Nấm đùi gà 400 g', 'Cà chua 250 g', 'Rau răm 5 g']));
      final rows = (json['ingredients']! as List<Object?>);
      final swapped = rows.first! as Map<String, Object?>;
      expect(swapped['name'], 'Nấm đùi gà');
      expect(swapped['isSignature'], isTrue);
      expect(_subs(swapped).map((s) => s['name']), contains('Đậu hũ'));
      expect((rows[1]! as Map<String, Object?>)['name'], 'Cà chua');
      expect(rows.last, 'Rau răm 5 g', reason: 'typed by hand: stays text');
    });

    test('an edited amount brings its nutrition along', () {
      final json = withSavedVariantItems(saved(['Đậu hũ 200 g']));
      final row = (json['ingredients']! as List<Object?>).single!
          as Map<String, Object?>;
      expect(row['quantity'], 200);
      expect(_kcalOf(row), closeTo(152, 0.1));
    });

    test('a recipe the member just wrote is left alone', () {
      final json = {
        'name': dish,
        'ingredients': ['Đậu hũ'],
        'instructions': ['Nấu'],
      };
      expect(withSavedVariantItems(json), same(json));
    });
  });
}
