// lib/features/meal_planner/data/mock/meal_planner_mock_data.dart
// Realistic Vietnamese vegan sample data, shaped exactly like the API JSON so
// the DTO parsers are exercised in mock mode too.

import '../../../../core/session/mock_accounts.dart';

Map<String, Object?> _r(
  String id,
  String name, {
  required int kcal,
  required num p,
  required num c,
  required num f,
  required num fi,
  List<String> allergens = const [],
  List<String> tags = const [],
  int prep = 20,
  Map<String, Object?>? seasonal,
}) =>
    {
      'id': id,
      'name': name,
      'imageUrl': null,
      'calories': kcal,
      'proteinG': p,
      'carbsG': c,
      'fatG': f,
      'fiberG': fi,
      'allergens': allergens,
      'dietTags': tags,
      'prepMinutes': prep,
      if (seasonal != null) 'seasonalSwap': seasonal,
    };

/// One entry per weekday (Mon → Sun).
final List<Map<String, Object?>> mockBreakfasts = [
  _r('b1', 'Yến mạch ngâm hạt chia & việt quất',
      kcal: 420,
      p: 18,
      c: 62,
      f: 12,
      fi: 11,
      tags: ['whole_food', 'high_fiber'],
      prep: 5),
  _r('b2', 'Bánh mì đậu hũ sả ớt',
      kcal: 460,
      p: 22,
      c: 58,
      f: 15,
      fi: 6,
      allergens: ['gluten', 'soy'],
      tags: ['quick']),
  _r('b3', 'Xôi đậu xanh mè đen',
      kcal: 440, p: 14, c: 78, f: 8, fi: 7, allergens: ['sesame']),
  _r('b4', 'Sinh tố chuối bơ đậu phộng',
      kcal: 480,
      p: 19,
      c: 60,
      f: 19,
      fi: 9,
      allergens: ['peanut'],
      tags: ['quick'],
      prep: 5),
  _r('b5', 'Cháo yến mạch hạt điều nấm',
      kcal: 390, p: 15, c: 55, f: 13, fi: 8, allergens: ['tree_nut']),
  _r('b6', 'Bánh cuốn chay nhân nấm mèo',
      kcal: 410, p: 13, c: 72, f: 7, fi: 5, allergens: ['soy']),
  _r('b7', 'Đậu hũ non chưng nấm & bánh mì đen',
      kcal: 430,
      p: 24,
      c: 48,
      f: 14,
      fi: 7,
      allergens: ['soy', 'gluten'],
      tags: ['high_protein']),
];

final List<Map<String, Object?>> mockLunches = [
  _r('l1', 'Cơm gạo lứt tempeh áp chảo',
      kcal: 640,
      p: 38,
      c: 78,
      f: 18,
      fi: 11,
      allergens: ['soy'],
      tags: ['high_protein'],
      prep: 25,
      seasonal: {'ingredient': 'bí đỏ', 'recipeId': 'ls1'}),
  _r('l2', 'Bún chả chay đậu hũ nướng',
      kcal: 610, p: 30, c: 88, f: 14, fi: 7, allergens: ['soy']),
  _r('l3', 'Phở chay nấm đông cô',
      kcal: 560,
      p: 22,
      c: 90,
      f: 10,
      fi: 6,
      allergens: ['soy'],
      tags: ['low_sodium']),
  _r('l4', 'Cơm chiên lá é đậu hũ',
      kcal: 620, p: 26, c: 84, f: 19, fi: 6, allergens: ['soy']),
  _r('l5', 'Bún riêu chay',
      kcal: 580, p: 24, c: 86, f: 12, fi: 8, allergens: ['soy']),
  _r('l6', 'Mì xào rau củ sốt sa tế đậu phộng',
      kcal: 700,
      p: 27,
      c: 86,
      f: 27,
      fi: 8,
      allergens: ['peanut', 'gluten', 'soy']),
  _r('l7', 'Cơm gà chay nấm đùi gà xé phay',
      kcal: 600, p: 28, c: 82, f: 15, fi: 7, allergens: ['soy']),
];

final List<Map<String, Object?>> mockDinners = [
  _r('d1', 'Cà ri đậu gà nước cốt dừa',
      kcal: 610, p: 22, c: 70, f: 26, fi: 14, tags: ['high_fiber'], prep: 30),
  _r('d2', 'Canh chua chay & cơm gạo lứt',
      kcal: 520,
      p: 18,
      c: 86,
      f: 10,
      fi: 9,
      allergens: ['soy'],
      tags: ['low_sodium']),
  _r('d3', 'Đậu hũ kho nấm rơm',
      kcal: 560,
      p: 29,
      c: 60,
      f: 21,
      fi: 7,
      allergens: ['soy'],
      tags: ['high_protein']),
  _r('d4', 'Đậu lăng đỏ hầm & cơm gạo lứt',
      kcal: 590,
      p: 29,
      c: 92,
      f: 9,
      fi: 15,
      tags: ['high_fiber', 'high_protein'],
      seasonal: {'ingredient': 'khoai lang', 'recipeId': 'ds1'}),
  _r('d5', 'Lẩu nấm chay',
      kcal: 540, p: 24, c: 70, f: 16, fi: 10, allergens: ['soy']),
  _r('d6', 'Bò lúc lắc chay nấm đùi gà',
      kcal: 600, p: 27, c: 64, f: 24, fi: 8, allergens: ['soy']),
  _r('d7', 'Cà tím nướng mỡ hành & đậu hũ',
      kcal: 550, p: 23, c: 62, f: 22, fi: 10, allergens: ['soy']),
];

/// Extra recipes the "swap" sheet can offer, per slot.
final Map<String, List<Map<String, Object?>>> mockSwapPool = {
  'breakfast': [
    _r('bs1', 'Bún gạo lứt trộn rau thơm & đậu hũ',
        kcal: 415, p: 20, c: 60, f: 10, fi: 8, allergens: ['soy']),
    _r('bs2', 'Pancake chuối yến mạch',
        kcal: 400, p: 14, c: 64, f: 9, fi: 7, tags: ['whole_food'], prep: 15),
    _r('bs3', 'Sữa đậu nành & bánh bao chay',
        kcal: 450, p: 21, c: 66, f: 10, fi: 5, allergens: ['soy', 'gluten']),
    _r('bs4', 'Bánh mì bơ đậu phộng chuối',
        kcal: 440, p: 15, c: 58, f: 17, fi: 6, allergens: ['peanut', 'gluten']),
  ],
  'lunch': [
    _r('ls1', 'Cơm gạo lứt tempeh & bí đỏ nướng',
        kcal: 630,
        p: 36,
        c: 84,
        f: 16,
        fi: 12,
        allergens: ['soy'],
        tags: ['seasonal', 'high_protein'],
        prep: 30),
    _r('ls2', 'Salad quinoa đậu gà sốt chanh dây',
        kcal: 590, p: 24, c: 80, f: 18, fi: 14, tags: ['high_fiber'], prep: 20),
    _r('ls3', 'Bánh xèo chay rau rừng',
        kcal: 620, p: 18, c: 82, f: 24, fi: 8, prep: 35),
    _r('ls4', 'Gỏi cuốn chay chấm tương đậu phộng',
        kcal: 600, p: 22, c: 80, f: 20, fi: 7, allergens: ['peanut', 'soy']),
  ],
  'dinner': [
    _r('ds1', 'Đậu lăng hầm khoai lang & cơm lứt',
        kcal: 580,
        p: 26,
        c: 96,
        f: 8,
        fi: 16,
        tags: ['seasonal', 'high_fiber'],
        prep: 35),
    _r('ds2', 'Súp bí đỏ đậu lăng',
        kcal: 560, p: 25, c: 82, f: 12, fi: 16, tags: ['high_fiber']),
    _r('ds3', 'Nấm kho tiêu & cơm gạo lứt',
        kcal: 570, p: 18, c: 90, f: 14, fi: 9, allergens: ['soy']),
    _r('ds4', 'Mì soba rau củ sốt mè',
        kcal: 600, p: 22, c: 88, f: 17, fi: 9, allergens: ['gluten', 'sesame']),
  ],
};

/// Planner-only extras kept out of [mockSwapPool] (other mocks list that
/// pool): more dinners the swap sheet and the AI can offer.
final List<Map<String, Object?>> mockExtraDinners = [
  _r('ds5', 'Đậu hũ cuốn lá lốt nướng',
      kcal: 520, p: 26, c: 40, f: 26, fi: 6, allergens: ['soy'], prep: 35),
  _r('ds6', 'Salad đậu lăng rau mầm sốt chanh',
      kcal: 430, p: 22, c: 48, f: 14, fi: 14, tags: ['high_fiber'], prep: 15),
];

/// One snack per weekday (Mon → Sun), for "Phụ sáng", "Phụ chiều" and
/// "Phụ tối".
final List<Map<String, Object?>> mockSnacks = [
  _r('sn1', 'Sữa chua dừa hạt chia & xoài',
      kcal: 220, p: 4, c: 26, f: 11, fi: 6, tags: ['high_fiber'], prep: 5),
  _r('sn2', 'Chuối nướng bơ đậu phộng',
      kcal: 230,
      p: 6,
      c: 30,
      f: 10,
      fi: 4,
      allergens: ['peanut'],
      tags: ['quick'],
      prep: 10),
  _r('sn3', 'Bắp luộc',
      kcal: 180, p: 6, c: 38, f: 2.5, fi: 4, tags: ['whole_food'], prep: 15),
  _r('sn4', 'Sữa đậu nành & hạt điều rang',
      kcal: 240,
      p: 11,
      c: 16,
      f: 15,
      fi: 2,
      allergens: ['soy', 'tree_nut'],
      tags: ['quick'],
      prep: 3),
  _r('sn5', 'Khoai lang luộc',
      kcal: 170, p: 3, c: 39, f: 0.3, fi: 5, tags: ['whole_food'], prep: 20),
  _r('sn6', 'Trái cây theo mùa & hạt bí',
      kcal: 190, p: 5, c: 28, f: 7, fi: 5, tags: ['quick'], prep: 5),
  _r('sn7', 'Chè đậu đen nước cốt dừa',
      kcal: 240, p: 7, c: 42, f: 5, fi: 6, prep: 30),
];

/// Extra snacks the swap sheet and the AI can offer.
final List<Map<String, Object?>> mockSnackSwaps = [
  _r('ss1', 'Edamame luộc muối',
      kcal: 190, p: 17, c: 14, f: 8, fi: 8, allergens: ['soy'], prep: 10),
  _r('ss2', 'Sinh tố bơ sữa hạt',
      kcal: 260, p: 4, c: 22, f: 18, fi: 7, tags: ['quick'], prep: 5),
  _r('ss3', 'Hummus đậu gà & cà rốt que',
      kcal: 200, p: 7, c: 22, f: 9, fi: 6, tags: ['high_fiber'], prep: 10),
  _r('ss4', 'Bánh mì nướng bơ hạt điều',
      kcal: 250,
      p: 8,
      c: 28,
      f: 12,
      fi: 3,
      allergens: ['gluten', 'tree_nut'],
      prep: 5),
  _r('ss5', 'Táo & bơ hạt hướng dương',
      kcal: 210, p: 5, c: 24, f: 11, fi: 5, tags: ['quick'], prep: 3),
];

/// Dishes built around common fridge items, offered when the plan is
/// generated from the pantry (same ids as the scanner's menu suggestions, so
/// the recipe screen knows them).
final List<Map<String, Object?>> mockPantryDishes = [
  _r('menu_1', 'Đậu hũ xào bông cải cà rốt',
      kcal: 420,
      p: 24,
      c: 38,
      f: 18,
      fi: 8,
      allergens: ['soy'],
      tags: ['high_protein', 'quick']),
  _r('menu_3', 'Cơm chiên rau củ kiểu Việt',
      kcal: 540, p: 14, c: 84, f: 15, fi: 6, prep: 25),
  _r('pd_canh_ca_chua', 'Canh cà chua đậu hũ & cơm gạo lứt',
      kcal: 540,
      p: 24,
      c: 82,
      f: 12,
      fi: 8,
      allergens: ['soy'],
      tags: ['low_sodium'],
      prep: 25),
  _r('pd_nam_rom_kho', 'Nấm rơm kho tiêu & rau muống luộc',
      kcal: 500, p: 18, c: 76, f: 13, fi: 10, allergens: ['soy']),
];

const Map<String, Object?> mockDailyTargets = {
  'calories': 1850,
  'proteinG': 90,
  'carbsG': 240,
  'fatG': 60,
  'fiberG': 32,
};

/// [mockDailyTargets] scaled to [kcal] (the member's TDEE-based target).
Map<String, Object?> mockDailyTargetsFor(int kcal) {
  final f = kcal / 1850;
  int g(String key) => ((mockDailyTargets[key]! as int) * f).round();
  return {
    'calories': kcal,
    'proteinG': g('proteinG'),
    'carbsG': g('carbsG'),
    'fatG': g('fatG'),
    'fiberG': g('fiberG'),
  };
}

/// Seed profile per demo account: Minh Anh (`u_me`) gets
/// [mockHealthProfileJson] (with gender, birth year and "3 bữa + 1 phụ");
/// Lê Quang Tâm (`u_chef_tam`) has an older profile without them (3 meals,
/// no energy estimate until he adds gender and birth year). Anyone else (an
/// account registered in this run, a guest) has none yet: `null`, like the
/// server's 404, so the app asks them to set one up.
Map<String, Object?>? mockHealthProfileJsonFor(String? userId,
    {required String syncProvider}) {
  if (userId == minhAnhAccount.userId) {
    return mockHealthProfileJson(syncProvider: syncProvider);
  }
  if (userId != tamChefAccount.userId) return null;
  return {
    'heightCm': 168,
    'weightKg': 63,
    'bmi': 22.3,
    'goal': 'maintain',
    'allergies': <String>[],
    'dietaryRestrictions': <String>[],
    'healthSync': {'provider': 'none', 'status': 'paused'},
  };
}

Map<String, Object?> mockHealthProfileJson({required String syncProvider}) => {
      'heightCm': 172,
      'weightKg': 66,
      'bmi': 22.3,
      'goal': 'lean_muscle',
      'gender': 'Female',
      'birthYear': 1997,
      'activityLevel': 'light',
      'mealPattern': ['breakfast', 'lunch', 'snack_pm', 'dinner'],
      // Legacy shape (plain ids) on purpose: both shapes are read.
      'allergies': ['peanut'],
      'dietaryRestrictions': ['low_sodium'],
      'healthSync': {
        'provider': syncProvider,
        'status': 'synced',
        'lastSyncedAt': DateTime.now()
            .subtract(const Duration(minutes: 4))
            .toUtc()
            .toIso8601String(),
      },
    };
