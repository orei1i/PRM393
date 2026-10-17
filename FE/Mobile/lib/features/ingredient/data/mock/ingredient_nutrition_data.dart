// lib/features/ingredient/data/mock/ingredient_nutrition_data.dart
//
// Mock nutrition DB: 35 common Vietnamese vegan ingredients, per 100 g, in
// the GET /ingredients/{id} wire format (without `recipes`, which the mock
// repository finds in the recipe catalogue). Values are rounded reference
// figures (Bảng thành phần thực phẩm Việt Nam / USDA FoodData Central); a
// figure the source doesn't give is left out, never set to 0.

const ingredientSource =
    'Tham khảo: Bảng thành phần thực phẩm Việt Nam / USDA FoodData Central';

/// FDA daily values used for "%DV".
const Map<String, double> _dailyValue = {
  'Vitamin A': 900, // µg
  'Vitamin C': 90, // mg
  'Vitamin E': 15, // mg
  'Vitamin K': 120, // µg
  'Vitamin B5': 5, // mg
  'Vitamin B6': 1.7, // mg
  'Niacin': 16, // mg
  'Folate': 400, // µg
  'Canxi': 1300, // mg
  'Sắt': 18, // mg
  'Magie': 420, // mg
  'Kali': 4700, // mg
  'Kẽm': 11, // mg
  'Đồng': 0.9, // mg
  'Mangan': 2.3, // mg
  'Phốt pho': 1250, // mg
};

Map<String, Object?> _m(String name, num amount, String unit) {
  final dv = _dailyValue[name];
  return {
    'name': name,
    'amount': amount,
    'unit': unit,
    if (dv != null) 'dvPercent': (amount / dv * 100).round(),
  };
}

Map<String, Object?> _pair(String name, String reason) =>
    {'name': name, 'reason': reason};

Map<String, Object?> _ing(
  String id,
  String name,
  String category, {
  required num kcal,
  num? p,
  num? f,
  num? c,
  num? fi,
  num? su,
  required String alt,
  required num altGrams,
  List<String> aliases = const [],
  List<Map<String, Object?>> micros = const [],
  List<String> goodFor = const [],
  List<String> cautionFor = const [],
  List<Map<String, Object?>> avoid = const [],
  List<String> dishes = const [],
  List<String> allergens = const [],
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'isVegan': true,
      'aliases': aliases,
      'caloriesPer100g': kcal,
      'serving': {'label': '100 g', 'grams': 100},
      'altServing': {'label': alt, 'grams': altGrams},
      'per100g': {
        'calories': kcal,
        if (p != null) 'proteinG': p,
        if (f != null) 'fatG': f,
        if (c != null) 'carbsG': c,
        if (fi != null) 'fiberG': fi,
        if (su != null) 'sugarG': su,
      },
      'micronutrients': micros,
      'goodFor': goodFor,
      'cautionFor': cautionFor,
      'avoidCombining': avoid,
      'suggestedDishes': dishes,
      'allergens': allergens,
      'source': ingredientSource,
    };

const _soyAllergy = 'Người dị ứng đậu nành';
const _gout = 'Người bị gút nên ăn vừa phải (có purin)';
const _anticoagulant =
    'Người đang dùng thuốc chống đông nên hỏi bác sĩ (nhiều vitamin K)';
const _oxalate = 'Ăn rất nhiều cùng lúc có thể giảm hấp thu canxi do oxalat; '
    'ăn lượng vừa phải thì không đáng lo';

/// The nutrition DB rows, in display order.
final List<Map<String, Object?>> mockIngredientRows = [
  _ing('ing_dau_hu', 'Đậu hũ', 'plant_protein',
      kcal: 76,
      p: 8.1,
      f: 4.8,
      c: 1.9,
      fi: 0.3,
      su: 0.6,
      alt: '1 bìa',
      altGrams: 150,
      aliases: [
        'đậu phụ',
        'tàu hũ'
      ],
      micros: [
        _m('Canxi', 350, 'mg'),
        _m('Sắt', 5.4, 'mg'),
        _m('Magie', 30, 'mg')
      ],
      goodFor: [
        'Người ăn chay cần bổ sung đạm',
        'Người muốn giảm cân (ít năng lượng, nhiều đạm)',
        'Người cần thêm canxi',
      ],
      cautionFor: [
        _soyAllergy,
        _gout
      ],
      avoid: [
        _pair('Rau chân vịt', _oxalate)
      ],
      dishes: [
        'Đậu hũ sốt cà chua',
        'Đậu hũ kho nấm',
        'Canh đậu hũ rau cải'
      ],
      allergens: [
        'soy'
      ]),
  _ing('ing_dau_hu_non', 'Đậu hũ non', 'plant_protein',
      kcal: 55,
      p: 4.8,
      f: 2.7,
      c: 2.9,
      fi: 0.1,
      su: 1.3,
      alt: '1 hộp',
      altGrams: 300,
      aliases: [
        'tàu hũ non'
      ],
      micros: [
        _m('Canxi', 31, 'mg'),
        _m('Sắt', 0.8, 'mg'),
        _m('Magie', 29, 'mg')
      ],
      goodFor: [
        'Người lớn tuổi, trẻ nhỏ (mềm, dễ tiêu)',
        'Bữa nhẹ bụng buổi tối',
      ],
      cautionFor: [
        _soyAllergy
      ],
      dishes: [
        'Đậu hũ non chưng nấm',
        'Canh đậu hũ non rong biển'
      ],
      allergens: [
        'soy'
      ]),
  _ing('ing_tempeh', 'Tempeh', 'plant_protein',
      kcal: 192,
      p: 20.3,
      f: 10.8,
      c: 7.6,
      alt: '1 miếng',
      altGrams: 85,
      micros: [
        _m('Magie', 81, 'mg'),
        _m('Sắt', 2.7, 'mg'),
        _m('Phốt pho', 266, 'mg'),
      ],
      goodFor: [
        'Người tập luyện cần nhiều đạm',
        'Hệ tiêu hoá (đậu nành lên men)',
      ],
      cautionFor: [
        _soyAllergy
      ],
      dishes: [
        'Tempeh áp chảo sả ớt',
        'Cơm gạo lứt tempeh'
      ],
      allergens: [
        'soy'
      ]),
  _ing('ing_mi_can', 'Mì căn', 'plant_protein',
      kcal: 121,
      p: 21,
      f: 1.9,
      c: 4.6,
      alt: '1 miếng',
      altGrams: 50,
      aliases: [
        'seitan'
      ],
      micros: [
        _m('Sắt', 2, 'mg')
      ],
      goodFor: [
        'Người cần nhiều đạm, ít béo'
      ],
      cautionFor: [
        'Người không dung nạp gluten hoặc bị bệnh celiac',
      ],
      dishes: [
        'Mì căn kho tiêu',
        'Mì căn xào sả ớt'
      ],
      allergens: [
        'gluten'
      ]),
  _ing('ing_nam_rom', 'Nấm rơm', 'mushroom',
      kcal: 32,
      p: 3.8,
      f: 0.7,
      c: 4.6,
      fi: 2.5,
      alt: '1 chén',
      altGrams: 70,
      micros: [_m('Sắt', 1.4, 'mg'), _m('Kali', 78, 'mg')],
      goodFor: ['Người giảm cân', 'Người cần thêm chất xơ'],
      cautionFor: [_gout, 'Người dị ứng nấm'],
      dishes: ['Nấm rơm kho tiêu', 'Canh chua nấm rơm'],
      allergens: []),
  _ing('ing_nam_dui_ga', 'Nấm đùi gà', 'mushroom',
      kcal: 35,
      p: 3.3,
      f: 0.4,
      c: 6.1,
      fi: 2.3,
      alt: '1 cây',
      altGrams: 50,
      micros: [_m('Kali', 358, 'mg'), _m('Niacin', 3.6, 'mg')],
      goodFor: ['Người giảm cân', 'Thay thịt trong món xào, nướng'],
      cautionFor: [_gout, 'Người dị ứng nấm'],
      dishes: ['Bò lúc lắc chay nấm đùi gà', 'Nấm đùi gà nướng sa tế'],
      allergens: []),
  _ing('ing_nam_huong', 'Nấm hương', 'mushroom',
      kcal: 34,
      p: 2.2,
      f: 0.5,
      c: 6.8,
      fi: 2.5,
      su: 2.4,
      alt: '1 cái',
      altGrams: 15,
      aliases: [
        'nấm đông cô',
        'shiitake'
      ],
      micros: [
        _m('Đồng', 0.14, 'mg'),
        _m('Vitamin B5', 1.5, 'mg'),
        _m('Kali', 304, 'mg'),
      ],
      goodFor: [
        'Tạo vị ngọt tự nhiên cho nước dùng chay'
      ],
      cautionFor: [
        _gout,
        'Người dị ứng nấm'
      ],
      dishes: [
        'Phở chay nấm đông cô',
        'Nấm hương xào cải thìa'
      ],
      allergens: []),
  _ing('ing_ca_chua', 'Cà chua', 'veg',
      kcal: 18,
      p: 0.9,
      f: 0.2,
      c: 3.9,
      fi: 1.2,
      su: 2.6,
      alt: '1 quả',
      altGrams: 123,
      micros: [
        _m('Vitamin C', 13.7, 'mg'),
        _m('Kali', 237, 'mg'),
        _m('Vitamin A', 42, 'µg'),
      ],
      goodFor: [
        'Người cần thêm vitamin C và lycopene',
        'Người giảm cân'
      ],
      cautionFor: [
        'Người bị trào ngược dạ dày (vị chua)'
      ],
      avoid: [
        _pair('Dưa leo',
            'Dân gian cho rằng enzym của dưa leo làm giảm vitamin C; ảnh hưởng nhỏ'),
      ],
      dishes: [
        'Canh cà chua đậu hũ',
        'Đậu hũ sốt cà chua',
        'Bún riêu chay'
      ],
      allergens: []),
  _ing('ing_rau_muong', 'Rau muống', 'leafy',
      kcal: 19,
      p: 2.6,
      f: 0.2,
      c: 3.1,
      fi: 2.1,
      alt: '1 bó',
      altGrams: 300,
      micros: [
        _m('Vitamin A', 315, 'µg'),
        _m('Vitamin C', 55, 'mg'),
        _m('Sắt', 1.7, 'mg'),
      ],
      goodFor: [
        'Người cần thêm chất xơ',
        'Người thiếu vitamin A'
      ],
      cautionFor: [
        _anticoagulant
      ],
      dishes: [
        'Rau muống xào tỏi',
        'Rau muống luộc chấm tương'
      ],
      allergens: []),
  _ing('ing_rau_chan_vit', 'Rau chân vịt', 'leafy',
      kcal: 23,
      p: 2.9,
      f: 0.4,
      c: 3.6,
      fi: 2.2,
      su: 0.4,
      alt: '1 bó',
      altGrams: 250,
      aliases: [
        'cải bó xôi',
        'rau bina'
      ],
      micros: [
        _m('Vitamin K', 483, 'µg'),
        _m('Folate', 194, 'µg'),
        _m('Sắt', 2.7, 'mg'),
      ],
      goodFor: [
        'Phụ nữ mang thai (nhiều folate)',
        'Người thiếu sắt'
      ],
      cautionFor: [
        'Người có tiền sử sỏi thận (nhiều oxalat)',
        _anticoagulant,
      ],
      avoid: [
        _pair('Đậu hũ', _oxalate)
      ],
      dishes: [
        'Canh rau chân vịt nấm',
        'Rau chân vịt xào tỏi'
      ],
      allergens: []),
  _ing('ing_cai_thia', 'Cải thìa', 'leafy',
      kcal: 13,
      p: 1.5,
      f: 0.2,
      c: 2.2,
      fi: 1,
      su: 1.2,
      alt: '1 cây',
      altGrams: 60,
      aliases: [
        'cải chíp',
        'bok choy'
      ],
      micros: [
        _m('Vitamin C', 45, 'mg'),
        _m('Vitamin A', 223, 'µg'),
        _m('Canxi', 105, 'mg'),
      ],
      goodFor: [
        'Người giảm cân',
        'Người cần canxi từ thực vật'
      ],
      cautionFor: [
        _anticoagulant
      ],
      dishes: [
        'Cải thìa xào nấm hương',
        'Canh cải thìa đậu hũ'
      ],
      allergens: []),
  _ing('ing_bong_cai_xanh', 'Bông cải xanh', 'veg',
      kcal: 34,
      p: 2.8,
      f: 0.4,
      c: 6.6,
      fi: 2.6,
      su: 1.7,
      alt: '1 chén',
      altGrams: 90,
      aliases: [
        'súp lơ xanh',
        'bông cải'
      ],
      micros: [
        _m('Vitamin C', 89, 'mg'),
        _m('Vitamin K', 102, 'µg'),
        _m('Folate', 63, 'µg'),
      ],
      goodFor: [
        'Người cần tăng sức đề kháng (nhiều vitamin C)',
        'Người giảm cân'
      ],
      cautionFor: [
        'Người hay đầy hơi nên nấu chín kỹ',
        _anticoagulant
      ],
      dishes: [
        'Đậu hũ xào bông cải cà rốt',
        'Bông cải luộc chấm tương'
      ],
      allergens: []),
  _ing('ing_ca_rot', 'Cà rốt', 'veg',
      kcal: 41,
      p: 0.9,
      f: 0.2,
      c: 9.6,
      fi: 2.8,
      su: 4.7,
      alt: '1 củ',
      altGrams: 70,
      micros: [
        _m('Vitamin A', 835, 'µg'),
        _m('Kali', 320, 'mg'),
        _m('Vitamin K', 13, 'µg'),
      ],
      goodFor: [
        'Mắt và da (nhiều beta-caroten)',
        'Trẻ nhỏ ăn dặm'
      ],
      cautionFor: [
        'Ăn quá nhiều lâu ngày có thể làm da hơi vàng'
      ],
      dishes: [
        'Cà rốt xào nấm',
        'Canh cà rốt khoai tây'
      ],
      allergens: []),
  _ing('ing_bi_do', 'Bí đỏ', 'veg',
      kcal: 26,
      p: 1,
      f: 0.1,
      c: 6.5,
      fi: 0.5,
      su: 2.8,
      alt: '1 miếng',
      altGrams: 150,
      aliases: [
        'bí ngô'
      ],
      micros: [
        _m('Vitamin A', 426, 'µg'),
        _m('Vitamin C', 9, 'mg'),
        _m('Kali', 340, 'mg'),
      ],
      goodFor: [
        'Người giảm cân',
        'Trẻ nhỏ ăn dặm'
      ],
      cautionFor: [
        'Người tiểu đường nên ăn lượng vừa phải'
      ],
      dishes: [
        'Súp bí đỏ đậu lăng',
        'Canh bí đỏ đậu phộng'
      ],
      allergens: []),
  _ing('ing_khoai_lang', 'Khoai lang', 'veg',
      kcal: 86,
      p: 1.6,
      f: 0.1,
      c: 20.1,
      fi: 3,
      su: 4.2,
      alt: '1 củ',
      altGrams: 130,
      micros: [
        _m('Vitamin A', 709, 'µg'),
        _m('Kali', 337, 'mg'),
        _m('Mangan', 0.26, 'mg'),
      ],
      goodFor: [
        'Bữa sáng no lâu',
        'Người cần thêm chất xơ'
      ],
      cautionFor: [
        'Người tiểu đường nên ăn lượng vừa phải'
      ],
      dishes: [
        'Khoai lang luộc',
        'Đậu lăng hầm khoai lang'
      ],
      allergens: []),
  _ing('ing_gao_lut', 'Gạo lứt', 'grain',
      kcal: 123,
      p: 2.7,
      f: 1,
      c: 25.6,
      fi: 1.6,
      su: 0.2,
      alt: '1 chén cơm',
      altGrams: 150,
      aliases: [
        'cơm gạo lứt'
      ],
      micros: [
        _m('Mangan', 0.9, 'mg'),
        _m('Magie', 39, 'mg'),
        _m('Phốt pho', 77, 'mg'),
      ],
      goodFor: [
        'Người cần kiểm soát đường huyết (thay gạo trắng)',
        'Người giảm cân'
      ],
      cautionFor: [
        'Người tiêu hoá kém nên ngâm gạo trước khi nấu'
      ],
      dishes: [
        'Cơm gạo lứt muối mè',
        'Cháo gạo lứt đậu đỏ'
      ],
      allergens: []),
  _ing('ing_yen_mach', 'Yến mạch', 'grain',
      kcal: 389,
      p: 16.9,
      f: 6.9,
      c: 66.3,
      fi: 10.6,
      alt: '1 chén',
      altGrams: 40,
      aliases: [
        'yến mạch cán',
        'oats'
      ],
      micros: [
        _m('Mangan', 4.9, 'mg'),
        _m('Sắt', 4.7, 'mg'),
        _m('Magie', 177, 'mg'),
      ],
      goodFor: [
        'Bữa sáng no lâu',
        'Người cần giảm cholesterol (beta-glucan)'
      ],
      cautionFor: [
        'Người không dung nạp gluten nên chọn loại ghi "không gluten"',
      ],
      dishes: [
        'Yến mạch ngâm hạt chia',
        'Pancake chuối yến mạch'
      ],
      allergens: []),
  _ing('ing_dau_xanh', 'Đậu xanh', 'plant_protein',
      kcal: 347,
      p: 23.9,
      f: 1.2,
      c: 62.6,
      fi: 16.3,
      su: 6.6,
      alt: '1 chén',
      altGrams: 50,
      aliases: [
        'đậu xanh cà vỏ'
      ],
      micros: [
        _m('Folate', 625, 'µg'),
        _m('Sắt', 6.7, 'mg'),
        _m('Magie', 189, 'mg'),
      ],
      goodFor: [
        'Người cần thêm đạm và chất xơ',
        'Ngày nắng nóng (chè, cháo)'
      ],
      cautionFor: [
        'Người hay đầy bụng nên ngâm kỹ, nấu chín mềm'
      ],
      dishes: [
        'Xôi đậu xanh',
        'Chè đậu xanh'
      ],
      allergens: []),
  _ing('ing_dau_den', 'Đậu đen', 'plant_protein',
      kcal: 341,
      p: 21.6,
      f: 1.4,
      c: 62.4,
      fi: 15.5,
      su: 2.1,
      alt: '1 chén',
      altGrams: 50,
      micros: [
        _m('Folate', 444, 'µg'),
        _m('Sắt', 5, 'mg'),
        _m('Magie', 171, 'mg'),
      ],
      goodFor: [
        'Người cần thêm đạm và chất xơ',
        'Người thiếu sắt'
      ],
      cautionFor: [
        'Người hay đầy bụng nên ngâm kỹ, nấu chín mềm'
      ],
      dishes: [
        'Chè đậu đen',
        'Cơm gạo lứt đậu đen'
      ],
      allergens: []),
  _ing('ing_dau_ga', 'Đậu gà', 'plant_protein',
      kcal: 164,
      p: 8.9,
      f: 2.6,
      c: 27.4,
      fi: 7.6,
      su: 4.8,
      alt: '1 chén',
      altGrams: 160,
      aliases: [
        'chickpea'
      ],
      micros: [
        _m('Folate', 172, 'µg'),
        _m('Sắt', 2.9, 'mg'),
        _m('Mangan', 1, 'mg'),
      ],
      goodFor: [
        'Người ăn chay cần đạm',
        'Người cần no lâu'
      ],
      cautionFor: [
        'Người hay đầy bụng nên ăn lượng nhỏ'
      ],
      dishes: [
        'Cà ri đậu gà nước cốt dừa',
        'Salad đậu gà'
      ],
      allergens: []),
  _ing('ing_dau_phong', 'Đậu phộng', 'nut_seed',
      kcal: 567,
      p: 25.8,
      f: 49.2,
      c: 16.1,
      fi: 8.5,
      su: 4.7,
      alt: '1 nắm',
      altGrams: 30,
      aliases: [
        'lạc'
      ],
      micros: [
        _m('Vitamin E', 8.3, 'mg'),
        _m('Niacin', 12.1, 'mg'),
        _m('Magie', 168, 'mg'),
      ],
      goodFor: [
        'Người cần tăng cân lành mạnh',
        'Bữa phụ giàu đạm'
      ],
      cautionFor: [
        'Người dị ứng đậu phộng (có thể gây phản ứng nặng)',
        'Người cần kiểm soát cân nặng nên ăn lượng nhỏ',
      ],
      dishes: [
        'Xôi đậu phộng',
        'Gỏi cuốn chấm tương đậu phộng'
      ],
      allergens: [
        'peanut'
      ]),
  _ing('ing_hat_dieu', 'Hạt điều', 'nut_seed',
      kcal: 553,
      p: 18.2,
      f: 43.8,
      c: 30.2,
      fi: 3.3,
      su: 5.9,
      alt: '1 nắm',
      altGrams: 28,
      micros: [
        _m('Đồng', 2.2, 'mg'),
        _m('Magie', 292, 'mg'),
        _m('Kẽm', 5.8, 'mg'),
      ],
      goodFor: [
        'Bữa phụ giàu năng lượng',
        'Làm sữa hạt, sốt kem chay'
      ],
      cautionFor: [
        'Người dị ứng hạt cây',
        'Người cần kiểm soát cân nặng nên ăn lượng nhỏ',
      ],
      dishes: [
        'Sữa hạt điều',
        'Cháo yến mạch hạt điều'
      ],
      allergens: [
        'tree_nut'
      ]),
  _ing('ing_me', 'Mè', 'nut_seed',
      kcal: 573,
      p: 17.7,
      f: 49.7,
      c: 23.4,
      fi: 11.8,
      su: 0.3,
      alt: '1 muỗng canh',
      altGrams: 9,
      aliases: [
        'vừng',
        'mè đen',
        'mè trắng'
      ],
      micros: [
        _m('Canxi', 975, 'mg'),
        _m('Sắt', 14.6, 'mg'),
        _m('Magie', 351, 'mg'),
      ],
      goodFor: [
        'Người ăn chay cần canxi và sắt'
      ],
      cautionFor: [
        'Người dị ứng mè'
      ],
      dishes: [
        'Muối mè',
        'Xôi mè đen'
      ],
      allergens: [
        'sesame'
      ]),
  _ing('ing_sua_dau_nanh', 'Sữa đậu nành', 'plant_milk',
      kcal: 54,
      p: 3.3,
      f: 1.8,
      c: 6.3,
      fi: 0.6,
      su: 3.9,
      alt: '1 ly',
      altGrams: 250,
      micros: [
        _m('Canxi', 25, 'mg'),
        _m('Kali', 118, 'mg')
      ],
      goodFor: [
        'Thay sữa bò cho người ăn thuần chay'
      ],
      cautionFor: [
        _soyAllergy,
        'Nên chọn loại ít đường'
      ],
      avoid: [
        _pair('Đường đỏ',
            'Dân gian cho rằng làm kết tủa đạm; bằng chứng khoa học còn hạn chế'),
      ],
      dishes: [
        'Sữa đậu nành lá dứa',
        'Sinh tố chuối sữa đậu nành'
      ],
      allergens: [
        'soy'
      ]),
  _ing('ing_rong_bien', 'Rong biển', 'veg',
      kcal: 45,
      p: 3,
      f: 0.6,
      c: 9.1,
      fi: 0.5,
      su: 0.7,
      alt: '1 nắm',
      altGrams: 20,
      aliases: [
        'rong biển wakame',
        'wakame'
      ],
      micros: [
        _m('Folate', 196, 'µg'),
        _m('Magie', 107, 'mg'),
        _m('Mangan', 1.4, 'mg'),
      ],
      goodFor: [
        'Món canh thanh mát, ít năng lượng'
      ],
      cautionFor: [
        'Người bệnh tuyến giáp nên hỏi bác sĩ (nhiều i-ốt)'
      ],
      dishes: [
        'Canh rong biển đậu hũ non',
        'Salad rong biển'
      ],
      allergens: []),
  _ing('ing_chuoi', 'Chuối', 'fruit',
      kcal: 89,
      p: 1.1,
      f: 0.3,
      c: 22.8,
      fi: 2.6,
      su: 12.2,
      alt: '1 quả',
      altGrams: 118,
      micros: [
        _m('Kali', 358, 'mg'),
        _m('Vitamin B6', 0.37, 'mg'),
        _m('Vitamin C', 8.7, 'mg'),
      ],
      goodFor: [
        'Bữa phụ trước khi tập',
        'Người cần bổ sung kali'
      ],
      cautionFor: [
        'Người bệnh thận cần hạn chế kali nên hỏi bác sĩ'
      ],
      dishes: [
        'Pancake chuối yến mạch',
        'Sinh tố chuối'
      ],
      allergens: []),
  _ing('ing_qua_bo', 'Bơ', 'fruit',
      kcal: 160,
      p: 2,
      f: 14.7,
      c: 8.5,
      fi: 6.7,
      su: 0.7,
      alt: '1 quả',
      altGrams: 200,
      aliases: [
        'quả bơ',
        'trái bơ'
      ],
      micros: [
        _m('Kali', 485, 'mg'),
        _m('Folate', 81, 'µg'),
        _m('Vitamin K', 21, 'µg'),
      ],
      goodFor: [
        'Chất béo tốt cho tim mạch',
        'Người cần tăng cân lành mạnh'
      ],
      cautionFor: [
        'Người cần kiểm soát cân nặng nên ăn lượng vừa phải'
      ],
      dishes: [
        'Sinh tố bơ sữa hạt',
        'Salad bơ đậu gà'
      ],
      allergens: []),
  _ing('ing_chanh', 'Chanh', 'fruit',
      kcal: 30,
      p: 0.7,
      f: 0.2,
      c: 10.5,
      fi: 2.8,
      su: 1.7,
      alt: '1 quả',
      altGrams: 67,
      micros: [_m('Vitamin C', 29, 'mg')],
      goodFor: ['Tăng vị chua thay nước mắm, giảm muối'],
      cautionFor: ['Người đau dạ dày, trào ngược nên dùng ít'],
      dishes: ['Nước chanh sả', 'Gỏi chay trộn chanh'],
      allergens: []),
  _ing('ing_gung', 'Gừng', 'spice',
      kcal: 80,
      p: 1.8,
      f: 0.8,
      c: 17.8,
      fi: 2,
      su: 1.7,
      alt: '1 lát',
      altGrams: 5,
      micros: [
        _m('Kali', 415, 'mg'),
        _m('Magie', 43, 'mg')
      ],
      goodFor: [
        'Làm ấm bụng, giảm buồn nôn nhẹ'
      ],
      cautionFor: [
        'Người đang dùng thuốc chống đông nên dùng lượng vừa phải',
      ],
      dishes: [
        'Trà gừng',
        'Đậu hũ kho gừng'
      ],
      allergens: []),
  _ing('ing_toi', 'Tỏi', 'spice',
      kcal: 149,
      p: 6.4,
      f: 0.5,
      c: 33.1,
      fi: 2.1,
      su: 1,
      alt: '1 tép',
      altGrams: 3,
      micros: [
        _m('Vitamin C', 31, 'mg'),
        _m('Mangan', 1.7, 'mg'),
        _m('Vitamin B6', 1.2, 'mg'),
      ],
      goodFor: [
        'Tạo hương vị, giảm muối trong món chay'
      ],
      cautionFor: [
        'Người đau dạ dày nên tránh ăn tỏi sống lúc đói'
      ],
      dishes: [
        'Rau muống xào tỏi',
        'Nấm xào tỏi'
      ],
      allergens: []),
  _ing('ing_hanh_tay', 'Hành tây', 'veg',
      kcal: 40,
      p: 1.1,
      f: 0.1,
      c: 9.3,
      fi: 1.7,
      su: 4.2,
      alt: '1 củ',
      altGrams: 110,
      micros: [
        _m('Vitamin C', 7.4, 'mg'),
        _m('Kali', 146, 'mg'),
      ],
      goodFor: [
        'Tạo vị ngọt cho món xào, canh'
      ],
      cautionFor: [
        'Người hội chứng ruột kích thích có thể bị đầy hơi'
      ],
      dishes: [
        'Đậu hũ xào hành tây',
        'Súp hành tây'
      ],
      allergens: []),
  _ing('ing_ot_chuong', 'Ớt chuông', 'veg',
      kcal: 31,
      p: 1,
      f: 0.3,
      c: 6,
      fi: 2.1,
      su: 4.2,
      alt: '1 quả',
      altGrams: 120,
      aliases: [
        'ớt Đà Lạt'
      ],
      micros: [
        _m('Vitamin C', 128, 'mg'),
        _m('Vitamin A', 157, 'µg'),
        _m('Vitamin B6', 0.29, 'mg'),
      ],
      goodFor: [
        'Người cần thêm vitamin C',
        'Người giảm cân'
      ],
      cautionFor: [
        'Người hay đầy hơi nên nấu chín'
      ],
      dishes: [
        'Ớt chuông xào nấm',
        'Salad ớt chuông'
      ],
      allergens: []),
  _ing('ing_dau_bap', 'Đậu bắp', 'veg',
      kcal: 33,
      p: 1.9,
      f: 0.2,
      c: 7.5,
      fi: 3.2,
      su: 1.5,
      alt: '1 trái',
      altGrams: 12,
      micros: [
        _m('Vitamin K', 31, 'µg'),
        _m('Vitamin C', 23, 'mg'),
        _m('Magie', 57, 'mg'),
      ],
      goodFor: [
        'Người cần thêm chất xơ hoà tan',
        'Người giảm cân'
      ],
      cautionFor: [
        'Người có tiền sử sỏi thận nên ăn lượng vừa phải'
      ],
      dishes: [
        'Đậu bắp luộc chấm tương',
        'Canh chua đậu bắp'
      ],
      allergens: []),
  _ing('ing_bap', 'Bắp', 'grain',
      kcal: 86,
      p: 3.3,
      f: 1.4,
      c: 18.7,
      fi: 2,
      su: 6.3,
      alt: '1 bắp',
      altGrams: 90,
      aliases: [
        'ngô',
        'bắp ngô',
        'bắp Mỹ'
      ],
      micros: [
        _m('Vitamin C', 6.8, 'mg'),
        _m('Magie', 37, 'mg'),
        _m('Kali', 270, 'mg'),
      ],
      goodFor: [
        'Bữa phụ no lâu',
        'Nấu nước dùng ngọt tự nhiên'
      ],
      cautionFor: [
        'Người tiểu đường nên ăn lượng vừa phải'
      ],
      dishes: [
        'Bắp luộc',
        'Súp bắp nấm'
      ],
      allergens: []),
  _ing('ing_khoai_tay', 'Khoai tây', 'veg',
      kcal: 77,
      p: 2,
      f: 0.1,
      c: 17.5,
      fi: 2.1,
      su: 0.8,
      alt: '1 củ',
      altGrams: 150,
      micros: [
        _m('Vitamin C', 19.7, 'mg'),
        _m('Kali', 425, 'mg'),
        _m('Vitamin B6', 0.3, 'mg'),
      ],
      goodFor: [
        'Nguồn tinh bột dễ chế biến'
      ],
      cautionFor: [
        'Không ăn phần vỏ xanh hoặc đã mọc mầm',
        'Người tiểu đường nên ăn lượng vừa phải',
      ],
      dishes: [
        'Khoai tây xào nấm',
        'Canh khoai tây cà rốt'
      ],
      allergens: []),
];
