// lib/features/recipe/data/mock/recipe_mock_data.dart
//
// Recipe-detail catalogue for mock mode, in the GET /recipes/{id} wire format.
// Covers every dish the planner mock can place (weekday menus, swap pool,
// seasonal swaps, pantry dishes), the scanner suggestions menu_1..menu_3,
// fridge-scan copies (`fs_<id>`) and the recipe book (member / chef recipes).
import '../../../meal_planner/data/mock/meal_planner_mock_data.dart';
import '../../../meal_planner/data/mock/mock_recipe_book.dart';

/// Hand-written detail for the dishes people open most.
const Map<String, Map<String, Object?>> handWrittenRecipes = {
  'l5': {
    'id': 'l5',
    'name': 'Bún riêu chay',
    'caloriesCache': 580,
    'isVegan': true,
    'proteinG': 24,
    'carbsG': 86,
    'fatG': 12,
    'fiberG': 8,
    'allergens': ['soy'],
    'prepMinutes': 60,
    'servings': 2,
    'imageUrl': null,
    'ingredients': [
      {
        'ingredientId': 'ing_bun',
        'name': 'Bún tươi',
        'quantity': 400,
        'unit': 'g'
      },
      {
        'ingredientId': 'ing_ca_chua',
        'name': 'Cà chua',
        'quantity': 4,
        'unit': 'quả'
      },
      {
        'ingredientId': 'ing_dau_hu',
        'name': 'Đậu hũ',
        'quantity': 300,
        'unit': 'g'
      },
      {
        'ingredientId': 'ing_nam_rom',
        'name': 'Nấm rơm',
        'quantity': 200,
        'unit': 'g'
      },
      {
        'ingredientId': 'ing_cu_cai',
        'name': 'Củ cải trắng',
        'quantity': 1,
        'unit': 'củ'
      },
      {
        'ingredientId': 'ing_bap',
        'name': 'Bắp ngô',
        'quantity': 2,
        'unit': 'bắp'
      },
      {
        'ingredientId': 'ing_mam_ruoc',
        'name': 'Mắm ruốc chay',
        'quantity': 1,
        'unit': 'muỗng canh'
      },
      {
        'ingredientId': 'ing_hanh_tim',
        'name': 'Hành tím',
        'quantity': 3,
        'unit': 'củ'
      },
      {
        'ingredientId': 'ing_rau_muong',
        'name': 'Rau muống chẻ',
        'quantity': 200,
        'unit': 'g'
      },
    ],
    'instructions': '1. Hầm củ cải và bắp ngô 40 phút lấy nước dùng ngọt.\n'
        '2. Phi thơm hành tím, xào cà chua đến khi sệt rồi cho vào nồi.\n'
        '3. Tán đậu hũ với nấm rơm băm làm "riêu", thả từng muỗng khi nước sôi lăn tăn.\n'
        '4. Nêm muối, đường phèn và mắm ruốc chay cho vừa ăn.\n'
        '5. Chần bún, chan nước dùng, ăn kèm rau muống chẻ.',
  },
  'menu_1': {
    'id': 'menu_1',
    'name': 'Đậu hũ xào bông cải cà rốt',
    'caloriesCache': 420,
    'isVegan': true,
    'proteinG': 24,
    'carbsG': 38,
    'fatG': 18,
    'fiberG': 8,
    'allergens': ['soy'],
    'prepMinutes': 20,
    'servings': 2,
    'ingredients': [
      {'name': 'Đậu hũ', 'quantity': 300, 'unit': 'g'},
      {'name': 'Bông cải xanh', 'quantity': 1, 'unit': 'bông'},
      {'name': 'Cà rốt', 'quantity': 1, 'unit': 'củ'},
      {'name': 'Tỏi', 'quantity': 3, 'unit': 'tép'},
      {'name': 'Nước tương', 'quantity': 2, 'unit': 'muỗng canh'},
      {'name': 'Dầu ăn', 'quantity': 1, 'unit': 'muỗng canh'},
    ],
    'instructions': '1. Cắt đậu hũ miếng vuông, chiên vàng đều các mặt.\n'
        '2. Bông cải tách nhánh, cà rốt thái lát; chần sơ 1 phút.\n'
        '3. Phi thơm tỏi, cho rau củ vào xào lửa lớn 2 phút.\n'
        '4. Thêm đậu hũ và nước tương, đảo đều rồi tắt bếp.',
  },
  'menu_2': {
    'id': 'menu_2',
    'name': 'Canh cà chua đậu hũ rau thơm',
    'caloriesCache': 260,
    'isVegan': true,
    'proteinG': 14,
    'carbsG': 22,
    'fatG': 12,
    'fiberG': 5,
    'allergens': ['soy'],
    'prepMinutes': 15,
    'servings': 2,
    'ingredients': [
      {'name': 'Cà chua', 'quantity': 2, 'unit': 'quả'},
      {'name': 'Đậu hũ', 'quantity': 200, 'unit': 'g'},
      {'name': 'Hành lá', 'quantity': 2, 'unit': 'nhánh'},
      {'name': 'Rau thơm', 'quantity': 1, 'unit': 'nắm'},
      {'name': 'Hạt nêm nấm', 'quantity': 1, 'unit': 'muỗng cà phê'},
    ],
    'instructions': '1. Cà chua bổ múi cau, đậu hũ cắt miếng vừa ăn.\n'
        '2. Phi hành, xào cà chua cho ra màu rồi thêm 700 ml nước.\n'
        '3. Nước sôi thì cho đậu hũ, nêm hạt nêm nấm, đun 5 phút.\n'
        '4. Tắt bếp, rắc hành lá và rau thơm.',
  },
  'menu_3': {
    'id': 'menu_3',
    'name': 'Cơm chiên rau củ kiểu Việt',
    'caloriesCache': 540,
    'isVegan': true,
    'proteinG': 14,
    'carbsG': 84,
    'fatG': 15,
    'fiberG': 6,
    'allergens': <String>[],
    'prepMinutes': 25,
    'servings': 2,
    'ingredients': [
      {'name': 'Cơm nguội', 'quantity': 2, 'unit': 'chén'},
      {'name': 'Cà rốt', 'quantity': 1, 'unit': 'củ'},
      {'name': 'Bông cải xanh', 'quantity': 0.5, 'unit': 'bông'},
      {'name': 'Rau chân vịt', 'quantity': 1, 'unit': 'bó'},
      {'name': 'Hạt nêm nấm', 'quantity': 1, 'unit': 'muỗng cà phê'},
      {'name': 'Dầu ăn', 'quantity': 2, 'unit': 'muỗng canh'},
    ],
    'instructions':
        '1. Cà rốt và bông cải thái hạt lựu, rau chân vịt cắt khúc.\n'
            '2. Xào cà rốt, bông cải với dầu 3 phút.\n'
            '3. Cho cơm nguội vào, đảo lửa lớn đến khi hạt cơm săn.\n'
            '4. Thêm rau chân vịt, nêm hạt nêm nấm, đảo thêm 1 phút.',
  },
};

/// Whole words in a dish name → ingredient row (name, quantity, unit).
/// Longer keywords first so "nấm đông cô" wins over "nấm".
const List<(String, String, num, String)> _dictionary = [
  ('đậu hũ non', 'Đậu hũ non', 300, 'g'),
  ('đậu hũ', 'Đậu hũ', 200, 'g'),
  ('tempeh', 'Tempeh', 150, 'g'),
  ('nấm đông cô', 'Nấm đông cô', 6, 'cái'),
  ('nấm đùi gà', 'Nấm đùi gà', 200, 'g'),
  ('nấm rơm', 'Nấm rơm', 200, 'g'),
  ('nấm mèo', 'Nấm mèo', 30, 'g'),
  ('nấm', 'Nấm các loại', 150, 'g'),
  ('cà chua', 'Cà chua', 2, 'quả'),
  ('gạo lứt', 'Gạo lứt', 80, 'g'),
  ('yến mạch', 'Yến mạch cán', 50, 'g'),
  ('hạt chia', 'Hạt chia', 1, 'muỗng canh'),
  ('việt quất', 'Việt quất', 50, 'g'),
  ('bánh mì', 'Bánh mì', 1, 'ổ'),
  ('sả', 'Sả', 2, 'cây'),
  ('đậu xanh', 'Đậu xanh cà vỏ', 60, 'g'),
  ('mè', 'Mè đen', 1, 'muỗng canh'),
  ('chuối', 'Chuối', 1, 'quả'),
  ('bơ đậu phộng', 'Bơ đậu phộng', 1, 'muỗng canh'),
  ('đậu phộng', 'Đậu phộng', 30, 'g'),
  ('hạt điều', 'Hạt điều', 30, 'g'),
  ('bánh cuốn', 'Bánh cuốn', 250, 'g'),
  ('bún', 'Bún tươi', 200, 'g'),
  ('phở', 'Bánh phở', 200, 'g'),
  ('lá é', 'Lá é', 1, 'nắm'),
  ('cơm', 'Cơm', 1, 'chén'),
  ('mì soba', 'Mì soba', 100, 'g'),
  ('mì', 'Mì', 150, 'g'),
  ('rau củ', 'Rau củ thập cẩm', 200, 'g'),
  ('sa tế', 'Sa tế', 1, 'muỗng cà phê'),
  ('đậu gà', 'Đậu gà', 100, 'g'),
  ('nước cốt dừa', 'Nước cốt dừa', 100, 'ml'),
  ('cà ri', 'Bột cà ri', 1, 'muỗng canh'),
  ('canh chua', 'Thơm (dứa)', 100, 'g'),
  ('đậu lăng', 'Đậu lăng đỏ', 80, 'g'),
  ('lẩu', 'Nước dùng rau củ', 1, 'lít'),
  ('cà tím', 'Cà tím', 1, 'quả'),
  ('mỡ hành', 'Hành lá', 3, 'nhánh'),
  ('bí đỏ', 'Bí đỏ', 200, 'g'),
  ('quinoa', 'Hạt quinoa', 60, 'g'),
  ('chanh dây', 'Chanh dây', 1, 'quả'),
  ('bánh xèo', 'Bột bánh xèo', 150, 'g'),
  ('rau rừng', 'Rau rừng', 100, 'g'),
  ('gỏi cuốn', 'Bánh tráng', 8, 'lá'),
  ('khoai lang', 'Khoai lang', 200, 'g'),
  ('pancake', 'Bột yến mạch', 60, 'g'),
  ('sữa đậu nành', 'Sữa đậu nành', 250, 'ml'),
  ('bánh bao', 'Bánh bao chay', 2, 'cái'),
  ('rau muống', 'Rau muống', 200, 'g'),
  ('tiêu', 'Tiêu đen', 1, 'muỗng cà phê'),
  ('bông cải', 'Bông cải xanh', 1, 'bông'),
  ('cà rốt', 'Cà rốt', 1, 'củ'),
];

/// Every planner dish summary (wire JSON) by id.
Map<String, Map<String, Object?>> _plannerSummaries() => {
      for (final r in [
        ...mockBreakfasts,
        ...mockLunches,
        ...mockDinners,
        for (final list in mockSwapPool.values) ...list,
        ...mockPantryDishes,
      ])
        r['id']! as String: r,
    };

/// Detail JSON for [id], or `null` when the mock catalogue doesn't know it.
Map<String, Object?>? mockRecipeDetail(String id) {
  // Dishes added from the fridge scan keep their suggestion id after `fs_`.
  final key = id.startsWith('fs_') ? id.substring(3) : id;
  if (handWrittenRecipes[key] case final recipe?) return recipe;
  if (MockRecipeBook.findDetail(key) case final recipe?) return recipe;
  if (_plannerSummaries()[key] case final summary?) {
    return _generated(summary);
  }
  return null;
}

Map<String, Object?> _generated(Map<String, Object?> summary) {
  final name = summary['name']! as String;
  final allergens = (summary['allergens'] as List<Object?>? ?? const [])
      .map((a) => a.toString())
      .toList();

  final rows = <Map<String, Object?>>[];
  final seen = <String>{};
  var rest = ' ${name.toLowerCase()} ';
  for (final (keyword, ingredient, qty, unit) in _dictionary) {
    final k = ' $keyword ';
    if (!rest.contains(k) || seen.contains(ingredient)) continue;
    seen.add(ingredient);
    // Consume the words so "nấm" doesn't match again after "nấm rơm".
    rest = rest.replaceFirst(k, ' ');
    rows.add({'name': ingredient, 'quantity': qty, 'unit': unit});
  }
  if (rows.isEmpty) {
    rows.add({'name': 'Rau củ theo mùa', 'quantity': 250, 'unit': 'g'});
  }
  if (allergens.contains('soy') &&
      !rows.any((r) =>
          '${r['name']}'.contains('Đậu hũ') ||
          '${r['name']}' == 'Tempeh' ||
          '${r['name']}' == 'Sữa đậu nành')) {
    rows.add({'name': 'Nước tương', 'quantity': 1, 'unit': 'muỗng canh'});
  }
  rows
    ..add({'name': 'Dầu ăn', 'quantity': 1, 'unit': 'muỗng canh'})
    ..add({'name': 'Hạt nêm nấm', 'quantity': null, 'unit': 'vừa ăn'});

  final main =
      rows.take(2).map((r) => '${r['name']}'.toLowerCase()).join(' và ');
  final lowerName = name[0].toLowerCase() + name.substring(1);
  return {
    'id': summary['id'],
    'name': name,
    'caloriesCache': summary['calories'],
    'isVegan': true,
    'proteinG': summary['proteinG'],
    'carbsG': summary['carbsG'],
    'fatG': summary['fatG'],
    'fiberG': summary['fiberG'],
    'allergens': allergens,
    'prepMinutes': summary['prepMinutes'],
    'imageUrl': summary['imageUrl'],
    'servings': 1,
    'ingredients': rows,
    'instructions': '1. Sơ chế: rửa sạch và cắt $main vừa ăn.\n'
        '2. Phi thơm hành tỏi với chút dầu, cho nguyên liệu chính vào đảo đều.\n'
        '3. Nêm hạt nêm nấm, nấu thêm 5–10 phút đến khi chín và thấm vị.\n'
        '4. Bày ra đĩa, thưởng thức $lowerName khi còn nóng.',
  };
}

/// Every id the planner mock can put in a slot, for tests.
Iterable<String> plannerRecipeIds() => _plannerSummaries().keys;
