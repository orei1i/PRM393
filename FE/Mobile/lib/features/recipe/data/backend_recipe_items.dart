// lib/features/recipe/data/backend_recipe_items.dart
//
// Goes away when the BE ships `ingredientItems` (shape in the README, "Chạy với
// BE thật"). The BE stores `ingredients: string[]`, so this table gives each of
// its 29 seed recipes what the recipe page needs to scale and swap: servings,
// quantity, unit, role, signature and optional flags, allergens, substitutes.
// Keyed by normalized recipe name, with exactly the rows the BE lists.
//
// Quantities are reference amounts: chosen with the per-100 g figures below (GET
// /ingredients, plus common food-table values for what it doesn't list) so that
// the energy they add up to is close to the recipe's BE `calories`. The BE's
// figure is still the one shown; only a change is recalculated from these ("≈").
// `Gạo lứt` / `Gạo trắng` are per 100 g of cooked rice in GET /ingredients, hence
// the unit "g cơm chín".
//
// Exported for the BE seed with [backendRecipeItemsJson].
import '../../../core/utils/text_search.dart';
import 'models/recipe_detail_model.dart';

class _Food {
  const _Food(
      this.kcal, this.protein, this.carbs, this.fat, this.fiber, this.group,
      [this.allergens = const []]);

  /// Per 100 g.
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  /// The role of a row or substitute that doesn't say otherwise.
  final String group;
  final List<String> allergens;
}

const _dam = 'Đạm';
const _nam = 'Nấm';
const _tinhBot = 'Tinh bột';
const _soi = 'Sợi';
const _voCuon = 'Vỏ cuốn';
const _rauCu = 'Rau củ';
const _rauLa = 'Rau lá';
const _rauThom = 'Rau thơm';
const _traiCay = 'Trái cây';
const _hat = 'Hạt';
const _sua = 'Sữa';
const _giaVi = 'Gia vị';
const _nuoc = 'Nước';

const _foods = <String, _Food>{
  // GET /ingredients.
  'Đậu hũ': _Food(76, 8.1, 1.9, 4.8, 0.3, _dam, ['soy']),
  'Đậu hũ chiên': _Food(132, 10.5, 3.2, 8.5, 0.4, _dam, ['soy']),
  'Đậu hũ non': _Food(55, 5, 1.5, 3, 0.2, _dam, ['soy']),
  'Đậu hũ ky': _Food(480, 49.5, 18, 22, 3, _dam, ['soy']),
  'Tempeh': _Food(192, 20.3, 7.6, 10.8, 4.5, _dam, ['soy']),
  'Sữa đậu nành': _Food(54, 3.3, 6, 1.8, 0.5, _sua, ['soy']),
  'Đậu đen': _Food(341, 21.6, 62.4, 1.4, 15.2, _dam),
  'Đậu xanh': _Food(328, 23.4, 59, 1.2, 16.3, _dam),
  'Đậu đỏ': _Food(329, 21, 61.2, 1, 12.7, _dam),
  'Đậu gà': _Food(364, 19.3, 60.7, 6, 17.4, _dam),
  'Đậu lăng đỏ': _Food(358, 24.6, 63.4, 1.1, 10.8, _dam),
  'Mì căn': _Food(370, 75.2, 13.8, 1.9, 0.6, _dam, ['gluten']),
  'Nấm rơm': _Food(32, 3.4, 4.2, 0.3, 1.5, _nam),
  'Nấm đùi gà': _Food(35, 3.1, 5.5, 0.4, 2.3, _nam),
  'Nấm đông cô': _Food(34, 2.2, 6.8, 0.5, 2.5, _nam),
  'Nấm kim châm': _Food(37, 2.7, 7.8, 0.3, 2.7, _nam),
  'Nấm bào ngư': _Food(33, 3.3, 6.1, 0.4, 2.3, _nam),
  'Nấm mộc nhĩ': _Food(25, 0.5, 7, 0.1, 5.1, _nam),
  'Gạo lứt': _Food(111, 2.6, 23, 0.9, 1.8, _tinhBot),
  'Gạo trắng': _Food(130, 2.7, 28.2, 0.3, 0.4, _tinhBot),
  'Yến mạch': _Food(389, 16.9, 66.3, 6.9, 10.6, _tinhBot, ['gluten']),
  'Hạt diêm mạch': _Food(120, 4.4, 21.3, 1.9, 2.8, _tinhBot),
  'Bún tươi': _Food(110, 1.7, 25.7, 0.1, 0.3, _soi),
  'Phở tươi': _Food(120, 2, 27.5, 0.2, 0.4, _soi),
  'Khoai lang': _Food(86, 1.6, 20.1, 0.1, 3, _tinhBot),
  'Khoai tây': _Food(77, 2, 17.5, 0.1, 2.2, _tinhBot),
  'Bắp ngọt': _Food(86, 3.3, 18.7, 1.4, 2, _tinhBot),
  'Bông cải xanh': _Food(34, 2.8, 6.6, 0.4, 2.6, _rauCu),
  'Bông cải trắng': _Food(25, 1.9, 5, 0.3, 2, _rauCu),
  'Cà rốt': _Food(41, 0.9, 9.6, 0.2, 2.8, _rauCu),
  'Cải ngọt': _Food(18, 1.5, 2.8, 0.2, 1.2, _rauLa),
  'Cải thìa': _Food(13, 1.5, 2.2, 0.2, 1, _rauLa),
  'Rau muống': _Food(19, 3, 2.1, 0.4, 1, _rauLa),
  'Rau dền': _Food(23, 2.5, 4, 0.3, 1.3, _rauLa),
  'Cải bó xôi': _Food(23, 2.9, 3.6, 0.4, 2.2, _rauLa),
  'Cà chua': _Food(18, 0.9, 3.9, 0.2, 1.2, _rauCu),
  'Dưa leo': _Food(15, 0.7, 3.6, 0.1, 0.5, _rauCu),
  'Bí đỏ': _Food(26, 1, 6.5, 0.1, 0.5, _rauCu),
  'Củ cải trắng': _Food(16, 0.7, 3.4, 0.1, 1.6, _rauCu),
  'Mướp hương': _Food(16, 0.9, 3, 0.1, 0.5, _rauCu),
  'Đậu phộng': _Food(567, 25.8, 16.1, 49.2, 8.5, _hat, ['peanut']),
  'Hạt điều': _Food(553, 18.2, 30.2, 43.8, 3.3, _hat, ['tree_nut']),
  'Hạt hạnh nhân': _Food(579, 21.2, 21.6, 49.9, 12.5, _hat, ['tree_nut']),
  'Hạt chia': _Food(486, 16.5, 42.1, 30.7, 34.4, _hat),
  'Mè đen': _Food(573, 17.7, 23.4, 49.7, 11.8, _hat, ['sesame']),
  'Mè trắng': _Food(573, 17.7, 23.4, 49.7, 11.8, _hat, ['sesame']),
  'Hạt sen': _Food(350, 17.9, 64.9, 2, 7.9, _hat),
  'Chuối': _Food(89, 1.1, 22.8, 0.3, 2.6, _traiCay),
  'Bơ': _Food(160, 2, 8.5, 14.7, 6.7, _traiCay),
  'Táo': _Food(52, 0.3, 13.8, 0.2, 2.4, _traiCay),
  // Not in GET /ingredients: common food-table values.
  'Việt quất': _Food(57, 0.7, 14.5, 0.3, 2.4, _traiCay),
  'Dâu tây': _Food(32, 0.7, 7.7, 0.3, 2, _traiCay),
  'Xoài': _Food(60, 0.8, 15, 0.4, 1.6, _traiCay),
  'Bánh mì': _Food(265, 9, 49, 3.2, 2.7, _tinhBot, ['gluten']),
  'Bánh gạo không gluten': _Food(250, 4, 50, 3, 2, _tinhBot),
  'Gạo nếp': _Food(370, 6.8, 81.7, 0.6, 2.8, _tinhBot),
  'Nếp cẩm': _Food(350, 8, 75, 1.5, 3, _tinhBot),
  'Khoai môn': _Food(112, 1.5, 26.5, 0.2, 4.1, _tinhBot),
  'Bún gạo lứt': _Food(110, 2.4, 23, 0.5, 1.8, _soi),
  'Bánh tráng': _Food(334, 5.9, 78, 0.5, 1.6, _voCuon),
  'Bánh tráng gạo lứt': _Food(330, 6.5, 74, 1.2, 3, _voCuon),
  'Sữa dừa': _Food(31, 0.2, 2.9, 2.1, 0, _sua),
  'Sữa yến mạch': _Food(47, 1, 7.6, 1.5, 0.8, _sua, ['gluten']),
  'Nước cốt dừa': _Food(197, 2, 2.8, 21, 0, _sua),
  'Nước ấm': _Food(0, 0, 0, 0, 0, _nuoc),
  'Hạt bí': _Food(559, 30, 10.7, 49, 6, _hat),
  'Hạt lanh': _Food(534, 18.3, 28.9, 42.2, 27.3, _hat),
  'Hạt hướng dương': _Food(584, 20.8, 20, 51.5, 8.6, _hat),
  'Sả': _Food(99, 1.8, 25, 0.5, 0, _giaVi),
  'Ớt': _Food(40, 1.9, 8.8, 0.4, 1.5, _giaVi),
  'Tỏi': _Food(149, 6.4, 33, 0.5, 2.1, _giaVi),
  'Gừng': _Food(80, 1.8, 18, 0.8, 2, _giaVi),
  'Hành tím': _Food(72, 2.5, 16.8, 0.1, 3.2, _giaVi),
  'Tiêu': _Food(251, 10.4, 63.9, 3.3, 25.3, _giaVi),
  'Tiêu đen': _Food(251, 10.4, 63.9, 3.3, 25.3, _giaVi),
  'Tiêu xanh': _Food(70, 2, 14, 1, 5, _giaVi),
  'Bột cà ri': _Food(325, 14, 56, 14, 53, _giaVi),
  'Bột nghệ': _Food(312, 9.7, 67, 3.2, 22.7, _giaVi),
  'Mật mía': _Food(290, 0, 75, 0.1, 0, _giaVi),
  'Đường thốt nốt': _Food(375, 0.5, 90, 0.5, 0, _giaVi),
  'Đường phèn': _Food(387, 0, 100, 0, 0, _giaVi),
  'Nước tương': _Food(57, 8.1, 4.9, 0.6, 0.8, _giaVi, ['soy']),
  'Dầu hào chay': _Food(110, 1.5, 25, 0.2, 0.3, _giaVi, ['soy']),
  'Hạt nêm nấm chay': _Food(200, 15, 30, 1, 1, _giaVi),
  'Lá chanh': _Food(30, 1, 7, 0.3, 4, _giaVi),
  'Rau mùi': _Food(23, 2.1, 3.7, 0.5, 2.8, _rauThom),
  'Ngò gai': _Food(31, 3, 6, 0.6, 3, _rauThom),
  'Hành lá': _Food(32, 1.8, 7.3, 0.2, 2.6, _rauThom),
  'Hành boa-rô': _Food(61, 1.5, 14.2, 0.3, 1.8, _rauThom),
  'Rau thơm': _Food(30, 2.5, 5, 0.5, 3, _rauThom),
  'Rau sống': _Food(20, 1.5, 3.5, 0.2, 1.5, _rauLa),
  'Xà lách': _Food(15, 1.4, 2.9, 0.2, 1.3, _rauLa),
  'Rong biển': _Food(45, 3, 9, 0.6, 0.5, _rauLa),
  'Bạc hà': _Food(14, 0.5, 3, 0.1, 1, _rauCu),
  'Đậu bắp': _Food(33, 1.9, 7.5, 0.2, 3.2, _rauCu),
  'Giá đỗ': _Food(30, 3, 5.9, 0.2, 1.8, _rauCu),
  'Bí ngòi': _Food(17, 1.2, 3.1, 0.3, 1, _rauCu),
};

const _comChin = 'g cơm chín';

class _Sub {
  const _Sub(this.name, this.quantity, this.unit, this.note,
      {this.grams, this.food, this.role});

  final String name;
  final double quantity;
  final String unit;
  final String note;

  /// For a unit that doesn't weigh by itself ("1 ổ").
  final double? grams;

  /// The row of [_foods] when it isn't [name] ("Nấm rơm băm nhuyễn").
  final String? food;

  /// When it isn't the food's group.
  final String? role;
}

class _Row {
  const _Row(this.name, this.quantity, this.unit,
      {this.grams,
      this.role,
      this.signature = false,
      this.optional = false,
      this.subs = const []});

  final String name;
  final double quantity;
  final String unit;
  final double? grams;
  final String? role;
  final bool signature;
  final bool optional;
  final List<_Sub> subs;
}

class _Dish {
  const _Dish(this.name, this.servings, this.rows);

  final String name;

  /// The servings the quantities of [rows] are for.
  final int servings;
  final List<_Row> rows;
}

const _subGaoLut = [
  _Sub('Gạo trắng', 500, _comChin, 'Mềm, dễ ăn hơn'),
  _Sub('Hạt diêm mạch', 500, 'g', 'Nhiều đạm hơn'),
];
const _subSuaDauNanh = [
  _Sub('Sữa dừa', 200, 'ml', 'Không chứa đậu nành'),
  _Sub('Sữa yến mạch', 200, 'ml', 'Ngọt nhẹ, sánh hơn'),
];
const _subNuocTuong = [
  _Sub('Hạt nêm nấm chay', 1, 'muỗng cà phê', 'Không chứa đậu nành', grams: 5),
];
const _subBongCai = [
  _Sub('Bông cải trắng', 200, 'g', 'Vị nhẹ hơn'),
  _Sub('Bí ngòi', 200, 'g', 'Mềm, ngọt nhẹ'),
];
const _subCaRot = [_Sub('Bí đỏ', 100, 'g', 'Ngọt, bùi hơn')];
const _subHatChia = [_Sub('Hạt lanh', 15, 'g', 'Bùi, cũng nhiều chất xơ')];

const _dishes = <_Dish>[
  // Bữa sáng.
  _Dish('Yến mạch ngâm hạt chia & việt quất', 1, [
    _Row('Yến mạch', 55, 'g', signature: true, subs: [
      _Sub('Hạt diêm mạch', 180, 'g', 'Không chứa gluten'),
    ]),
    _Row('Hạt chia', 15, 'g', signature: true, subs: _subHatChia),
    _Row('Sữa đậu nành', 200, 'ml', subs: _subSuaDauNanh),
    _Row('Việt quất', 50, 'g', subs: [
      _Sub('Dâu tây', 60, 'g', 'Chua ngọt, dễ mua'),
      _Sub('Chuối', 60, 'g', 'Ngọt, no lâu hơn'),
    ]),
  ]),
  _Dish('Bánh mì đậu hũ sả ớt', 1, [
    _Row('Đậu hũ', 150, 'g', signature: true, subs: [
      _Sub('Tempeh', 90, 'g', 'Chắc, nhiều đạm hơn'),
      _Sub('Nấm đùi gà', 180, 'g', 'Không chứa đậu nành', role: _dam),
    ]),
    _Row('Bánh mì', 1, 'ổ', grams: 120, signature: true, subs: [
      _Sub('Bánh gạo không gluten', 1, 'ổ', 'Không chứa gluten', grams: 110),
    ]),
    _Row('Sả', 1, 'cây', grams: 10),
    _Row('Ớt', 1, 'quả', grams: 5, optional: true),
    _Row('Dưa leo', 50, 'g', optional: true, subs: [
      _Sub('Xà lách', 30, 'g', 'Giòn, mát'),
    ]),
    _Row('Rau mùi', 10, 'g', optional: true, subs: [
      _Sub('Hành lá', 10, 'g', 'Nếu không ăn được rau mùi'),
    ]),
  ]),
  _Dish('Xôi đậu xanh mè đen', 1, [
    _Row('Gạo nếp', 75, 'g', signature: true, subs: [
      _Sub('Nếp cẩm', 80, 'g', 'Dẻo thơm, nhiều chất xơ hơn'),
    ]),
    _Row('Đậu xanh', 30, 'g', signature: true, subs: [
      _Sub('Đậu đen', 30, 'g', 'Bùi, màu đậm'),
    ]),
    _Row('Mè đen', 5, 'g', optional: true, subs: [
      _Sub('Hạt bí', 5, 'g', 'Không chứa mè'),
    ]),
    _Row('Nước cốt dừa', 20, 'ml', optional: true, subs: [
      _Sub('Sữa dừa', 40, 'ml', 'Nhẹ béo hơn'),
    ]),
  ]),
  _Dish('Sinh tố chuối bơ đậu phộng', 1, [
    _Row('Chuối', 150, 'g', signature: true, subs: [
      _Sub('Xoài', 150, 'g', 'Thơm, ít năng lượng hơn'),
    ]),
    _Row('Đậu phộng', 30, 'g', signature: true, subs: [
      _Sub('Hạt hướng dương', 30, 'g', 'Không chứa đậu phộng'),
      _Sub('Hạt điều', 30, 'g', 'Béo, không chứa đậu phộng'),
    ]),
    _Row('Sữa đậu nành', 200, 'ml', subs: _subSuaDauNanh),
    _Row('Hạt chia', 15, 'g', optional: true, subs: _subHatChia),
  ]),
  _Dish('Phở nấm hương chay', 2, [
    _Row('Phở tươi', 450, 'g', signature: true, subs: [
      _Sub('Bún tươi', 450, 'g', 'Sợi tròn, nhẹ hơn'),
      _Sub('Bún gạo lứt', 450, 'g', 'Nhiều chất xơ hơn'),
    ]),
    _Row('Nấm đông cô', 100, 'g', signature: true, subs: [
      _Sub('Nấm rơm', 100, 'g', 'Ngọt nhẹ'),
      _Sub('Nấm bào ngư', 100, 'g', 'Dai, ngọt nhẹ'),
    ]),
    _Row('Đậu hũ', 200, 'g', subs: [
      _Sub('Nấm đùi gà', 250, 'g', 'Không chứa đậu nành', role: _dam),
      _Sub('Tempeh', 100, 'g', 'Chắc, nhiều đạm hơn'),
    ]),
    _Row('Củ cải trắng', 150, 'g', subs: [
      _Sub('Cà rốt', 150, 'g', 'Ngọt nước dùng hơn'),
    ]),
    _Row('Hành boa-rô', 50, 'g', optional: true, subs: [
      _Sub('Hành lá', 30, 'g', 'Dễ mua'),
    ]),
    _Row('Ngò gai', 10, 'g', optional: true, subs: [
      _Sub('Rau mùi', 10, 'g', 'Thơm nhẹ hơn'),
    ]),
  ]),
  _Dish('Bún riêu chay đậu hũ cà chua', 2, [
    _Row('Bún tươi', 420, 'g', subs: [
      _Sub('Bún gạo lứt', 420, 'g', 'Nhiều chất xơ hơn'),
    ]),
    _Row('Đậu hũ', 200, 'g', role: 'Riêu', signature: true, subs: [
      _Sub('Đậu hũ non', 280, 'g', 'Riêu mềm, mịn hơn', role: 'Riêu'),
      _Sub('Nấm rơm băm nhuyễn', 250, 'g', 'Riêu không chứa đậu nành',
          food: 'Nấm rơm', role: 'Riêu'),
    ]),
    _Row('Cà chua', 200, 'g', signature: true, subs: [
      _Sub('Cà chua bi', 200, 'g', 'Ngọt, màu đẹp', food: 'Cà chua'),
    ]),
    _Row('Nấm rơm', 100, 'g', subs: [
      _Sub('Nấm bào ngư', 100, 'g', 'Dai, ngọt nhẹ'),
    ]),
    _Row('Sữa đậu nành', 300, 'ml', subs: [
      _Sub('Sữa dừa', 300, 'ml', 'Không chứa đậu nành'),
    ]),
    _Row('Rau muống', 100, 'g', optional: true, subs: [
      _Sub('Cải ngọt', 100, 'g', 'Ngọt, mềm'),
    ]),
  ]),
  _Dish('Cháo yến mạch nấm rơm hạt sen', 1, [
    _Row('Yến mạch', 50, 'g', signature: true, subs: [
      _Sub('Gạo trắng', 150, _comChin, 'Không chứa gluten'),
    ]),
    _Row('Nấm rơm', 80, 'g', signature: true, subs: [
      _Sub('Nấm bào ngư', 80, 'g', 'Dai, ngọt nhẹ'),
    ]),
    _Row('Hạt sen', 30, 'g', subs: [
      _Sub('Đậu xanh', 30, 'g', 'Bùi, dễ mua'),
    ]),
    _Row('Cà rốt', 50, 'g', optional: true, subs: [
      _Sub('Bí đỏ', 50, 'g', 'Ngọt, bùi hơn'),
    ]),
    _Row('Hành lá', 10, 'g', optional: true),
  ]),
  _Dish('Khoai lang mật nướng hạt chia', 1, [
    _Row('Khoai lang', 300, 'g', signature: true, subs: [
      _Sub('Khoai tây', 300, 'g', 'Bùi, ít ngọt hơn'),
    ]),
    _Row('Hạt chia', 10, 'g', subs: [
      _Sub('Hạt lanh', 10, 'g', 'Bùi, cũng nhiều chất xơ'),
    ]),
    _Row('Mật mía', 5, 'g', optional: true, subs: [
      _Sub('Đường thốt nốt', 5, 'g', 'Thơm, ngọt dịu'),
    ]),
  ]),

  // Bữa trưa.
  _Dish('Cơm gạo lứt đậu hũ kho nấm đông cô', 2, [
    _Row('Gạo lứt', 600, _comChin, signature: true, subs: _subGaoLut),
    _Row('Đậu hũ', 400, 'g', signature: true, subs: [
      _Sub('Tempeh', 200, 'g', 'Chắc, nhiều đạm hơn'),
      _Sub('Nấm đùi gà', 400, 'g', 'Không chứa đậu nành', role: _dam),
    ]),
    _Row('Nấm đông cô', 150, 'g', signature: true, subs: [
      _Sub('Nấm rơm', 150, 'g', 'Ngọt nhẹ'),
    ]),
    _Row('Nước tương', 2, 'muỗng canh', grams: 30, subs: _subNuocTuong),
    _Row('Tiêu đen', 1, 'muỗng cà phê', grams: 2, optional: true),
  ]),
  _Dish('Cơm chiên hạt sen bông cải xanh', 2, [
    _Row('Gạo lứt', 500, _comChin, signature: true, subs: _subGaoLut),
    _Row('Hạt sen', 60, 'g', signature: true, subs: [
      _Sub('Hạt bí', 40, 'g', 'Bùi, nhiều chất béo tốt', role: _hat),
    ]),
    _Row('Bông cải xanh', 200, 'g', signature: true, subs: _subBongCai),
    _Row('Cà rốt', 100, 'g', optional: true, subs: _subCaRot),
    _Row('Bắp ngọt', 100, 'g', optional: true, subs: [
      _Sub('Đậu bắp', 100, 'g', 'Ít tinh bột hơn', role: _tinhBot),
    ]),
  ]),
  _Dish('Bún chả giò chay rau sống', 2, [
    _Row('Bún tươi', 350, 'g', subs: [
      _Sub('Bún gạo lứt', 350, 'g', 'Nhiều chất xơ hơn'),
    ]),
    _Row('Khoai môn', 180, 'g', signature: true, subs: [
      _Sub('Khoai lang', 200, 'g', 'Ngọt, dễ mua'),
    ]),
    _Row('Đậu xanh', 40, 'g', subs: [
      _Sub('Đậu đen', 40, 'g', 'Bùi, màu đậm'),
    ]),
    _Row('Nấm mộc nhĩ', 30, 'g', subs: [
      _Sub('Nấm đông cô', 30, 'g', 'Thơm hơn'),
    ]),
    _Row('Bánh tráng', 7, 'lá', grams: 70, signature: true, subs: [
      _Sub('Bánh tráng gạo lứt', 7, 'lá', 'Nhiều chất xơ hơn', grams: 70),
    ]),
    _Row('Rau sống', 100, 'g', optional: true, subs: [
      _Sub('Xà lách', 100, 'g', 'Giòn, mát'),
    ]),
  ]),
  _Dish('Đậu hũ sốt cà chua & cơm lứt', 2, [
    _Row('Đậu hũ', 400, 'g', signature: true, subs: [
      _Sub('Tempeh', 200, 'g', 'Chắc, nhiều đạm hơn'),
      _Sub('Nấm đùi gà', 400, 'g', 'Không chứa đậu nành', role: _dam),
    ]),
    _Row('Cà chua', 250, 'g', signature: true, subs: [
      _Sub('Cà chua bi', 250, 'g', 'Ngọt, màu đẹp', food: 'Cà chua'),
    ]),
    _Row('Gạo lứt', 480, _comChin, subs: _subGaoLut),
    _Row('Hành boa-rô', 30, 'g', optional: true, subs: [
      _Sub('Hành lá', 30, 'g', 'Dễ mua'),
    ]),
    _Row('Nước tương', 1, 'muỗng canh', grams: 15, subs: _subNuocTuong),
  ]),
  _Dish('Nấm đùi gà kho tiêu xanh & rau luộc', 2, [
    _Row('Nấm đùi gà', 300, 'g', signature: true, subs: [
      _Sub('Nấm bào ngư', 300, 'g', 'Mềm hơn'),
    ]),
    _Row('Gạo lứt', 550, _comChin, subs: _subGaoLut),
    _Row('Tiêu xanh', 10, 'g', signature: true, subs: [
      _Sub('Tiêu đen', 3, 'g', 'Cay nồng, dễ mua'),
    ]),
    _Row('Bông cải xanh', 200, 'g', subs: _subBongCai),
    _Row('Cà rốt', 150, 'g', optional: true, subs: _subCaRot),
  ]),
  _Dish('Canh chua nấm đậu bắp & cơm lứt', 2, [
    _Row('Nấm rơm', 150, 'g', signature: true, subs: [
      _Sub('Nấm bào ngư', 150, 'g', 'Dai, ngọt nhẹ'),
    ]),
    _Row('Đậu hũ', 150, 'g', subs: [
      _Sub('Nấm đùi gà', 150, 'g', 'Không chứa đậu nành', role: _dam),
    ]),
    _Row('Cà chua', 150, 'g', signature: true, subs: [
      _Sub('Cà chua bi', 150, 'g', 'Ngọt, màu đẹp', food: 'Cà chua'),
    ]),
    _Row('Bạc hà', 100, 'g', optional: true, subs: [
      _Sub('Bí ngòi', 100, 'g', 'Nếu không mua được bạc hà'),
    ]),
    _Row('Đậu bắp', 100, 'g', signature: true, subs: [
      _Sub('Bí ngòi', 100, 'g', 'Không nhớt'),
    ]),
    _Row('Giá đỗ', 100, 'g', optional: true),
    _Row('Gạo lứt', 500, _comChin, subs: _subGaoLut),
  ]),
  _Dish('Tempeh áp chảo sốt tương tỏi', 2, [
    _Row('Tempeh', 250, 'g', signature: true, subs: [
      _Sub('Đậu hũ', 500, 'g', 'Mềm, dễ mua'),
      _Sub('Đậu gà', 130, 'g', 'Không chứa đậu nành'),
    ]),
    _Row('Gạo lứt', 450, _comChin, subs: _subGaoLut),
    _Row('Tỏi', 3, 'tép', grams: 10, signature: true),
    _Row('Nước tương', 2, 'muỗng canh', grams: 30, signature: true, subs: [
      _Sub('Hạt nêm nấm chay', 1, 'muỗng cà phê', 'Không chứa đậu nành',
          grams: 5),
    ]),
    _Row('Bông cải xanh', 150, 'g', subs: [
      _Sub('Bông cải trắng', 150, 'g', 'Vị nhẹ hơn'),
    ]),
  ]),
  _Dish('Mì xào giòn rau củ thập cẩm chay', 2, [
    _Row('Mì căn', 210, 'g', signature: true, subs: [
      _Sub('Đậu hũ chiên', 550, 'g', 'Không chứa gluten'),
      _Sub('Tempeh', 380, 'g', 'Không chứa gluten'),
    ]),
    _Row('Bông cải xanh', 150, 'g', subs: [
      _Sub('Bông cải trắng', 150, 'g', 'Vị nhẹ hơn'),
    ]),
    _Row('Cà rốt', 100, 'g', subs: _subCaRot),
    _Row('Nấm bào ngư', 150, 'g', subs: [
      _Sub('Nấm rơm', 150, 'g', 'Ngọt nhẹ'),
    ]),
    _Row('Cải thìa', 200, 'g', optional: true, subs: [
      _Sub('Cải ngọt', 200, 'g', 'Ngọt, mềm'),
    ]),
  ]),
  _Dish('Cà ri đậu gà khoai lang cốt dừa', 2, [
    _Row('Đậu gà', 100, 'g', signature: true, subs: [
      _Sub('Đậu đen', 100, 'g', 'Bùi, nhiều chất xơ'),
      _Sub('Đậu lăng đỏ', 100, 'g', 'Nhanh mềm, sánh hơn'),
    ]),
    _Row('Khoai lang', 250, 'g', signature: true, subs: [
      _Sub('Khoai tây', 250, 'g', 'Bùi, ít ngọt hơn'),
    ]),
    _Row('Nước cốt dừa', 100, 'ml', signature: true, subs: [
      _Sub('Sữa dừa', 200, 'ml', 'Nhẹ béo hơn'),
    ]),
    _Row('Cà rốt', 100, 'g', optional: true, subs: _subCaRot),
    _Row('Bột cà ri', 1, 'muỗng cà phê', grams: 5, signature: true, subs: [
      _Sub('Bột nghệ', 1, 'muỗng cà phê', 'Cay nhẹ hơn', grams: 5),
    ]),
    _Row('Gạo lứt', 220, _comChin, subs: [
      _Sub('Gạo trắng', 190, _comChin, 'Mềm, dễ ăn hơn'),
    ]),
  ]),

  // Bữa tối.
  _Dish('Canh rong biển đậu hũ non & cơm gạo lứt', 2, [
    _Row('Rong biển', 30, 'g', signature: true, subs: [
      _Sub('Cải bó xôi', 100, 'g', 'Nếu không ăn được rong biển'),
    ]),
    _Row('Đậu hũ non', 300, 'g', signature: true, subs: [
      _Sub('Đậu hũ', 220, 'g', 'Chắc hơn, dễ mua'),
      _Sub('Nấm kim châm', 300, 'g', 'Không chứa đậu nành', role: _dam),
    ]),
    _Row('Gạo lứt', 500, _comChin, signature: true, subs: _subGaoLut),
    _Row('Mè trắng', 5, 'g', optional: true, subs: [
      _Sub('Hạt bí', 5, 'g', 'Không chứa mè'),
    ]),
    _Row('Gừng', 5, 'g', optional: true),
  ]),
  _Dish('Nấm bào ngư xào sả ớt & canh rau dền', 2, [
    _Row('Nấm bào ngư', 300, 'g', signature: true, subs: [
      _Sub('Nấm rơm', 300, 'g', 'Ngọt nhẹ'),
      _Sub('Nấm đùi gà', 300, 'g', 'Dai, thơm hơn'),
    ]),
    _Row('Sả', 2, 'cây', grams: 20, signature: true),
    _Row('Ớt', 1, 'quả', grams: 5, optional: true),
    _Row('Rau dền', 200, 'g', signature: true, subs: [
      _Sub('Cải bó xôi', 200, 'g', 'Ngọt, mềm'),
      _Sub('Rau muống', 200, 'g', 'Dễ mua'),
    ]),
    _Row('Gạo lứt', 600, _comChin, subs: _subGaoLut),
  ]),
  _Dish('Mướp hương xào nấm rơm & cơm lứt', 2, [
    _Row('Mướp hương', 300, 'g', signature: true, subs: [
      _Sub('Bí ngòi', 300, 'g', 'Giòn hơn'),
    ]),
    _Row('Nấm rơm', 200, 'g', signature: true, subs: [
      _Sub('Nấm bào ngư', 200, 'g', 'Dai, ngọt nhẹ'),
    ]),
    _Row('Gạo lứt', 600, _comChin, subs: _subGaoLut),
    _Row('Hành lá', 15, 'g', optional: true),
    _Row('Tiêu', 1, 'g', optional: true),
  ]),
  _Dish('Cải thìa sốt nấm đông cô dầu hào chay', 2, [
    _Row('Cải thìa', 300, 'g', signature: true, subs: [
      _Sub('Cải ngọt', 300, 'g', 'Ngọt, mềm'),
    ]),
    _Row('Nấm đông cô', 200, 'g', signature: true, subs: [
      _Sub('Nấm rơm', 200, 'g', 'Ngọt nhẹ'),
    ]),
    _Row('Gạo lứt', 540, _comChin, subs: _subGaoLut),
    _Row('Dầu hào chay', 2, 'muỗng canh', grams: 30, signature: true, subs: [
      _Sub('Hạt nêm nấm chay', 1, 'muỗng cà phê', 'Không chứa đậu nành',
          grams: 5),
    ]),
  ]),
  _Dish('Súp bí đỏ đậu lăng đỏ sánh mịn', 2, [
    _Row('Bí đỏ', 400, 'g', signature: true, subs: [
      _Sub('Khoai lang', 200, 'g', 'Ngọt, sánh hơn', role: _rauCu),
    ]),
    _Row('Đậu lăng đỏ', 100, 'g', signature: true, subs: [
      _Sub('Đậu xanh', 100, 'g', 'Bùi, dễ mua'),
    ]),
    _Row('Nước cốt dừa', 80, 'ml', optional: true, subs: [
      _Sub('Sữa dừa', 160, 'ml', 'Nhẹ béo hơn'),
    ]),
    _Row('Hạt bí', 20, 'g', optional: true, subs: [
      _Sub('Hạt hướng dương', 20, 'g', 'Bùi, dễ mua'),
    ]),
  ]),
  _Dish('Đậu hũ ky cuốn nấm hấp tương', 2, [
    _Row('Đậu hũ ky', 150, 'g', signature: true, subs: [
      _Sub('Bánh tráng', 150, 'g', 'Vỏ cuốn không chứa đậu nành', role: _dam),
    ]),
    _Row('Nấm kim châm', 200, 'g', signature: true, subs: [
      _Sub('Nấm đùi gà', 200, 'g', 'Dai, thơm hơn'),
    ]),
    _Row('Nấm mộc nhĩ', 30, 'g', subs: [
      _Sub('Nấm đông cô', 30, 'g', 'Thơm hơn'),
    ]),
    _Row('Gừng', 10, 'g', optional: true),
    _Row('Nước tương', 2, 'muỗng canh', grams: 30, subs: _subNuocTuong),
  ]),
  _Dish('Gỏi cuốn đậu hũ bơ sốt tương phộng', 2, [
    _Row('Bánh tráng', 6, 'lá', grams: 60, signature: true, subs: [
      _Sub('Bánh tráng gạo lứt', 6, 'lá', 'Nhiều chất xơ hơn', grams: 60),
    ]),
    _Row('Đậu hũ', 150, 'g', signature: true, subs: [
      _Sub('Tempeh', 80, 'g', 'Chắc, nhiều đạm hơn'),
      _Sub('Nấm đùi gà', 200, 'g', 'Không chứa đậu nành', role: _dam),
    ]),
    _Row('Bơ', 100, 'g', signature: true, subs: [
      _Sub('Xoài', 100, 'g', 'Chua ngọt, ít béo hơn'),
    ]),
    _Row('Rau thơm', 30, 'g', optional: true),
    _Row('Bún tươi', 100, 'g', subs: [
      _Sub('Bún gạo lứt', 100, 'g', 'Nhiều chất xơ hơn'),
    ]),
    _Row('Đậu phộng', 45, 'g', subs: [
      _Sub('Hạt hướng dương', 45, 'g', 'Không chứa đậu phộng'),
    ]),
  ]),

  // Bữa phụ.
  _Dish('Sữa hạt điều mè đen ấm', 1, [
    _Row('Hạt điều', 25, 'g', signature: true, subs: [
      _Sub('Hạt bí', 25, 'g', 'Không chứa hạt cây'),
      _Sub('Hạt hạnh nhân', 25, 'g', 'Thơm, ít béo hơn'),
    ]),
    _Row('Mè đen', 7, 'g', signature: true, subs: [
      _Sub('Hạt lanh', 7, 'g', 'Không chứa mè'),
    ]),
    _Row('Nước ấm', 200, 'ml'),
  ]),
  _Dish('Bánh chuối yến mạch nướng', 1, [
    _Row('Chuối', 100, 'g', signature: true, subs: [
      _Sub('Táo', 100, 'g', 'Ít ngọt hơn'),
    ]),
    _Row('Yến mạch', 25, 'g', signature: true, subs: [
      _Sub('Khoai lang', 110, 'g', 'Không chứa gluten', role: _tinhBot),
    ]),
    _Row('Hạt chia', 5, 'g', optional: true, subs: [
      _Sub('Hạt lanh', 5, 'g', 'Bùi, cũng nhiều chất xơ'),
    ]),
  ]),
  _Dish('Chè hạt sen đậu đỏ ngọt thanh', 1, [
    _Row('Hạt sen', 20, 'g', signature: true, subs: [
      _Sub('Đậu xanh', 20, 'g', 'Bùi, dễ mua', role: _hat),
    ]),
    _Row('Đậu đỏ', 25, 'g', signature: true, subs: [
      _Sub('Đậu đen', 25, 'g', 'Bùi, màu đậm'),
    ]),
    _Row('Đường phèn', 18, 'g', subs: [
      _Sub('Đường thốt nốt', 18, 'g', 'Thơm, ngọt dịu'),
    ]),
  ]),
  _Dish('Đậu phộng rang tỏi ớt lá chanh', 1, [
    _Row('Đậu phộng', 32, 'g', signature: true, subs: [
      _Sub('Hạt hướng dương', 32, 'g', 'Không chứa đậu phộng'),
      _Sub('Hạt điều', 32, 'g', 'Béo, không chứa đậu phộng'),
    ]),
    _Row('Tỏi', 5, 'g', optional: true),
    _Row('Ớt', 3, 'g', optional: true),
    _Row('Lá chanh', 2, 'g', optional: true),
  ]),
  _Dish('Bơ dầm sữa đậu nành hạt chia', 1, [
    _Row('Bơ', 100, 'g', signature: true, subs: [
      _Sub('Chuối', 150, 'g', 'Ít béo, ngọt hơn'),
    ]),
    _Row('Sữa đậu nành', 60, 'ml', subs: [
      _Sub('Sữa dừa', 60, 'ml', 'Không chứa đậu nành'),
    ]),
    _Row('Hạt chia', 8, 'g', optional: true, subs: [
      _Sub('Hạt lanh', 8, 'g', 'Bùi, cũng nhiều chất xơ'),
    ]),
  ]),
];

/// "Cơm chiên  HẠT SEN" → "com chien hat sen": how a recipe name finds its row.
String normalizedRecipeName(String name) =>
    foldVietnamese(name).trim().replaceAll(RegExp(r'\s+'), ' ');

String _slug(String name) => foldVietnamese(name)
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

double _round1(double v) => (v * 10).roundToDouble() / 10;

/// What [grams] of [food] bring to the recipe, in the wire format.
Map<String, Object?> _nutrition(String food, double grams) {
  final f = _foods[food]!;
  double of(double per100) => _round1(per100 * grams / 100);
  return {
    'calories': of(f.kcal),
    'proteinG': of(f.protein),
    'carbsG': of(f.carbs),
    'fatG': of(f.fat),
    'fiberG': of(f.fiber),
  };
}

num _plain(double v) => v == v.roundToDouble() ? v.round() : v;

Map<String, Object?> _rowJson(_Row row) {
  final food = _foods[row.name]!;
  final key = _slug(row.name);
  return {
    'key': key,
    'name': row.name,
    'quantity': _plain(row.quantity),
    'unit': row.unit,
    'role': row.role ?? food.group,
    if (row.signature) 'isSignature': true,
    if (row.optional) 'isOptional': true,
    'allergens': food.allergens,
    'nutrition': _nutrition(row.name, row.grams ?? row.quantity),
    if (row.subs.isNotEmpty)
      'substitutes': [
        for (final s in row.subs)
          {
            'key': '${key}_${_slug(s.name)}',
            'name': s.name,
            'quantity': _plain(s.quantity),
            'unit': s.unit,
            'role': s.role ?? _foods[s.food ?? s.name]!.group,
            'note': s.note,
            'allergens': _foods[s.food ?? s.name]!.allergens,
            'nutrition': _nutrition(s.food ?? s.name, s.grams ?? s.quantity),
          },
      ],
  };
}

/// The table for one recipe: [rows] are `ingredients` rows in the wire format
/// (`RecipeIngredientDto.fromJson`), each for [servings] servings.
class BackendRecipeItems {
  const BackendRecipeItems(this.name, this.servings, this.rows);

  final String name;
  final int servings;
  final List<Map<String, Object?>> rows;

  Map<String, Object?> toJson() =>
      {'name': name, 'servings': servings, 'ingredientItems': rows};
}

final Map<String, BackendRecipeItems> _byName = {
  for (final d in _dishes)
    normalizedRecipeName(d.name): BackendRecipeItems(
        d.name, d.servings, [for (final r in d.rows) _rowJson(r)]),
};

/// The table's row for a BE seed recipe; `null` for any other name.
BackendRecipeItems? backendRecipeItemsFor(String recipeName) =>
    _byName[normalizedRecipeName(recipeName)];

/// The whole table, for the BE seed.
List<Map<String, Object?>> backendRecipeItemsJson() =>
    [for (final items in _byName.values) items.toJson()];

/// [json] (a BE `RecipeResponse` of a catalogue recipe) with the table's rows in
/// place of its strings, in the BE's order: a row the table doesn't know stays
/// the BE's string, so nothing is dropped. Unknown names and a response with
/// `ingredientItems` stay as they are.
Map<String, dynamic> withBackendRecipeItems(Map<String, dynamic> json) {
  final items = backendRecipeItemsFor(json['name']?.toString() ?? '');
  if (items == null || _hasItems(json)) return json;
  final listed = json['ingredients'];
  final rows = {for (final r in items.rows) r['name']: r};
  final allergens = <Object?>{
    if (json['allergens'] case final List<Object?> tags) ...tags,
    for (final r in items.rows) ...r['allergens']! as List<Object?>,
  };
  return {
    ...json,
    'servings': items.servings,
    'allergens': allergens.toList(),
    'ingredients': listed is List<Object?> && listed.isNotEmpty
        ? [for (final name in listed) rows[name] ?? name]
        : items.rows,
  };
}

bool _hasItems(Map<String, dynamic> json) =>
    json['ingredientItems'] is List<Object?> &&
    (json['ingredientItems']! as List<Object?>).isNotEmpty;

final _savedVariantNote =
    RegExp(r'^Biến thể của «(.+)» · Định lượng cho (\d+) phần');

/// First step of a variant saved with POST /recipes, which has no field for
/// where it came from or its servings. Readable as it is on any other client.
String savedVariantNote(String baseName, int servings) =>
    'Biến thể của «$baseName» · Định lượng cho $servings phần · '
    'Năng lượng là ước tính.';

/// [json] (a BE `RecipeResponse` of the member's own recipe) as a saved variant
/// when its first step says it is one: rows matched back to the table keep
/// their role, signature flag and substitutes, so they follow the same swap
/// rules; a row typed by hand stays plain text. Any other recipe is unchanged.
Map<String, dynamic> withSavedVariantItems(Map<String, dynamic> json) {
  final steps = json['instructions'];
  final listed = json['ingredients'];
  if (steps is! List<Object?> || steps.isEmpty || listed is! List<Object?>) {
    return json;
  }
  if (_hasItems(json)) return json;
  final note = _savedVariantNote.firstMatch('${steps.first}');
  final items = note == null ? null : backendRecipeItemsFor(note.group(1)!);
  if (note == null || items == null) return json;
  final unused = [...items.rows];
  return {
    ...json,
    'servings': int.parse(note.group(2)!),
    'basedOnName': items.name,
    'nutritionEstimated': true,
    'instructions': steps.sublist(1),
    'ingredients': [
      for (final (i, text) in listed.indexed)
        _matchSavedRow('$text', i, unused) ?? text,
    ],
  };
}

/// The table row [text] was saved from ("Nấm rơm băm nhuyễn 250 g"), taken out
/// of [unused]; a swapped row offers the original and the other options back.
Map<String, Object?>? _matchSavedRow(
    String text, int index, List<Map<String, Object?>> unused) {
  final saved = RecipeIngredientDto.fromText(text, key: 'row$index').entity;
  for (final row in unused) {
    final subs = (row['substitutes'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    if (row['name'] == saved.name) {
      unused.remove(row);
      return _atSavedAmount(row, saved.quantity, saved.unit);
    }
    for (final s in subs) {
      if (s['name'] != saved.name) continue;
      unused.remove(row);
      return _atSavedAmount({
        ...row,
        'name': s['name'],
        'quantity': s['quantity'],
        'unit': s['unit'],
        'allergens': s['allergens'],
        'nutrition': s['nutrition'],
        'substitutes': [
          {
            'key': '${row['key']}_goc',
            'name': row['name'],
            'quantity': row['quantity'],
            'unit': row['unit'],
            'note': 'Nguyên liệu của công thức gốc',
            'allergens': row['allergens'],
            'nutrition': row['nutrition'],
          },
          for (final other in subs)
            if (other != s) other,
        ],
      }, saved.quantity, saved.unit);
    }
  }
  return null;
}

/// [row] with an amount edited after it was saved, its nutrition following.
Map<String, Object?> _atSavedAmount(
    Map<String, Object?> row, double? quantity, String unit) {
  final base = row['quantity'] as num?;
  if (quantity == null || base == null || base <= 0 || unit != row['unit']) {
    return row;
  }
  final ratio = quantity / base;
  final nutrition = row['nutrition'] as Map<String, Object?>?;
  return {
    ...row,
    'quantity': quantity,
    if (nutrition != null)
      'nutrition': {
        for (final MapEntry(:key, :value) in nutrition.entries)
          key: value is num ? _round1(value * ratio) : value,
      },
  };
}
