// lib/features/recipe/data/mock/recipe_mock_data.dart
//
// Recipe-detail catalogue for mock mode, in the GET /recipes/{id} wire format.
// Covers every dish the planner mock can place (weekday menus, swap pool,
// seasonal swaps, pantry dishes), the scanner suggestions menu_1..menu_3,
// fridge-scan copies (`fs_<id>`) and the recipe book (member / chef recipes).
//
// Catalogue rows carry the customization annotations (key, role,
// signature / optional flags, allergens, per-row nutrition for the whole
// recipe, substitutes). Nutrition figures are reference values (Bảng thành
// phần thực phẩm Việt Nam / USDA FoodData Central); a figure without a
// source is left out. Recipe-book rows (member / chef) stay unannotated.
import '../../../meal_planner/data/mock/meal_planner_mock_data.dart';
import '../../../meal_planner/data/mock/mock_recipe_book.dart';
import 'recipe_substitution_data.dart';

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
        'key': 'bun',
        'ingredientId': 'ing_bun',
        'name': 'Bún tươi',
        'quantity': 400,
        'unit': 'g',
        'role': 'Sợi bún',
        'allergens': <String>[],
        'nutrition': {
          'calories': 440,
          'proteinG': 6.8,
          'carbsG': 102.8,
          'fatG': 0.4
        },
        'substitutes': [
          {
            'key': 'bun_gao_lut',
            'name': 'Bún gạo lứt',
            'quantity': 400,
            'unit': 'g',
            'note': 'Nhiều chất xơ hơn',
            'allergens': <String>[],
            'nutrition': {
              'calories': 420,
              'proteinG': 8,
              'carbsG': 92,
              'fatG': 1.6,
              'fiberG': 4
            },
          },
          {
            'key': 'pho_tuoi',
            'name': 'Bánh phở tươi',
            'quantity': 400,
            'unit': 'g',
            'allergens': <String>[],
          },
        ],
      },
      {
        'key': 'ca_chua',
        'ingredientId': 'ing_ca_chua',
        'name': 'Cà chua',
        'quantity': 4,
        'unit': 'quả',
        'role': 'Nước dùng',
        'allergens': <String>[],
        'nutrition': {
          'calories': 89,
          'proteinG': 4.4,
          'carbsG': 19.2,
          'fatG': 1.0,
          'fiberG': 5.9
        },
      },
      {
        'key': 'rieu',
        'ingredientId': 'ing_dau_hu',
        'name': 'Đậu hũ',
        'quantity': 300,
        'unit': 'g',
        'role': 'Riêu',
        'isSignature': true,
        'allergens': ['soy'],
        'nutrition': {
          'calories': 228,
          'proteinG': 24.3,
          'carbsG': 5.7,
          'fatG': 14.4,
          'fiberG': 0.9
        },
        'substitutes': [
          {
            'key': 'rieu_nam',
            'ingredientId': 'ing_nam_rom',
            'name': 'Nấm rơm băm nhuyễn',
            'quantity': 300,
            'unit': 'g',
            'note': 'Riêu nấm: nhẹ hơn, ít đạm hơn',
            'allergens': <String>[],
            'nutrition': {
              'calories': 96,
              'proteinG': 11.4,
              'carbsG': 13.8,
              'fatG': 2.1,
              'fiberG': 7.5
            },
          },
          {
            'key': 'rieu_dau_nanh',
            'name': 'Đậu nành ngâm xay',
            'quantity': 150,
            'unit': 'g',
            'note': 'Riêu đậu nành: đậm vị, nhiều đạm',
            'allergens': ['soy'],
            'nutrition': {
              'calories': 260,
              'proteinG': 24.9,
              'carbsG': 14.9,
              'fatG': 13.5,
              'fiberG': 9
            },
          },
        ],
      },
      {
        'key': 'nam_rom',
        'ingredientId': 'ing_nam_rom',
        'name': 'Nấm rơm',
        'quantity': 200,
        'unit': 'g',
        'role': 'Riêu',
        'allergens': <String>[],
        'nutrition': {
          'calories': 64,
          'proteinG': 7.6,
          'carbsG': 9.2,
          'fatG': 1.4,
          'fiberG': 5
        },
        'substitutes': [
          {
            'key': 'nam_bao_ngu',
            'name': 'Nấm bào ngư',
            'quantity': 200,
            'unit': 'g',
            'allergens': <String>[],
            'nutrition': {
              'calories': 66,
              'proteinG': 6.6,
              'carbsG': 12.2,
              'fatG': 0.8,
              'fiberG': 4.6
            },
          },
        ],
      },
      {
        'key': 'cu_cai',
        'ingredientId': 'ing_cu_cai',
        'name': 'Củ cải trắng',
        'quantity': 1,
        'unit': 'củ',
        'role': 'Nước dùng',
        'allergens': <String>[],
      },
      {
        'key': 'bap',
        'ingredientId': 'ing_bap',
        'name': 'Bắp ngô',
        'quantity': 2,
        'unit': 'bắp',
        'role': 'Nước dùng',
        'allergens': <String>[],
      },
      {
        'key': 'mam_ruoc',
        'ingredientId': 'ing_mam_ruoc',
        'name': 'Mắm ruốc chay',
        'quantity': 1,
        'unit': 'muỗng canh',
        'role': 'Gia vị',
        'isOptional': true,
        'allergens': ['soy'],
        'nutrition': {
          'calories': 15,
          'proteinG': 1.5,
          'carbsG': 1.5,
          'fatG': 0.3
        },
      },
      {
        'key': 'hanh_tim',
        'ingredientId': 'ing_hanh_tim',
        'name': 'Hành tím',
        'quantity': 3,
        'unit': 'củ',
        'role': 'Gia vị',
        'allergens': <String>[],
      },
      {
        'key': 'rau_muong',
        'ingredientId': 'ing_rau_muong',
        'name': 'Rau muống chẻ',
        'quantity': 200,
        'unit': 'g',
        'role': 'Rau ăn kèm',
        'isOptional': true,
        'allergens': <String>[],
        'nutrition': {
          'calories': 38,
          'proteinG': 5.2,
          'carbsG': 6.2,
          'fatG': 0.4,
          'fiberG': 4.2
        },
        'substitutes': [
          {
            'key': 'rau_song',
            'name': 'Rau sống thập cẩm',
            'quantity': 150,
            'unit': 'g',
            'allergens': <String>[],
            'nutrition': {'calories': 30},
          },
        ],
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
      {
        'key': 'dau_hu',
        'ingredientId': 'ing_dau_hu',
        'name': 'Đậu hũ',
        'quantity': 300,
        'unit': 'g',
        'role': 'Đạm',
        'isSignature': true,
        'allergens': ['soy'],
        'nutrition': {
          'calories': 228,
          'proteinG': 24.3,
          'carbsG': 5.7,
          'fatG': 14.4,
          'fiberG': 0.9
        },
      },
      {
        'key': 'bong_cai',
        'ingredientId': 'ing_bong_cai_xanh',
        'name': 'Bông cải xanh',
        'quantity': 1,
        'unit': 'bông',
        'role': 'Rau củ',
        'allergens': <String>[],
        'substitutes': [
          {
            'key': 'bong_cai_trang',
            'name': 'Bông cải trắng',
            'quantity': 1,
            'unit': 'bông',
            'note': 'Vị ngọt nhẹ, mềm hơn',
            'allergens': <String>[],
          },
          {
            'key': 'cai_thia',
            'ingredientId': 'ing_cai_thia',
            'name': 'Cải thìa',
            'quantity': 4,
            'unit': 'cây',
            'note': 'Xào nhanh, giòn',
            'allergens': <String>[],
            'nutrition': {
              'calories': 31.2,
              'proteinG': 3.6,
              'carbsG': 5.3,
              'fatG': 0.5,
              'fiberG': 2.4
            },
          },
        ],
      },
      {
        'key': 'ca_rot',
        'ingredientId': 'ing_ca_rot',
        'name': 'Cà rốt',
        'quantity': 1,
        'unit': 'củ',
        'role': 'Rau củ',
        'allergens': <String>[],
        'nutrition': {
          'calories': 28.7,
          'proteinG': 0.6,
          'carbsG': 6.7,
          'fatG': 0.1,
          'fiberG': 2.0
        },
      },
      {
        'key': 'toi',
        'ingredientId': 'ing_toi',
        'name': 'Tỏi',
        'quantity': 3,
        'unit': 'tép',
        'role': 'Gia vị',
        'allergens': <String>[],
        'nutrition': {
          'calories': 13.4,
          'proteinG': 0.6,
          'carbsG': 3.0,
          'fatG': 0.0,
          'fiberG': 0.2
        },
      },
      {
        'key': 'nuoc_tuong',
        'name': 'Nước tương',
        'quantity': 2,
        'unit': 'muỗng canh',
        'role': 'Gia vị',
        'allergens': ['soy'],
        'nutrition': {
          'calories': 17,
          'proteinG': 2.6,
          'carbsG': 1.6,
          'fatG': 0.2
        },
        'substitutes': [
          {
            'key': 'hat_nem_nam',
            'name': 'Hạt nêm nấm chay',
            'quantity': 1,
            'unit': 'muỗng cà phê',
            'note': 'Không chứa đậu nành',
            'allergens': <String>[],
          },
        ],
      },
      {
        'key': 'dau_an',
        'name': 'Dầu ăn',
        'quantity': 1,
        'unit': 'muỗng canh',
        'role': 'Dầu',
        'allergens': <String>[],
        'nutrition': {
          'calories': 120,
          'proteinG': 0,
          'carbsG': 0,
          'fatG': 13.6
        },
        'substitutes': [
          {
            'key': 'it_dau',
            'name': 'Ít dầu ăn',
            'quantity': 1,
            'unit': 'muỗng cà phê',
            'note': 'Ít dầu: 1 muỗng cà phê, dùng chảo chống dính',
            'allergens': <String>[],
            'nutrition': {
              'calories': 40,
              'proteinG': 0,
              'carbsG': 0,
              'fatG': 4.5
            },
          },
        ],
      },
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
      {
        'key': 'ca_chua',
        'ingredientId': 'ing_ca_chua',
        'name': 'Cà chua',
        'quantity': 2,
        'unit': 'quả',
        'role': 'Nước canh',
        'isSignature': true,
        'allergens': <String>[],
        'nutrition': {
          'calories': 44.3,
          'proteinG': 2.2,
          'carbsG': 9.6,
          'fatG': 0.5,
          'fiberG': 3.0
        },
      },
      {
        'key': 'dau_hu',
        'ingredientId': 'ing_dau_hu',
        'name': 'Đậu hũ',
        'quantity': 200,
        'unit': 'g',
        'role': 'Đạm',
        'allergens': ['soy'],
        'nutrition': {
          'calories': 152,
          'proteinG': 16.2,
          'carbsG': 3.8,
          'fatG': 9.6,
          'fiberG': 0.6
        },
        'substitutes': [
          {
            'key': 'dau_hu_non',
            'ingredientId': 'ing_dau_hu_non',
            'name': 'Đậu hũ non',
            'quantity': 200,
            'unit': 'g',
            'note': 'Mềm, mịn hơn',
            'allergens': ['soy'],
            'nutrition': {
              'calories': 110,
              'proteinG': 9.6,
              'carbsG': 5.8,
              'fatG': 5.4,
              'fiberG': 0.2
            },
          },
          {
            'key': 'nam_rom',
            'ingredientId': 'ing_nam_rom',
            'name': 'Nấm rơm',
            'quantity': 200,
            'unit': 'g',
            'note': 'Không chứa đậu nành',
            'allergens': <String>[],
            'nutrition': {
              'calories': 64,
              'proteinG': 7.6,
              'carbsG': 9.2,
              'fatG': 1.4,
              'fiberG': 5
            },
          },
        ],
      },
      {
        'key': 'hanh_la',
        'name': 'Hành lá',
        'quantity': 2,
        'unit': 'nhánh',
        'role': 'Rau thơm',
        'isOptional': true,
        'allergens': <String>[],
      },
      {
        'key': 'rau_thom',
        'name': 'Rau thơm',
        'quantity': 1,
        'unit': 'nắm',
        'role': 'Rau thơm',
        'isOptional': true,
        'allergens': <String>[],
      },
      {
        'key': 'hat_nem',
        'name': 'Hạt nêm nấm',
        'quantity': 1,
        'unit': 'muỗng cà phê',
        'role': 'Gia vị',
        'allergens': <String>[],
      },
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
      {
        'key': 'com',
        'name': 'Cơm nguội',
        'quantity': 2,
        'unit': 'chén',
        'role': 'Cơm',
        'isSignature': true,
        'allergens': <String>[],
        // 2 chén ≈ 300 g cơm trắng (USDA: 130 kcal / 100 g).
        'nutrition': {
          'calories': 390,
          'proteinG': 8.1,
          'carbsG': 84.6,
          'fatG': 0.9,
          'fiberG': 1.2
        },
        'substitutes': [
          {
            'key': 'com_gao_lut',
            'ingredientId': 'ing_gao_lut',
            'name': 'Cơm gạo lứt nguội',
            'quantity': 2,
            'unit': 'chén',
            'note': 'Nhiều chất xơ hơn',
            'allergens': <String>[],
            'nutrition': {
              'calories': 369,
              'proteinG': 8.1,
              'carbsG': 76.8,
              'fatG': 3.0,
              'fiberG': 4.8
            },
          },
        ],
      },
      {
        'key': 'ca_rot',
        'ingredientId': 'ing_ca_rot',
        'name': 'Cà rốt',
        'quantity': 1,
        'unit': 'củ',
        'role': 'Rau củ',
        'allergens': <String>[],
        'nutrition': {
          'calories': 28.7,
          'proteinG': 0.6,
          'carbsG': 6.7,
          'fatG': 0.1,
          'fiberG': 2.0
        },
      },
      {
        'key': 'bong_cai',
        'ingredientId': 'ing_bong_cai_xanh',
        'name': 'Bông cải xanh',
        'quantity': 0.5,
        'unit': 'bông',
        'role': 'Rau củ',
        'allergens': <String>[],
      },
      {
        'key': 'rau_chan_vit',
        'ingredientId': 'ing_rau_chan_vit',
        'name': 'Rau chân vịt',
        'quantity': 1,
        'unit': 'bó',
        'role': 'Rau lá',
        'allergens': <String>[],
        'nutrition': {
          'calories': 57.5,
          'proteinG': 7.3,
          'carbsG': 9.0,
          'fatG': 1.0,
          'fiberG': 5.5
        },
        'substitutes': [
          {
            'key': 'cai_thia',
            'ingredientId': 'ing_cai_thia',
            'name': 'Cải thìa',
            'quantity': 4,
            'unit': 'cây',
            'note': 'Giòn, ngọt nhẹ',
            'allergens': <String>[],
            'nutrition': {
              'calories': 31.2,
              'proteinG': 3.6,
              'carbsG': 5.3,
              'fatG': 0.5,
              'fiberG': 2.4
            },
          },
        ],
      },
      {
        'key': 'hat_nem',
        'name': 'Hạt nêm nấm',
        'quantity': 1,
        'unit': 'muỗng cà phê',
        'role': 'Gia vị',
        'allergens': <String>[],
      },
      {
        'key': 'dau_an',
        'name': 'Dầu ăn',
        'quantity': 2,
        'unit': 'muỗng canh',
        'role': 'Dầu',
        'allergens': <String>[],
        'nutrition': {
          'calories': 240,
          'proteinG': 0,
          'carbsG': 0,
          'fatG': 27.2
        },
        'substitutes': [
          {
            'key': 'it_dau',
            'name': 'Ít dầu ăn',
            'quantity': 2,
            'unit': 'muỗng cà phê',
            'note': 'Ít dầu: dùng chảo chống dính',
            'allergens': <String>[],
            'nutrition': {
              'calories': 80,
              'proteinG': 0,
              'carbsG': 0,
              'fatG': 9.0
            },
          },
        ],
      },
    ],
    'instructions':
        '1. Cà rốt và bông cải thái hạt lựu, rau chân vịt cắt khúc.\n'
            '2. Xào cà rốt, bông cải với dầu 3 phút.\n'
            '3. Cho cơm nguội vào, đảo lửa lớn đến khi hạt cơm săn.\n'
            '4. Thêm rau chân vịt, nêm hạt nêm nấm, đảo thêm 1 phút.',
  },
};

/// Whole words in a dish name → ingredient row (name, quantity, unit).
/// Longer keywords first so "nấm đông cô" wins over "nấm". Each row's role
/// and allergens come from [ingredientRoles] / [ingredientAllergens].
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
  ('lá lốt', 'Lá lốt', 10, 'lá'),
  ('rau mầm', 'Rau mầm', 50, 'g'),
  ('chanh', 'Chanh', 1, 'quả'),
  ('xoài', 'Xoài', 0.5, 'quả'),
  ('sữa chua dừa', 'Sữa chua dừa', 1, 'hũ'),
  ('bắp', 'Bắp', 1, 'bắp'),
  ('hạt bí', 'Hạt bí', 1, 'muỗng canh'),
  ('trái cây', 'Trái cây theo mùa', 150, 'g'),
  ('đậu đen', 'Đậu đen', 50, 'g'),
  ('edamame', 'Đậu nành Nhật (edamame)', 150, 'g'),
  ('sinh tố bơ', 'Bơ', 0.5, 'quả'),
  ('sữa hạt', 'Sữa hạt', 200, 'ml'),
  ('hummus', 'Sốt hummus', 3, 'muỗng canh'),
  ('táo', 'Táo', 1, 'quả'),
  ('hướng dương', 'Bơ hạt hướng dương', 1, 'muỗng canh'),
];

/// Every planner dish summary (wire JSON) by id.
Map<String, Map<String, Object?>> _plannerSummaries() => {
      for (final r in [
        ...mockBreakfasts,
        ...mockLunches,
        ...mockDinners,
        ...mockSnacks,
        for (final list in mockSwapPool.values) ...list,
        ...mockExtraDinners,
        ...mockSnackSwaps,
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

/// A catalogue row: the first one found in the dish name is its "Thành
/// phần chính" (only swapped within its role); every row is annotated with
/// its allergens, nutrition when the grams are known, and alternatives.
Map<String, Object?> _row(String name, num? quantity, String unit,
    {bool signature = false, bool optional = false, String? key}) {
  final rowKey = key ?? mockRowKey(name);
  return {
    'key': rowKey,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'role': ingredientRoles[name],
    if (signature) 'isSignature': true,
    if (optional) 'isOptional': true,
    'allergens': ingredientAllergens[name] ?? const <String>[],
    if (mockRowNutrition(name, quantity, unit) case final n?) 'nutrition': n,
    'substitutes':
        mockSubstitutesFor(name, rowKey: rowKey, signature: signature),
  };
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
    rows.add(_row(ingredient, qty, unit, signature: rows.isEmpty));
  }
  if (rows.isEmpty) {
    rows.add(_row('Rau củ theo mùa', 250, 'g', signature: true));
  }
  if (allergens.contains('soy') &&
      !rows.any((r) =>
          '${r['name']}'.contains('Đậu hũ') ||
          '${r['name']}' == 'Tempeh' ||
          '${r['name']}' == 'Sữa đậu nành')) {
    rows.add(_row('Nước tương', 1, 'muỗng canh'));
  }
  rows
    ..add(_row('Dầu ăn', 1, 'muỗng canh'))
    ..add(_row('Hạt nêm nấm', null, 'vừa ăn', optional: true));

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
