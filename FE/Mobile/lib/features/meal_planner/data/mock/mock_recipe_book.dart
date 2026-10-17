// lib/features/meal_planner/data/mock/mock_recipe_book.dart

/// In-memory `recipes` rows that are not in the catalogue: recipes members
/// wrote ("Công thức của tôi") and dishes chefs suggested to a member ("Từ
/// chuyên gia"). Rows use the recipe-detail wire format (`caloriesCache`,
/// `ingredients` with quantity/unit, newline `instructions`), so the planner
/// reads them as `RecipeDto` and the recipe screen shows them in full.
///
/// Static for the app session: data follows the account, like every mock DB.
abstract final class MockRecipeBook {
  static final Map<String, List<Map<String, Object?>>> _userRecipes = {};
  static final Map<String, List<Map<String, Object?>>> _chefSuggestions = {
    'u_me': _seedSuggestionsForMinhAnh(),
  };
  static int _seq = 0;

  /// Back to the seeds (tests, via `MockMealPlannerRepository.reset`).
  static void reset() {
    _userRecipes.clear();
    _chefSuggestions
      ..clear()
      ..['u_me'] = _seedSuggestionsForMinhAnh();
  }

  static List<Map<String, Object?>> userRecipes(String userId) =>
      List.unmodifiable(_userRecipes[userId] ?? const []);

  /// Stores a member-written recipe and returns its row (id `ur_…`).
  static Map<String, Object?> addUserRecipe({
    required String userId,
    required String? userName,
    required Map<String, Object?> recipe,
  }) {
    final row = <String, Object?>{
      ...recipe,
      'id': 'ur_${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      'isVegan': true,
      'createdBy': userId,
      'createdByName': userName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    (_userRecipes[userId] ??= []).insert(0, row);
    return row;
  }

  /// `{ id, chefId, chefName, note, slot, targetDate?, createdAt, recipe }`,
  /// newest first.
  static List<Map<String, Object?>> chefSuggestions(String userId) =>
      List.unmodifiable(_chefSuggestions[userId] ?? const []);

  /// A dish of a delivered chef plan (booking plan day, D15b) for the
  /// member [userId]'s "Từ chuyên gia": [recipe] in the detail wire format,
  /// without an id. [targetDate] (`yyyy-MM-dd`) is the plan day, if any.
  static Map<String, Object?> addChefSuggestion({
    required String userId,
    required String chefId,
    required String chefName,
    required Map<String, Object?> recipe,
    String? note,
    String? slot,
    String? targetDate,
  }) {
    final n = _seq++;
    final row = <String, Object?>{
      'id': 'sg_${DateTime.now().millisecondsSinceEpoch}_$n',
      'chefId': chefId,
      'chefName': chefName,
      'note': note,
      'slot': slot,
      if (targetDate != null) 'targetDate': targetDate,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'recipe': {
        ...recipe,
        'id': 'cs_${DateTime.now().millisecondsSinceEpoch}_$n',
        'isVegan': true,
        'createdBy': chefId,
        'createdByName': chefName,
      },
    };
    (_chefSuggestions[userId] ??= []).insert(0, row);
    return row;
  }

  /// Any stored recipe by id, for the recipe screen.
  static Map<String, Object?>? findDetail(String id) {
    for (final list in _userRecipes.values) {
      for (final r in list) {
        if (r['id'] == id) return r;
      }
    }
    for (final list in _chefSuggestions.values) {
      for (final s in list) {
        final recipe = s['recipe']! as Map<String, Object?>;
        if (recipe['id'] == id) return recipe;
      }
    }
    return null;
  }

  static List<Map<String, Object?>> _seedSuggestionsForMinhAnh() {
    String ago(Duration d) =>
        DateTime.now().subtract(d).toUtc().toIso8601String();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    String two(int n) => n.toString().padLeft(2, '0');
    const tam = 'u_chef_tam';
    const tamName = 'Lê Quang Tâm';
    return [
      {
        'id': 'sg_tam_chao',
        'chefId': tam,
        'chefName': tamName,
        'note': 'Bữa sáng nhẹ bụng, đủ xơ cho người mới tập ăn chay.',
        'slot': 'breakfast',
        'createdAt': ago(const Duration(days: 1)),
        'recipe': {
          'id': 'cs_tam_chao_yen_mach',
          'name': 'Cháo yến mạch hạt sen táo đỏ',
          'caloriesCache': 390,
          'proteinG': 13,
          'carbsG': 64,
          'fatG': 9,
          'fiberG': 8,
          'allergens': <String>[],
          'dietTags': ['high_fiber'],
          'prepMinutes': 20,
          'servings': 1,
          'isVegan': true,
          'createdBy': tam,
          'createdByName': tamName,
          'ingredients': [
            {'name': 'Yến mạch cán', 'quantity': 60, 'unit': 'g'},
            {'name': 'Hạt sen tươi', 'quantity': 40, 'unit': 'g'},
            {'name': 'Táo đỏ khô', 'quantity': 5, 'unit': 'quả'},
            {'name': 'Nước lọc', 'quantity': 400, 'unit': 'ml'},
            {'name': 'Đường phèn', 'quantity': 1, 'unit': 'muỗng cà phê'},
          ],
          'instructions': '1. Hầm hạt sen với 400 ml nước 15 phút cho bở.\n'
              '2. Cho yến mạch và táo đỏ vào, khuấy đều, nấu nhỏ lửa 5 phút.\n'
              '3. Nêm chút đường phèn, tắt bếp và để 2 phút cho cháo sánh.',
        },
      },
      {
        'id': 'sg_tam_com',
        'chefId': tam,
        'chefName': tamName,
        'note': 'Giàu đạm, hợp bữa tối sau buổi tập.',
        'slot': 'dinner',
        // Shows "Cho bữa tối · <Thứ>, dd/MM" in "Từ chuyên gia".
        'targetDate':
            '${tomorrow.year}-${two(tomorrow.month)}-${two(tomorrow.day)}',
        'createdAt': ago(const Duration(days: 2)),
        'recipe': {
          'id': 'cs_tam_com_dau_hu_nam',
          'name': 'Cơm gạo lứt đậu hũ non sốt nấm',
          'caloriesCache': 560,
          'proteinG': 28,
          'carbsG': 74,
          'fatG': 16,
          'fiberG': 9,
          'allergens': ['soy'],
          'dietTags': ['high_protein'],
          'prepMinutes': 30,
          'servings': 1,
          'isVegan': true,
          'createdBy': tam,
          'createdByName': tamName,
          'ingredients': [
            {'name': 'Gạo lứt', 'quantity': 80, 'unit': 'g'},
            {'name': 'Đậu hũ non', 'quantity': 300, 'unit': 'g'},
            {'name': 'Nấm đông cô', 'quantity': 5, 'unit': 'cái'},
            {'name': 'Nấm bào ngư', 'quantity': 100, 'unit': 'g'},
            {'name': 'Nước tương', 'quantity': 1, 'unit': 'muỗng canh'},
            {'name': 'Hành lá', 'quantity': 2, 'unit': 'nhánh'},
          ],
          'instructions': '1. Nấu cơm gạo lứt (ngâm gạo trước 2 tiếng nếu kịp).\n'
              '2. Xào thơm nấm đông cô và nấm bào ngư với chút dầu.\n'
              '3. Cho nước tương và nửa chén nước, đặt đậu hũ non vào, đun nhỏ lửa 5 phút.\n'
              '4. Rắc hành lá, ăn kèm cơm gạo lứt.',
        },
      },
    ];
  }
}
