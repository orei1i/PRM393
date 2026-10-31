// test/recipe_customization/recipe_model_compat_test.dart
// GET /recipes/{id} parsing: the new optional fields, plain-string rows from
// the current BE, and older payloads that must keep working.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_detail.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_customization.dart';

RecipeDetail _parse(Map<String, dynamic> json) =>
    RecipeDetailDto.fromJson(json).toEntity();

void main() {
  test('plain-string ingredients (current BE): name-only or "name amount"', () {
    final r = _parse({
      'id': 'be1',
      'name': 'Canh',
      'instructions': ['Nấu.'],
      'ingredients': [
        'Đậu hũ',
        'Đậu hũ non 200 g',
        'Nấm rơm: 150 g',
        'Nước dùng 1,5 lít',
        'Chanh 2',
        '  ',
      ],
    });
    expect(r.ingredients.map((i) => i.name),
        ['Đậu hũ', 'Đậu hũ non', 'Nấm rơm', 'Nước dùng', 'Chanh']);
    expect(r.ingredients.map((i) => i.amount),
        ['', '200 g', '150 g', '1,5 lít', '2']);
    expect(r.ingredients.first.isFreeText, isTrue);
    expect(r.ingredients[1].quantity, 200);
    expect(r.ingredients.map((i) => i.key).toSet(), hasLength(5),
        reason: 'unique keys');
    expect(r.servings, isNull);
    expect(r.baseServings, 1, reason: 'no servings → scaled as 1');
    expect(r.isCustomizable, isFalse);
    // Name-only rows scale to nothing and read as the name alone.
    final cooked = CustomizedRecipe(r, const RecipeCustomization(servings: 2));
    expect(cooked.rows.first.amount, '');
    expect(cooked.rows[1].amount, '400 g');
  });

  test('older map rows keep "vừa ăn" / unit text and parse unchanged', () {
    final r = _parse({
      'id': 105,
      'name': 'Đậu hũ sốt',
      'instructions': '1. Nấu.',
      'caloriesCache': 520,
      'servings': 2,
      'someFutureField': {'x': 1},
      'ingredients': [
        {'ingredientId': 7, 'name': 'Đậu hũ', 'quantity': 200, 'unit': 'g'},
        {
          'ingredientId': 7,
          'name': 'Đậu hũ chiên',
          'quantity': 100,
          'unit': 'g'
        },
        {'name': 'Muối', 'quantity': null, 'unit': ''},
        {'name': 'Tiêu', 'unit': 'vừa đủ'},
      ],
    });
    expect(r.id, '105');
    expect(r.ingredients.map((i) => i.amount),
        ['200 g', '100 g', 'vừa ăn', 'vừa đủ']);
    expect(r.ingredients.map((i) => i.key), ['7', '7_1', 'row2', 'row3'],
        reason: 'key falls back to ingredientId, then row index; unique');
    expect(r.ingredients.first.allergens, isNull, reason: 'not annotated');
    expect(r.ingredients.first.substitutes, isEmpty);
    expect(r.averageRating, isNull);
    expect(r.ratingCount, 0);
    expect(r.isVariant, isFalse);
    expect(r.isPublic, isTrue);
  });

  test('annotated rows, substitutes, rating and variant fields', () {
    final r = _parse({
      'id': 'ur_1',
      'name': 'Bún riêu chay (tuỳ chỉnh)',
      'instructions': '1. Nấu.',
      'caloriesCache': 514,
      'servings': 2,
      'createdBy': 'u_me',
      'createdByName': 'Minh Anh',
      'averageRating': 4.6,
      'ratingCount': 5,
      'basedOnRecipeId': 'l5',
      'basedOnName': 'Bún riêu chay',
      'nutritionEstimated': true,
      'customizations': [
        {'type': 'swap', 'from': 'Đậu hũ', 'to': 'Nấm rơm băm nhuyễn'},
        {'type': 'remove', 'name': 'Rau muống chẻ'},
        {'type': 'unknown'},
      ],
      'ingredients': [
        {
          'key': 'rieu',
          'name': 'Nấm rơm băm nhuyễn',
          'quantity': 300,
          'unit': 'g',
          'role': 'Riêu',
          'isSignature': true,
          'allergens': <String>[],
          'nutrition': {'calories': 96, 'proteinG': 11.4},
          'substitutes': [
            {
              'key': 'rieu_goc',
              'name': 'Đậu hũ',
              'quantity': 300,
              'unit': 'g',
              'allergens': ['soy'],
              'nutrition': {'calories': 228},
            },
            {'name': 'Đậu nành ngâm xay', 'quantity': 150, 'unit': 'g'},
          ],
        },
        {
          'key': 'mam',
          'name': 'Mắm ruốc chay',
          'quantity': 1,
          'unit': 'muỗng canh',
          'isOptional': true,
          'nutrition': {},
        },
      ],
    });
    expect(r.averageRating, 4.6);
    expect(r.ratingCount, 5);
    expect(r.isVariant, isTrue);
    expect(r.isPublic, isFalse);
    expect(r.basedOnName, 'Bún riêu chay');
    expect(r.nutritionEstimated, isTrue);
    expect(r.customizations.map((c) => c.label),
        ['Đã đổi Đậu hũ → Nấm rơm băm nhuyễn', 'Đã bỏ Rau muống chẻ']);
    final rieu = r.ingredient('rieu')!;
    expect(rieu.isSignature, isTrue);
    expect(rieu.role, 'Riêu');
    expect(rieu.allergens, isEmpty);
    expect(rieu.nutrition?.calories, 96);
    expect(rieu.nutrition?.fatG, isNull);
    expect(rieu.substitutes.map((s) => s.key), ['rieu_goc', 'sub1']);
    expect(rieu.substitute('rieu_goc')?.allergens, ['soy']);
    expect(rieu.substitutes[1].allergens, isNull);
    expect(r.ingredient('mam')!.isOptional, isTrue);
    expect(r.ingredient('mam')!.nutrition, isNull, reason: 'empty → none');
    expect(r.isCustomizable, isTrue);
  });

  test('rows round-trip through the wire format', () {
    const row = RecipeIngredient(
      key: 'rieu',
      name: 'Đậu hũ',
      quantity: 300,
      unit: 'g',
      role: 'Riêu',
      isSignature: true,
      allergens: ['soy'],
      nutrition: IngredientNutrition(calories: 228, proteinG: 24.3),
      substitutes: [
        RecipeSubstitute(
            key: 'rieu_nam', name: 'Nấm rơm', quantity: 300, unit: 'g'),
      ],
    );
    final back = RecipeIngredientDto.fromJson(
            Map<String, dynamic>.from(recipeIngredientToJson(row)))
        .toEntity();
    expect(back.key, 'rieu');
    expect(back.isSignature, isTrue);
    expect(back.allergens, ['soy']);
    expect(back.nutrition?.proteinG, 24.3);
    expect(back.substitutes.single.key, 'rieu_nam');
    expect(back.substitutes.single.allergens, isNull);
  });

  test('variant request body and name rules', () {
    final body = CreateVariantRequestDto.fromChoices(
        '  Bún riêu chay (tuỳ chỉnh) ',
        const RecipeCustomization(
            swaps: {'rieu': 'rieu_nam'}, removed: {'rau_muong'})).toJson();
    expect(body, {
      'name': 'Bún riêu chay (tuỳ chỉnh)',
      'swaps': [
        {'ingredientKey': 'rieu', 'substituteKey': 'rieu_nam'},
      ],
      'removed': ['rau_muong'],
    });
    final back = CreateVariantRequestDto.fromJson(body);
    expect(back.choices.swaps, {'rieu': 'rieu_nam'});
    expect(back.choices.removed, {'rau_muong'});
    expect(validateVariantName(' a '), 'Nhập tên công thức (ít nhất 2 ký tự).');
    expect(validateVariantName('x' * 81), 'Tên tối đa 80 ký tự.');
    expect(validateVariantName('Bún riêu'), isNull);
    expect(defaultVariantName('Bún riêu chay'), 'Bún riêu chay (tuỳ chỉnh)');
  });
}
