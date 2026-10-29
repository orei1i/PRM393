// test/recipe_customization/recipe_mock_data_test.dart
// The annotated mock catalogue: every recipe parses, generated recipes have
// one "Thành phần chính", substitutes are vegan (and same-role for a
// signature row), keys are unique, nutrition is never negative.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/recipe/data/mock/recipe_mock_data.dart';
import 'package:veganlife_mobile/features/recipe/data/mock/recipe_substitution_data.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_detail.dart';
import 'package:veganlife_mobile/features/scanner/domain/vegan_check.dart';

RecipeDetail _recipe(String id) =>
    RecipeDetailDto.fromJson(Map<String, dynamic>.from(mockRecipeDetail(id)!))
        .toEntity();

void main() {
  final handWritten = handWrittenRecipes.keys.toSet();
  final all = {...handWritten, ...plannerRecipeIds()};
  final generated = all.difference(handWritten);

  test('every catalogue recipe parses with rows and steps', () {
    expect(all.length, greaterThan(40));
    for (final id in all) {
      final r = _recipe(id);
      expect(r.ingredients, isNotEmpty, reason: id);
      expect(r.steps, isNotEmpty, reason: id);
      expect(r.caloriesCache, greaterThan(0), reason: id);
      expect(r.isPublic, isTrue, reason: id);
    }
  });

  test(
      'generated recipes: one signature row, all rows annotated, the '
      'recipe allergens explained by rows, "Hạt nêm nấm" optional', () {
    for (final id in generated) {
      final r = _recipe(id);
      expect(r.ingredients.where((i) => i.isSignature), hasLength(1),
          reason: id);
      expect(r.ingredients.first.isSignature, isTrue, reason: id);
      for (final i in r.ingredients) {
        expect(i.allergens, isNotNull, reason: '$id ${i.name}');
        expect(i.role, isNotNull, reason: '$id ${i.name}');
      }
      final listed = {for (final i in r.ingredients) ...?i.allergens};
      expect(listed.containsAll(r.allergens), isTrue, reason: id);
      final seasoning = r.ingredients.last;
      expect(seasoning.name, 'Hạt nêm nấm');
      expect(seasoning.isOptional, isTrue);
      expect(seasoning.amount, 'vừa ăn');
      expect(r.isCustomizable, isTrue, reason: id);
    }
  });

  test('substitutes are vegan; a signature row only offers its own role', () {
    for (final id in all) {
      final r = _recipe(id);
      for (final row in r.ingredients) {
        for (final s in row.substitutes) {
          expect(classifyVegan(s.name).isVegan, isTrue,
              reason: '$id ${row.name} → ${s.name}');
          expect(s.allergens, isNotNull, reason: '$id ${s.name}');
          if (row.isSignature && generated.contains(id)) {
            expect(ingredientRoles[s.name], row.role,
                reason: '$id ${row.name} → ${s.name}');
          }
        }
      }
    }
    // Hand-written: the riêu of Bún riêu chay stays a riêu.
    final rieu = _recipe('l5').ingredient('rieu')!;
    expect(rieu.isSignature, isTrue);
    expect(rieu.role, 'Riêu');
    expect(rieu.substitutes.map((s) => s.name),
        ['Nấm rơm băm nhuyễn', 'Đậu nành ngâm xay']);
    // Đậu hũ as a signature only gets Tempeh (Nấm đùi gà is another role).
    final dauHu = mockSubstitutesFor('Đậu hũ', rowKey: 'x', signature: true);
    expect(dauHu.map((s) => s['name']), ['Tempeh']);
    expect(
        mockSubstitutesFor('Đậu hũ', rowKey: 'x', signature: false)
            .map((s) => s['name']),
        ['Tempeh', 'Nấm đùi gà']);
  });

  test('keys are unique per recipe; nutrition is never negative', () {
    for (final id in all) {
      final r = _recipe(id);
      final keys = [
        for (final row in r.ingredients) ...[
          row.key,
          for (final s in row.substitutes) s.key,
        ],
      ];
      expect(keys.toSet(), hasLength(keys.length), reason: '$id $keys');
      final figures = [
        for (final row in r.ingredients) ...[
          row.nutrition,
          for (final s in row.substitutes) s.nutrition,
        ],
      ].nonNulls;
      for (final n in figures) {
        for (final f in RecipeNutrient.values) {
          expect(n.of(f) ?? 0, greaterThanOrEqualTo(0), reason: id);
        }
      }
    }
  });

  test('hand-written annotations (§9)', () {
    final menu1 = _recipe('menu_1');
    final dauHu = menu1.ingredient('dau_hu')!;
    expect(dauHu.isSignature, isTrue);
    expect(dauHu.substitutes, isEmpty);
    expect(menu1.ingredient('bong_cai')!.substitutes.map((s) => s.name),
        ['Bông cải trắng', 'Cải thìa']);
    expect(menu1.ingredient('nuoc_tuong')!.substitutes.single.name,
        'Hạt nêm nấm chay');

    final menu2 = _recipe('menu_2');
    expect(menu2.ingredient('ca_chua')!.isSignature, isTrue);
    expect(menu2.ingredient('dau_hu')!.substitutes.map((s) => s.name),
        ['Đậu hũ non', 'Nấm rơm']);
    expect(menu2.ingredients.where((i) => i.isOptional).map((i) => i.name),
        ['Hành lá', 'Rau thơm']);

    final menu3 = _recipe('menu_3');
    expect(menu3.ingredient('com')!.isSignature, isTrue);
    expect(
        menu3.ingredient('com')!.substitutes.single.name, 'Cơm gạo lứt nguội');
    expect(
        menu3.ingredient('rau_chan_vit')!.substitutes.single.name, 'Cải thìa');
    expect(menu3.ingredient('dau_an')!.substitutes.single.name, 'Ít dầu ăn');
  });

  test('generated nutrition comes from the DB only when grams are known', () {
    // "Đậu hũ kho nấm rơm": Đậu hũ 200 g × 76 kcal / 100 g.
    final d3 = _recipe('d3');
    expect(d3.ingredient('dau_hu')!.nutrition?.calories, 152);
    expect(d3.ingredient('nam_rom')!.nutrition?.calories, 64);
    // "Bánh mì đậu hũ sả ớt": no DB row for bánh mì → no figure.
    final b2 = _recipe('b2');
    expect(b2.ingredients.firstWhere((i) => i.name == 'Bánh mì').nutrition,
        isNull);
    // "1 quả" is the DB's alt serving for Chuối (118 g).
    expect(mockRowNutrition('Chuối', 1, 'quả')?['calories'], 105.0);
    expect(mockRowNutrition('Bông cải xanh', 1, 'bông'), isNull);
    expect(mockRowNutrition('Sữa yến mạch', 250, 'ml'), isNull,
        reason: 'only exact DB names, never "yến mạch" inside another name');
  });

  test('the recipe book (member / chef recipes) stays unannotated', () {
    final r = _recipe('cs_tam_chao_yen_mach');
    expect(r.isPublic, isFalse);
    expect(r.isCustomizable, isFalse);
    expect(r.ingredients.every((i) => i.allergens == null), isTrue);
  });
}
