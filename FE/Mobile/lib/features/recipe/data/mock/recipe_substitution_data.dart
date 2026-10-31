// lib/features/recipe/data/mock/recipe_substitution_data.dart
//
// Annotations for the generated mock recipes (every planner dish): the part
// of the dish each ingredient makes ("vai trò"), its allergens, vegan
// alternatives (allergy-aware) and nutrition taken from the mock nutrition
// DB. A figure is only given when the grams are known (g / ml, or the
// unit is the DB row's alt serving, e.g. "1 quả" = 123 g); otherwise it is
// left out rather than guessed.
import '../../../../core/utils/text_search.dart';
import '../../../ingredient/data/mock/ingredient_nutrition_data.dart';

/// The part of the dish an ingredient makes, for the dictionary rows and
/// every substitute below. A signature row is only swapped within its role.
const Map<String, String> ingredientRoles = {
  // Đạm
  'Đậu hũ': 'Đạm',
  'Đậu hũ non': 'Đạm',
  'Tempeh': 'Đạm',
  'Đậu nành Nhật (edamame)': 'Đạm',
  'Đậu gà': 'Đạm',
  'Đậu lăng đỏ': 'Đạm',
  'Đậu xanh cà vỏ': 'Đạm',
  'Đậu đen': 'Đạm',
  // Nấm
  'Nấm đông cô': 'Nấm',
  'Nấm đùi gà': 'Nấm',
  'Nấm rơm': 'Nấm',
  'Nấm mèo': 'Nấm',
  'Nấm các loại': 'Nấm',
  'Nấm bào ngư': 'Nấm',
  // Tinh bột
  'Gạo lứt': 'Tinh bột',
  'Gạo trắng': 'Tinh bột',
  'Cơm': 'Tinh bột',
  'Cơm gạo lứt': 'Tinh bột',
  'Yến mạch cán': 'Tinh bột',
  'Bột yến mạch': 'Tinh bột',
  'Bánh mì': 'Tinh bột',
  'Bánh mì gạo không gluten': 'Tinh bột',
  'Bánh bao chay': 'Tinh bột',
  'Bột bánh xèo': 'Tinh bột',
  'Hạt quinoa': 'Tinh bột',
  'Khoai lang': 'Tinh bột',
  'Bắp': 'Tinh bột',
  // Sợi & vỏ
  'Bún tươi': 'Sợi',
  'Bún gạo lứt': 'Sợi',
  'Bánh phở': 'Sợi',
  'Bánh cuốn': 'Sợi',
  'Mì': 'Sợi',
  'Mì soba': 'Sợi',
  'Miến dong': 'Sợi',
  'Bánh tráng': 'Vỏ cuốn',
  // Rau củ
  'Cà chua': 'Rau củ',
  'Rau củ thập cẩm': 'Rau củ',
  'Rau củ theo mùa': 'Rau củ',
  'Cà tím': 'Rau củ',
  'Bí đỏ': 'Rau củ',
  'Bông cải xanh': 'Rau củ',
  'Cà rốt': 'Rau củ',
  'Rau muống': 'Rau lá',
  'Rau rừng': 'Rau lá',
  'Rau mầm': 'Rau lá',
  'Lá é': 'Rau thơm',
  'Lá lốt': 'Rau thơm',
  'Hành lá': 'Rau thơm',
  // Trái cây
  'Việt quất': 'Trái cây',
  'Chuối': 'Trái cây',
  'Xoài': 'Trái cây',
  'Trái cây theo mùa': 'Trái cây',
  'Chanh dây': 'Trái cây',
  'Táo': 'Trái cây',
  'Bơ': 'Trái cây',
  // Hạt
  'Hạt chia': 'Hạt',
  'Mè đen': 'Hạt',
  'Đậu phộng': 'Hạt',
  'Hạt điều': 'Hạt',
  'Hạt bí': 'Hạt',
  'Hạt hướng dương': 'Hạt',
  'Bơ đậu phộng': 'Bơ hạt',
  'Bơ hạt hướng dương': 'Bơ hạt',
  // Sữa
  'Sữa đậu nành': 'Sữa',
  'Sữa yến mạch': 'Sữa',
  'Sữa hạt': 'Sữa',
  'Sữa chua dừa': 'Sữa',
  'Nước cốt dừa': 'Sữa',
  // Nước dùng, sốt, gia vị
  'Thơm (dứa)': 'Nước dùng',
  'Nước dùng rau củ': 'Nước dùng',
  'Sốt hummus': 'Sốt',
  'Sa tế': 'Gia vị',
  'Bột cà ri': 'Gia vị',
  'Tiêu đen': 'Gia vị',
  'Sả': 'Gia vị',
  'Chanh': 'Gia vị',
  'Nước tương': 'Gia vị',
  'Hạt nêm nấm': 'Gia vị',
  'Hạt nêm nấm chay': 'Gia vị',
  'Dầu ăn': 'Dầu',
  'Ít dầu ăn': 'Dầu',
};

/// Allergen ids of the ingredients that have any (everything else: none).
const Map<String, List<String>> ingredientAllergens = {
  'Đậu hũ': ['soy'],
  'Đậu hũ non': ['soy'],
  'Tempeh': ['soy'],
  'Đậu nành Nhật (edamame)': ['soy'],
  'Sữa đậu nành': ['soy'],
  'Nước tương': ['soy'],
  'Đậu phộng': ['peanut'],
  'Bơ đậu phộng': ['peanut'],
  'Bánh mì': ['gluten'],
  'Bánh bao chay': ['gluten'],
  'Mì': ['gluten'],
  'Mì soba': ['gluten'],
  'Mè đen': ['sesame'],
  'Hạt điều': ['tree_nut'],
};

/// Vegan alternatives per ingredient: (name, quantity, unit, note). Picked
/// to keep the dish and, where it matters, to avoid a common allergen. A
/// signature row only offers those of its own role ([ingredientRoles]).
const Map<String, List<(String, num, String, String)>> _alternatives = {
  'Đậu hũ': [
    ('Tempeh', 150, 'g', 'Chắc, nhiều đạm hơn'),
    ('Nấm đùi gà', 200, 'g', 'Không chứa đậu nành'),
  ],
  'Đậu hũ non': [('Đậu hũ', 300, 'g', 'Chắc hơn, dễ chiên')],
  'Tempeh': [('Đậu hũ', 200, 'g', 'Mềm, dễ mua')],
  'Nấm rơm': [('Nấm bào ngư', 200, 'g', 'Dai, ngọt nhẹ')],
  'Nấm đùi gà': [('Nấm bào ngư', 200, 'g', 'Mềm hơn')],
  'Bún tươi': [('Bún gạo lứt', 200, 'g', 'Nhiều chất xơ hơn')],
  'Mì': [('Miến dong', 150, 'g', 'Không chứa gluten')],
  'Mì soba': [('Miến dong', 100, 'g', 'Không chứa gluten')],
  'Gạo lứt': [('Gạo trắng', 80, 'g', 'Mềm, dễ ăn hơn')],
  'Cơm': [('Cơm gạo lứt', 1, 'chén', 'Nhiều chất xơ hơn')],
  'Nước tương': [
    ('Hạt nêm nấm chay', 1, 'muỗng cà phê', 'Không chứa đậu nành'),
  ],
  'Đậu phộng': [('Hạt hướng dương', 30, 'g', 'Không chứa đậu phộng')],
  'Bơ đậu phộng': [
    ('Bơ hạt hướng dương', 1, 'muỗng canh', 'Không chứa đậu phộng'),
  ],
  'Mè đen': [('Hạt bí', 1, 'muỗng canh', 'Không chứa mè')],
  'Bánh mì': [('Bánh mì gạo không gluten', 1, 'ổ', 'Không chứa gluten')],
  'Hạt điều': [('Hạt bí', 30, 'g', 'Không chứa hạt cây')],
  'Sữa đậu nành': [('Sữa yến mạch', 250, 'ml', 'Không chứa đậu nành')],
  'Dầu ăn': [('Ít dầu ăn', 1, 'muỗng cà phê', 'Ít dầu: dùng chảo chống dính')],
};

/// "Đậu nành Nhật (edamame)" → `dau_nanh_nhat_edamame`.
String mockRowKey(String name) => foldVietnamese(name)
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// The substitutes of a generated row, in the wire format.
List<Map<String, Object?>> mockSubstitutesFor(String name,
    {required String rowKey, required bool signature}) {
  final role = ingredientRoles[name];
  return [
    for (final (sub, qty, unit, note)
        in _alternatives[name] ?? const <(String, num, String, String)>[])
      if (!signature || ingredientRoles[sub] == role)
        {
          'key': '${rowKey}_${mockRowKey(sub)}',
          'name': sub,
          'quantity': qty,
          'unit': unit,
          'note': note,
          'allergens': ingredientAllergens[sub] ?? const <String>[],
          if (mockRowNutrition(sub, qty, unit) case final n?) 'nutrition': n,
        },
  ];
}

/// The nutrition DB row named exactly [name] (or one of its aliases).
Map<String, Object?>? _dbRow(String name) {
  final target = foldVietnamese(name.trim());
  for (final row in mockIngredientRows) {
    final names = [
      row['name']! as String,
      ...(row['aliases'] as List<Object?>? ?? const []).map((a) => '$a'),
    ];
    if (names.any((n) => foldVietnamese(n.trim()) == target)) return row;
  }
  return null;
}

/// What [quantity] [unit] of [name] brings to the recipe, from the DB's
/// per-100 g figures, when the grams are known; else `null`.
Map<String, Object?>? mockRowNutrition(
    String name, num? quantity, String unit) {
  final q = quantity;
  final row = _dbRow(name);
  if (q == null || q <= 0 || row == null) return null;
  final u = unit.trim().toLowerCase();
  double? grams;
  if (u == 'g' || u == 'ml') {
    grams = q.toDouble();
  } else {
    final alt = row['altServing'] as Map<String, Object?>?;
    final label = '${alt?['label'] ?? ''}'.trim().toLowerCase();
    final altUnit = label.replaceFirst(RegExp(r'^[\d.,]+\s*'), '');
    final altGrams = alt?['grams'];
    if (altUnit == u && altGrams is num) grams = (q * altGrams).toDouble();
  }
  if (grams == null) return null;
  final per100 = row['per100g']! as Map<String, Object?>;
  double? scaled(String key) => switch (per100[key]) {
        final num v => double.parse((v * grams! / 100).toStringAsFixed(1)),
        _ => null,
      };
  return {
    'calories': scaled('calories'),
    if (scaled('proteinG') case final v?) 'proteinG': v,
    if (scaled('carbsG') case final v?) 'carbsG': v,
    if (scaled('fatG') case final v?) 'fatG': v,
    if (scaled('fiberG') case final v?) 'fiberG': v,
  };
}
