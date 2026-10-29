// test/recipe_customization/recipe_customization_test.dart
// "Đảm bảo calo" and "Thành phần chính" on Bún riêu chay (l5): the §4.2
// worked cases E1–E4, warnings W1/W2/W3, the default meal to compare with,
// signature / substitute validation, the conservative allergen rule and the
// shopping list.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/meal_planner_mock_data.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';
import 'package:veganlife_mobile/features/recipe/data/mock/recipe_mock_data.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_detail.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_customization.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_customization_controller.dart';

RecipeDetail _recipe(String id) =>
    RecipeDetailDto.fromJson(Map<String, dynamic>.from(mockRecipeDetail(id)!))
        .toEntity();

CustomizedRecipe _l5(
        {Map<String, String> swaps = const {},
        Set<String> removed = const {},
        int? servings}) =>
    CustomizedRecipe(
      _recipe('l5'),
      RecipeCustomization(swaps: swaps, removed: removed, servings: servings),
    );

/// Minh Anh: 172 cm, 66 kg, Nữ, sinh 1997, Nhẹ, Tăng cơ, 3 bữa + 1 phụ.
HealthProfile _minhAnh() =>
    HealthProfileDto.fromJson(mockHealthProfileJson(syncProvider: 'none'))
        .toEntity();

void main() {
  final targets = slotTargets(_minhAnh());
  final dinner = targets[MealSlot.dinner]!;
  final dinnerLabel = '≈ ${Energy.formatKcal(dinner)} kcal';
  int pct(double e) => ((e - dinner) / dinner * 100).abs().round();

  test('targets follow the profile (energy.dart) and the meals of the day', () {
    final daily = _minhAnh().dailyKcalTarget!;
    expect(targets.keys, [
      MealSlot.breakfast,
      MealSlot.lunch,
      MealSlot.snackPm,
      MealSlot.dinner,
    ]);
    expect(targets, MealPattern.kcalTargets(_minhAnh().mealPattern, daily));
  });

  group('energy (§4.2)', () {
    test('unmodified: exact original figures, no "≈", fits dinner', () {
      final c = _l5();
      expect(c.isModified, isFalse);
      expect(c.energy.modified, isFalse);
      expect(c.energy.shown, 580);
      expect(c.energy.delta, 0);
      expect(c.energy.macroLine,
          'Đạm 24 g · Tinh bột 86 g · Béo 12 g · Chất xơ 8 g');
      expect(c.energy.largeChangeWarning, isNull);
      expect(c.energy.unknownWarning, isNull);
      expect(c.allergens, ['soy']);

      final slot = defaultCompareSlot(targets, c.energy.original);
      expect(slot, MealSlot.dinner, reason: 'closest to the original 580');
      final cmp = SlotComparison(slot: slot!, target: dinner, energy: 580);
      expect(cmp.fits, isTrue);
      expect(cmp.message, 'Vừa với mục tiêu bữa tối ($dinnerLabel)');
    });

    test('E1 riêu đậu hũ → riêu nấm: ≈ 514, −66, macros, below dinner', () {
      final c = _l5(swaps: {'rieu': 'rieu_nam'});
      final e = c.energy;
      expect(e.modified, isTrue);
      expect(e.exact, 514);
      expect(e.shown, 514);
      expect(e.delta, -66);
      expect(e.ratio, closeTo(-0.114, 0.001));
      expect(e.largeChangeWarning, isNull, reason: '|p| < 15 %');
      expect(e.unknownWarning, isNull);
      expect(e.proteinG, closeTo(17.55, 1e-9));
      expect(e.macroLine, 'Đạm 18 g · Tinh bột 90 g · Béo 6 g · Chất xơ 11 g');
      expect(c.allergens, ['soy'], reason: 'mắm ruốc still has soy');

      final cmp = SlotComparison(
          slot: MealSlot.dinner, target: dinner, energy: e.exact!);
      expect(cmp.fits, isFalse);
      expect(cmp.message,
          'Thấp hơn mục tiêu bữa tối ${pct(514)} % ($dinnerLabel)');
    });

    test('E2 = E1 + bỏ rau muống + bỏ mắm ruốc: ≈ 488, W1 −16 %', () {
      final c =
          _l5(swaps: {'rieu': 'rieu_nam'}, removed: {'rau_muong', 'mam_ruoc'});
      final e = c.energy;
      expect(e.exact, 487.5);
      expect(e.shown, 488);
      expect(e.delta, -92);
      expect(
          e.largeChangeWarning, 'Năng lượng giảm 16 % so với công thức gốc.');
      expect(e.unknownWarning, isNull);
      expect(c.allergens, isEmpty, reason: 'every row annotated, none soy');
      expect(
          SlotComparison(slot: MealSlot.dinner, target: dinner, energy: 487.5)
              .message,
          'Thấp hơn mục tiêu bữa tối ${pct(487.5)} % ($dinnerLabel)');
    });

    test('E3 bún tươi → bánh phở tươi (no data): ≈ 580 + W3', () {
      final e = _l5(swaps: {'bun': 'pho_tuoi'}).energy;
      expect(e.modified, isTrue);
      expect(e.shown, 580);
      expect(e.delta, 0);
      expect(e.unknown, ['Bánh phở tươi']);
      expect(e.unknownWarning,
          'Chưa có số liệu dinh dưỡng của «Bánh phở tươi» — năng lượng là ước tính.');
    });

    test('E4 riêu đậu nành: ≈ 596, +16, still soy, no warnings', () {
      final c = _l5(swaps: {'rieu': 'rieu_dau_nanh'});
      expect(c.energy.shown, 596);
      expect(c.energy.delta, 16);
      expect(c.energy.ratio, closeTo(0.028, 0.001));
      expect(c.energy.largeChangeWarning, isNull);
      expect(c.energy.unknownWarning, isNull);
      expect(c.allergens, ['soy']);
    });

    test('E1 cooked for 3: per serving unchanged, total = E × N', () {
      final c = _l5(swaps: {'rieu': 'rieu_nam'}, servings: 3);
      expect(c.servings, 3);
      expect(c.energy.shown, 514);
      expect(c.energy.totalFor(3), 1542);
      expect(_l5(servings: 5).energy.shown, 580);
    });

    test('no kcal on the recipe → no energy figures', () {
      const r = RecipeDetail(
        id: 'x',
        name: 'Món chưa có số liệu',
        instructions: '1. Nấu.',
        ingredients: [
          RecipeIngredient(
              key: 'a', name: 'Đậu hũ', isOptional: true, allergens: ['soy']),
        ],
      );
      final e =
          CustomizedRecipe(r, const RecipeCustomization(removed: {'a'})).energy;
      expect(e.original, isNull);
      expect(e.shown, isNull);
      expect(e.totalFor(2), isNull);
      expect(e.largeChangeWarning, isNull);
    });
  });

  group('meal to compare with', () {
    test('context slot wins when it is one of the member\'s meals', () {
      expect(defaultCompareSlot(targets, 580, contextSlot: MealSlot.lunch),
          MealSlot.lunch);
      expect(defaultCompareSlot(targets, 580, contextSlot: MealSlot.snackLate),
          MealSlot.dinner,
          reason: 'an extra meal has no target');
    });

    test('no energy estimate (no gender / birth year) → no targets', () {
      final tam = HealthProfileDto.fromJson(
              mockHealthProfileJsonFor('u_chef_tam', syncProvider: 'none')!)
          .toEntity();
      expect(tam.dailyKcalTarget, isNull);
      expect(slotTargets(tam), isEmpty);
      expect(defaultCompareSlot(const {}, 580), isNull);
    });

    test('W2 boundaries: ±10 % fits, above is "Cao hơn"', () {
      const t = 600;
      expect(
          const SlotComparison(slot: MealSlot.lunch, target: t, energy: 660)
              .fits,
          isTrue);
      expect(
          const SlotComparison(slot: MealSlot.lunch, target: t, energy: 700)
              .message,
          'Cao hơn mục tiêu bữa trưa 17 % (≈ 600 kcal)');
      expect(
          const SlotComparison(slot: MealSlot.snackPm, target: 200, energy: 150)
              .message,
          'Thấp hơn mục tiêu phụ chiều 25 % (≈ 200 kcal)');
    });
  });

  group('signature & substitutes (D7)', () {
    test('a signature row cannot be removed; substitutes must be listed', () {
      final l5 = _recipe('l5');
      final noSignature = validateCustomization(
          l5, const RecipeCustomization(removed: {'rieu'}));
      expect(noSignature?.code, 'signature_required');
      expect(noSignature?.message,
          'Không thể bỏ «Đậu hũ» — đây là thành phần chính của món.');
      expect(
          validateCustomization(
                  l5, const RecipeCustomization(swaps: {'rieu': 'bun_gao_lut'}))
              ?.code,
          'invalid_substitute');
      expect(
          validateCustomization(
              l5, const RecipeCustomization(removed: {'khong_co'}))?.code,
          'invalid_ingredient');
      expect(
          validateCustomization(
              l5,
              const RecipeCustomization(
                  swaps: {'rieu': 'rieu_nam'}, removed: {'rau_muong'})),
          isNull);
    });

    test('the controller refuses to remove a signature row', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = recipeCustomizationProvider('l5');
      container.listen(provider, (_, __) {});
      final controller = container.read(provider.notifier);
      final l5 = _recipe('l5');

      expect(controller.remove(l5.ingredient('rieu')!), isFalse);
      expect(container.read(provider).choices.isModified, isFalse);

      controller.swap(l5.ingredient('rieu')!, 'not_listed');
      expect(container.read(provider).choices.swaps, isEmpty);

      controller.swap(l5.ingredient('rieu')!, 'rieu_nam');
      expect(controller.remove(l5.ingredient('rau_muong')!), isTrue);
      expect(container.read(provider).choices.changeCount, 2);
      controller.setServings(3, base: 2);
      controller.resetIngredients();
      final after = container.read(provider).choices;
      expect(after.isModified, isFalse);
      expect(after.servings, 3, reason: '"Đặt lại" keeps the servings');
      controller.setServings(2, base: 2);
      expect(container.read(provider).choices.servings, isNull);
      controller.setServings(99, base: 2);
      expect(container.read(provider).choices.servings, 20);
    });
  });

  group('allergens (D10)', () {
    test('E1 + bỏ mắm ruốc clears a soy allergy; options are tagged', () {
      final l5 = _recipe('l5');
      expect(_l5().allergenConflicts(['soy']), ['soy']);
      expect(
          _l5(swaps: {'rieu': 'rieu_nam'}).allergenConflicts(['soy']), ['soy']);
      expect(
          _l5(swaps: {'rieu': 'rieu_nam'}, removed: {'mam_ruoc'})
              .allergenConflicts(['soy']),
          isEmpty);

      final rieu = l5.ingredient('rieu')!;
      final nam = substituteAllergyInfo(
          rieu, rieu.substitute('rieu_nam')!, const ['soy']);
      expect(nam.isSafe, isTrue);
      expect(nam.avoids, ['soy']);
      final dauNanh = substituteAllergyInfo(
          rieu, rieu.substitute('rieu_dau_nanh')!, const ['soy']);
      expect(dauNanh.isSafe, isFalse);
      expect(dauNanh.conflicts, ['soy']);
      expect(dauNanh.avoids, isEmpty);
    });

    test('free-text allergies match the rows as cooked', () {
      expect(_l5().allergenConflicts(['nấm rơm']), ['nấm rơm']);
      expect(
          _l5(swaps: {'nam_rom': 'nam_bao_ngu', 'rieu': 'rieu_dau_nanh'})
              .allergenConflicts(['nấm rơm']),
          isEmpty);
    });

    test('an unannotated recipe keeps its allergens', () {
      const r = RecipeDetail(
        id: 'r',
        name: 'Gỏi',
        instructions: '1. Trộn.',
        allergens: ['soy', 'peanut'],
        ingredients: [
          RecipeIngredient(key: 'a', name: 'Rau'), // not annotated
          RecipeIngredient(
              key: 'b',
              name: 'Nước tương',
              isOptional: true,
              allergens: ['soy']),
        ],
      );
      final c = CustomizedRecipe(r, const RecipeCustomization(removed: {'b'}));
      expect(c.allergens, ['soy', 'peanut']);
    });

    test('an allergen no row explains is kept', () {
      const r = RecipeDetail(
        id: 'r',
        name: 'Bánh',
        instructions: '1. Nướng.',
        allergens: ['gluten'],
        ingredients: [
          RecipeIngredient(key: 'a', name: 'Bột', allergens: []),
          RecipeIngredient(
              key: 'b', name: 'Mè', isOptional: true, allergens: ['sesame']),
        ],
      );
      expect(
          CustomizedRecipe(r, const RecipeCustomization(removed: {'b'}))
              .allergens,
          ['gluten']);
    });
  });

  group('shopping list & variant rows', () {
    test('scaled, customized, removed rows omitted, "vừa ăn" kept', () {
      final c =
          _l5(swaps: {'rieu': 'rieu_nam'}, removed: {'rau_muong'}, servings: 3);
      expect(
          c.shoppingList(),
          'Đi chợ: Bún riêu chay (3 người)\n'
          '- Bún tươi: 600 g\n'
          '- Cà chua: 6 quả\n'
          '- Nấm rơm băm nhuyễn: 450 g\n'
          '- Nấm rơm: 300 g\n'
          '- Củ cải trắng: 1,5 củ\n'
          '- Bắp ngô: 3 bắp\n'
          '- Mắm ruốc chay: 1,5 muỗng canh\n'
          '- Hành tím: 4,5 củ');

      const freeText = RecipeDetail(
        id: 'f',
        name: 'Canh',
        instructions: '1. Nấu.',
        ingredients: [
          RecipeIngredient(key: 'a', name: 'Đậu hũ', isFreeText: true),
          RecipeIngredient(key: 'b', name: 'Hạt nêm nấm', unit: 'vừa ăn'),
        ],
      );
      expect(
          CustomizedRecipe(freeText, const RecipeCustomization(servings: 3))
              .shoppingList(),
          'Đi chợ: Canh (3 người)\n- Đậu hũ\n- Hạt nêm nấm: vừa ăn');
    });

    test(
        'a variant keeps keys, roles and flags; the original becomes an '
        'option', () {
      final c =
          _l5(swaps: {'rieu': 'rieu_nam'}, removed: {'rau_muong', 'mam_ruoc'});
      expect(c.changeNotes().map((n) => n.label), [
        'Đã đổi Đậu hũ → Nấm rơm băm nhuyễn',
        'Đã bỏ Mắm ruốc chay',
        'Đã bỏ Rau muống chẻ',
      ]);
      final rows = c.variantRows();
      expect(rows.map((r) => r.key),
          ['bun', 'ca_chua', 'rieu', 'nam_rom', 'cu_cai', 'bap', 'hanh_tim']);
      final rieu = rows[2];
      expect(rieu.name, 'Nấm rơm băm nhuyễn');
      expect(rieu.isSignature, isTrue);
      expect(rieu.role, 'Riêu');
      expect(
          rieu.substitutes.map((s) => s.name), ['Đậu hũ', 'Đậu nành ngâm xay']);
    });
  });
}
