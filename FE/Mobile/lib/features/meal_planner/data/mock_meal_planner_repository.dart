// lib/features/meal_planner/data/mock_meal_planner_repository.dart
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/mock_accounts.dart';
import '../../../core/utils/bmi.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../scanner/domain/vegan_check.dart';
import '../domain/entities/meal_plan.dart';
import 'meal_planner_api_service.dart';
import 'mock/meal_planner_mock_data.dart';
import 'mock/mock_recipe_book.dart';
import 'models/health_profile_model.dart';
import 'models/meal_plan_model.dart';
import 'models/pantry_model.dart';
import 'pantry_api_service.dart';

/// In-memory backend with realistic latency. Behaves like the real API:
/// each account has its own health profile, plan and recipes (kept for the
/// app session, so switching accounts and back finds them again); swaps and
/// added meals persist; suggestions and generated plans respect allergies.
///
/// Mock triggers: saving weight exactly 99.9 kg → 503; `#fail` in a recipe
/// name → 503.
class MockMealPlannerRepository implements MealPlannerApiService {
  MockMealPlannerRepository({this.userId});

  /// Signed-in user; `null` for guests and bare test containers.
  final String? userId;

  static final Map<String, _PlannerStore> _stores = {};

  /// Fresh seeds for every account (tests).
  @visibleForTesting
  static void reset() {
    _stores.clear();
    MockRecipeBook.reset();
    MockPantryRepository.reset();
  }

  _PlannerStore get _store => _stores[userId ?? 'guest'] ??= _PlannerStore();

  /// Allergen id → Vietnamese ingredient words that contain it (whole words,
  /// so "nấm mèo" is not mistaken for "mè").
  static const _allergenWords = {
    'peanut': ['đậu phộng', 'lạc rang'],
    'soy': ['đậu hũ', 'đậu phụ', 'tàu hũ', 'đậu nành', 'nước tương', 'tempeh'],
    'gluten': ['bánh mì', 'lúa mì', 'mì căn', 'mì ý'],
    'sesame': ['mè', 'vừng'],
    'tree_nut': ['hạt điều', 'hạnh nhân', 'óc chó'],
  };

  /// Allergens the server would infer from a dish name and its ingredients.
  static Set<String> detectAllergens(String name,
      [Iterable<String> ingredients = const []]) {
    final words = [name, ...ingredients].map((w) => ' ${w.toLowerCase()} ');
    return {
      for (final MapEntry(key: id, value: names) in _allergenWords.entries)
        if (words.any((w) => names.any((n) => w.contains(' $n ')))) id,
    };
  }

  HealthProfileDto get _healthProfile =>
      _store.profile ??= HealthProfileDto.fromJson(
        mockHealthProfileJsonFor(
          userId,
          syncProvider: defaultTargetPlatform == TargetPlatform.iOS
              ? 'apple_health'
              : 'health_connect',
        ),
      );

  @override
  Future<HealthProfileDto> getHealthProfile() async {
    await mockDelay(500);
    return _healthProfile;
  }

  @override
  Future<HealthProfileDto> updateHealthProfile(
      UpdateHealthProfileRequestDto request) async {
    await mockDelay(700);
    if (request.weightKg == 99.9) {
      throw const ApiException(
          message: 'Chưa lưu được hồ sơ sức khoẻ. Thử lại sau ít phút.',
          statusCode: 503);
    }
    if (request.heightCm < 100 ||
        request.heightCm > 230 ||
        request.weightKg < 30 ||
        request.weightKg > 250) {
      throw const ApiException(
          message: 'Chiều cao hoặc cân nặng chưa hợp lệ.', statusCode: 400);
    }
    final bmi =
        Bmi.calculate(heightCm: request.heightCm, weightKg: request.weightKg);
    return _store.profile = HealthProfileDto(
      heightCm: request.heightCm,
      weightKg: request.weightKg,
      // health_profiles.bmi is cached with one decimal.
      bmi: (bmi * 10).roundToDouble() / 10,
      goal: request.goal.apiValue,
      allergies: request.allergies,
      dietaryRestrictions: request.dietaryRestrictions,
      healthSync: _healthProfile.healthSync,
    );
  }

  @override
  Future<MealPlanDto?> getCurrentMealPlan() async {
    await mockDelay(800);
    return _store.plan ??= _buildWeek(startOfWeek(DateTime.now()));
  }

  @override
  Future<MealPlanDto> generateMealPlan(
      {required DateTime startDate, bool fromPantry = false}) async {
    await mockDelay(2200); // generation is slow on the real server too
    return _store.plan = _generate(startDate,
        pantry: fromPantry ? MockPantryRepository.itemsOf(userId) : null);
  }

  @override
  Future<MealPlanDto> createEmptyMealPlan({required DateTime startDate}) async {
    await mockDelay(600);
    return _store.plan = MealPlanDto.fromJson({
      'id': 'mp_${toApiDate(startDate)}_manual',
      'startDate': toApiDate(startDate),
      'goal': _healthProfile.goal,
      'dailyTargets': mockDailyTargets,
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': toApiDate(startDate.add(Duration(days: i))),
            'meals': <String, Object?>{},
          },
      ],
    });
  }

  @override
  Future<List<RecipeDto>> getSwapSuggestions({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  }) async {
    await mockDelay(1100);
    final plan = _requirePlan(planId);
    final day = plan.days.firstWhere((d) => isSameDay(d.date, date));
    final current = day.meals[slot.apiValue];
    final allergies = _healthProfile.allergies.toSet();
    // An empty slot aims at a third of the day's target.
    final targetKcal = current != null && current.nutrition.calories > 0
        ? current.nutrition.calories
        : plan.dailyTargets.calories ~/ 3;

    final pool = [
      ...?mockSwapPool[slot.apiValue],
      ..._slotRecipes(slot),
    ].map(RecipeDto.fromJson);

    final suggestions = pool
        .where((r) => r.id != current?.id)
        .where((r) => !r.allergens.any(allergies.contains))
        .where((r) =>
            (r.nutrition.calories - targetKcal).abs() <= targetKcal * 0.1)
        .toList()
      ..sort((a, b) => (a.nutrition.calories - targetKcal)
          .abs()
          .compareTo((b.nutrition.calories - targetKcal).abs()));
    return suggestions.take(3).toList();
  }

  @override
  Future<MealPlanDayDto> swapMeal({
    required String planId,
    required SwapMealRequestDto request,
  }) async {
    await mockDelay(600);
    final plan = _requirePlan(planId);
    final recipe = _findRecipe(request.recipeId);
    if (recipe == null) {
      throw const ApiException(
          message: 'Món ăn không còn khả dụng.', statusCode: 404);
    }
    final placed = request.source == null
        ? recipe
        : recipe.withSource(request.source!.apiValue);
    return _put(plan, request.date, request.slot, placed);
  }

  @override
  Future<MealPlanDayDto> addMealToCurrentPlan(AddMealRequestDto request) async {
    await mockDelay(700);
    final plan = _store.plan ??= _buildWeek(startOfWeek(DateTime.now()));
    if (request.name.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa thêm được món. Thử lại nhé.', statusCode: 503);
    }
    final recipe = _recipeFromRequest(request);
    _store.added[recipe.id] = recipe;
    return _put(plan, request.date, request.slot, recipe);
  }

  @override
  Future<MealPlanDayDto> removeMeal({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  }) async {
    await mockDelay(400);
    final plan = _requirePlan(planId);
    final day = _dayOf(plan, date);
    final updated = MealPlanDayDto(
      date: day.date,
      meals: {...day.meals}..remove(slot.apiValue),
    );
    _store.plan = plan.copyWithDay(updated);
    return updated;
  }

  @override
  Future<List<RecipeDto>> getMyRecipes() async {
    await mockDelay(500);
    final id = userId;
    if (id == null) return const [];
    return MockRecipeBook.userRecipes(id)
        .map((r) =>
            RecipeDto.fromJson(r).withSource(MealSource.userRecipe.apiValue))
        .toList();
  }

  @override
  Future<RecipeDto> createMyRecipe(CreateRecipeRequestDto request) async {
    await mockDelay(700);
    final id = userId;
    if (id == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
    if (request.name.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa lưu được công thức. Thử lại nhé.', statusCode: 503);
    }
    if (request.name.trim().length < 2 ||
        request.ingredients.isEmpty ||
        request.steps.isEmpty) {
      throw const ApiException(
          message: 'Công thức cần tên, nguyên liệu và cách làm.',
          statusCode: 400);
    }
    // Only the macros the member typed: none are made up from the kcal.
    final row = MockRecipeBook.addUserRecipe(
      userId: id,
      userName: _accountName(id),
      recipe: {
        ...request.toJson(),
        'allergens': detectAllergens(
            request.name, request.ingredients.map((i) => i.name)).toList(),
        'dietTags': <String>[],
      },
    );
    return RecipeDto.fromJson(row).withSource(MealSource.userRecipe.apiValue);
  }

  @override
  Future<List<ChefSuggestionDto>> getChefSuggestions() async {
    await mockDelay(600);
    final id = userId;
    if (id == null) return const [];
    return MockRecipeBook.chefSuggestions(id)
        .map((s) => ChefSuggestionDto.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  // ---------------------------------------------------------------------------

  static String? _accountName(String id) {
    for (final a in mockAccounts) {
      if (a.userId == id) return a.displayName;
    }
    return null;
  }

  MealPlanDayDto _dayOf(MealPlanDto plan, DateTime date) {
    final day = plan.days.where((d) => isSameDay(d.date, date)).firstOrNull;
    if (day == null) {
      throw const ApiException(
          message: 'Ngày này không thuộc thực đơn tuần hiện tại.',
          statusCode: 404);
    }
    return day;
  }

  MealPlanDayDto _put(
      MealPlanDto plan, DateTime date, MealSlot slot, RecipeDto recipe) {
    final day = _dayOf(plan, date);
    final updated = MealPlanDayDto(
      date: day.date,
      meals: {...day.meals, slot.apiValue: recipe},
    );
    _store.plan = plan.copyWithDay(updated);
    return updated;
  }

  /// What the server does for an off-catalogue dish: keeps its kcal and only
  /// the macros it was given (missing ones stay `null`, never estimated into
  /// the dish) and flags allergens found in the name and ingredients.
  /// Allergens are flagged, never silently dropped.
  RecipeDto _recipeFromRequest(AddMealRequestDto request) {
    final manual = request.source == MealSource.manual.apiValue;
    return RecipeDto(
      id: manual
          ? 'mn_${DateTime.now().microsecondsSinceEpoch}'
          : 'fs_${request.sourceId ?? request.name.hashCode.abs()}',
      name: request.name,
      nutrition: NutritionDto(
        calories: request.calories ?? 0,
        proteinG: request.proteinG,
        carbsG: request.carbsG,
        fatG: request.fatG,
      ),
      allergens: {
        ...request.allergens,
        ...detectAllergens(request.name, request.ingredients),
      }.toList(),
      prepMinutes: request.prepMinutes,
      source: request.source,
    );
  }

  MealPlanDto _requirePlan(String planId) {
    final plan = _store.plan;
    if (plan == null || plan.id != planId) {
      throw const ApiException(
          message: 'Không tìm thấy thực đơn.', statusCode: 404);
    }
    return plan;
  }

  List<Map<String, Object?>> _slotRecipes(MealSlot slot) => switch (slot) {
        MealSlot.breakfast => mockBreakfasts,
        MealSlot.lunch => mockLunches,
        MealSlot.dinner => mockDinners,
      };

  RecipeDto? _findRecipe(String id) {
    if (_store.added[id] case final added?) return added;
    final owner = userId;
    if (owner != null) {
      for (final r in MockRecipeBook.userRecipes(owner)) {
        if (r['id'] == id) {
          return RecipeDto.fromJson(r)
              .withSource(MealSource.userRecipe.apiValue);
        }
      }
      for (final s in MockRecipeBook.chefSuggestions(owner)) {
        final dto = ChefSuggestionDto.fromJson(Map<String, dynamic>.from(s));
        if (dto.recipe.id == id) {
          return dto.recipe
              .withSource(MealSource.chef.apiValue, sourceName: dto.chefName);
        }
      }
    }
    final all = [
      ...mockBreakfasts,
      ...mockLunches,
      ...mockDinners,
      for (final list in mockSwapPool.values) ...list,
      ...mockPantryDishes,
    ];
    for (final json in all) {
      if (json['id'] == id) return RecipeDto.fromJson(json);
    }
    return null;
  }

  MealPlanDto _buildWeek(DateTime monday) {
    final days = List.generate(7, (i) {
      final date = monday.add(Duration(days: i));
      return {
        'date': toApiDate(date),
        'meals': {
          'breakfast': mockBreakfasts[i],
          'lunch': mockLunches[i],
          'dinner': mockDinners[i],
        },
      };
    });
    return MealPlanDto.fromJson({
      'id': 'mp_${toApiDate(monday)}',
      'startDate': toApiDate(monday),
      'goal': 'lean_muscle',
      'dailyTargets': mockDailyTargets,
      'days': days,
    });
  }

  /// A generated week: dishes with the member's allergens are swapped for
  /// the closest safe one. With a [pantry], dishes that use more of its
  /// vegan items come first, starting from today (anything not vegan in the
  /// fridge is ignored).
  MealPlanDto _generate(DateTime monday, {List<PantryItemDto>? pantry}) {
    final allergies = _healthProfile.allergies.toSet();
    bool safe(RecipeDto r) => !r.allergens.any(allergies.contains);
    final fridge = [
      for (final p in pantry ?? const <PantryItemDto>[])
        if (classifyVegan(p.ingredient).isVegan) foldVietnamese(p.ingredient),
    ];
    int score(RecipeDto r) {
      final name = foldVietnamese(r.name);
      var s = 0;
      for (final word in fridge) {
        if (word.isNotEmpty && name.contains(word)) s++;
      }
      return s;
    }

    final today = DateTime.now().difference(monday).inDays;
    final order = [
      for (var i = 0; i < 7; i++)
        (i + (today >= 0 && today < 7 ? today : 0)) % 7
    ];
    final meals = List.generate(7, (_) => <String, RecipeDto>{});

    for (final slot in MealSlot.values) {
      final defaults = _slotRecipes(slot).map(RecipeDto.fromJson).toList();
      final pool = [
        ...defaults,
        ...?mockSwapPool[slot.apiValue]?.map(RecipeDto.fromJson),
        if (slot != MealSlot.breakfast)
          ...mockPantryDishes.map(RecipeDto.fromJson),
      ].where(safe).toList();
      final ranked = [...pool.indexed]..sort((a, b) {
          final byScore = score(b.$2).compareTo(score(a.$2));
          return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
        });
      final used = <String>{};
      for (final dayIndex in order) {
        final original = defaults[dayIndex];
        final fromFridge = ranked
            .map((e) => e.$2)
            .where((r) => !used.contains(r.id) && score(r) > 0)
            .firstOrNull;
        RecipeDto pick;
        if (fromFridge != null) {
          pick = fromFridge;
        } else if (safe(original) && !used.contains(original.id)) {
          pick = original;
        } else {
          int gap(RecipeDto r) =>
              (r.nutrition.calories - original.nutrition.calories).abs();
          final unused = pool.where((r) => !used.contains(r.id)).toList();
          final options = unused.isNotEmpty ? unused : pool;
          pick = options.isEmpty
              ? original // nothing safe: kept and flagged in the planner
              : (options..sort((a, b) => gap(a).compareTo(gap(b)))).first;
        }
        used.add(pick.id);
        meals[dayIndex][slot.apiValue] =
            pick.withSource(MealSource.ai.apiValue);
      }
    }

    return MealPlanDto(
      id: 'mp_${toApiDate(monday)}_${DateTime.now().millisecondsSinceEpoch}',
      startDate: monday,
      goal: _healthProfile.goal,
      dailyTargets: NutritionDto.fromJson(mockDailyTargets),
      days: [
        for (var i = 0; i < 7; i++)
          MealPlanDayDto(date: monday.add(Duration(days: i)), meals: meals[i]),
      ],
    );
  }
}

class _PlannerStore {
  MealPlanDto? plan;
  HealthProfileDto? profile;

  /// Dishes added from outside the catalogue (fridge scan, typed in), by id.
  final Map<String, RecipeDto> added = {};
}
