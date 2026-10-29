// lib/features/meal_planner/data/mock_meal_planner_repository.dart
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/mock_accounts.dart';
import '../../../core/utils/bmi.dart';
import '../../../core/utils/energy.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../recipe/data/mock/recipe_mock_data.dart';
import '../../scanner/domain/vegan_check.dart';
import '../domain/allergy_match.dart';
import '../domain/entities/body_measurement.dart';
import '../domain/entities/health_profile.dart';
import '../domain/entities/meal_plan.dart';
import '../domain/entities/plan_adjustment.dart';
import 'meal_planner_api_service.dart';
import 'mock/body_measurement_mock_data.dart';
import 'mock/meal_planner_mock_data.dart';
import 'mock/mock_plan_adjuster.dart';
import 'mock/mock_recipe_book.dart';
import 'models/body_measurement_model.dart';
import 'models/health_profile_model.dart';
import 'models/meal_plan_model.dart';
import 'models/pantry_model.dart';
import 'pantry_api_service.dart';

/// In-memory backend with realistic latency. Behaves like the real API:
/// each account has its own health profile, plan and recipes (kept for the
/// app session, so switching accounts and back finds them again); swaps and
/// added meals persist; suggestions and generated plans respect allergies
/// (tagged ids and free-text names) and the member's meals of the day, and
/// AI plans size portions so each day meets the kcal target.
///
/// Only the demo accounts (Minh Anh `u_me`, Lê Quang Tâm `u_chef_tam`) start
/// with a health profile and a filled week. Anyone else (an account
/// registered in this run) starts with neither, like on the server: no
/// profile (404 → `null`) and no plan until they set one up.
///
/// Weigh-ins (`health_metric_logs`): the demo accounts start with seeded
/// history dated relative to the clock; a profile save that changes the
/// weight by more than 0,05 kg logs a `profile` row (the first save of a new
/// account too), "Cập nhật cân nặng" a `check_in` row.
///
/// Mock triggers: saving weight exactly 99.9 kg (profile or check-in) → 503;
/// `#fail` in a recipe name or an AI request → 503.
class MockMealPlannerRepository implements MealPlannerApiService {
  MockMealPlannerRepository({this.userId, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Signed-in user; `null` for guests and bare test containers.
  final String? userId;

  /// "Now" for the current week and "today" (tests pin it).
  final DateTime Function() _clock;

  static final Map<String, _PlannerStore> _stores = {};
  static int _proposalSeq = 0;

  /// Fresh seeds for every account (tests).
  @visibleForTesting
  static void reset() {
    _stores.clear();
    MockRecipeBook.reset();
    MockPantryRepository.reset();
  }

  _PlannerStore get _store => _stores[userId ?? 'guest'] ??= _PlannerStore(
        _seedProfile(userId),
        measurements: [
          for (final json in mockBodyMeasurementsFor(userId, _clock()))
            BodyMeasurementDto.fromJson(json),
        ],
      );

  /// The demo account's seed profile; `null` for everyone else.
  static HealthProfileDto? _seedProfile(String? userId) =>
      switch (mockHealthProfileJsonFor(
        userId,
        syncProvider: defaultTargetPlatform == TargetPlatform.iOS
            ? 'apple_health'
            : 'health_connect',
      )) {
        final json? => HealthProfileDto.fromJson(json),
        null => null,
      };

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

  /// `null` until the member saves one ("Hồ sơ sức khoẻ").
  HealthProfileDto? get _healthProfile => _store.profile;

  HealthProfile get _profile =>
      _healthProfile?.toEntity() ?? HealthProfile.empty;

  /// The member's meals of the day (3 meals without a profile).
  List<MealSlot> get _pattern => _profile.mealPattern;

  /// Allergies dishes are checked against (none without a profile).
  List<String> get _allergies => _profile.allergies;

  String get _goal => _profile.goal.apiValue;

  /// TDEE-based target; 1.850 kcal until gender and birth year are known.
  int get _dailyKcal => _profile.dailyKcalTarget ?? 1850;

  @override
  Future<HealthProfileDto?> getHealthProfile() async {
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
    final saved = _healthProfile;
    final birthYear = request.birthYear ?? saved?.birthYear;
    if (birthYear != null && !Energy.isValidBirthYear(birthYear)) {
      throw const ApiException(
          message: 'Năm sinh không hợp lệ (13–100 tuổi).', statusCode: 400);
    }
    if (request.mealPattern case final p? when p.isEmpty) {
      throw const ApiException(message: 'Chọn ít nhất 1 bữa.', statusCode: 400);
    }
    final dto = _saveProfile(request);
    // Like the server: a weight change (or the first save) is logged.
    if (saved == null || (saved.weightKg - request.weightKg).abs() > 0.05) {
      _logMeasurement(dto, source: MeasurementSource.profile);
    }
    return dto;
  }

  /// Stores [request] as the profile with what the server recomputes (BMI
  /// cached with one decimal, BMR, TDEE; fields left `null` keep their saved
  /// value) and re-aims the current week at the new target.
  HealthProfileDto _saveProfile(UpdateHealthProfileRequestDto request) {
    final saved = _healthProfile;
    final birthYear = request.birthYear ?? saved?.birthYear;
    final bmi =
        Bmi.calculate(heightCm: request.heightCm, weightKg: request.weightKg);
    final gender = request.gender?.apiValue ?? saved?.gender;
    final activity = request.activityLevel?.apiValue ?? saved?.activityLevel;
    final pattern = request.mealPattern == null
        ? (saved?.mealPattern ?? MealPattern.toApi(MealPattern.standard))
        : MealPattern.toApi(request.mealPattern!);
    // What the server recomputes and caches.
    final energy = HealthProfile(
      heightCm: request.heightCm,
      weightKg: request.weightKg,
      bmi: bmi,
      goal: request.goal,
      gender: Gender.fromApi(gender),
      birthYear: birthYear,
      activityLevel: ActivityLevel.fromApi(activity),
    );
    final dto = _store.profile = HealthProfileDto(
      heightCm: request.heightCm,
      weightKg: request.weightKg,
      // health_profiles.bmi is cached with one decimal.
      bmi: (bmi * 10).roundToDouble() / 10,
      goal: request.goal.apiValue,
      allergies: [
        for (final a in request.allergies)
          if (a.trim().isNotEmpty) a.trim()
      ],
      dietaryRestrictions: request.dietaryRestrictions,
      healthSync: saved?.healthSync,
      gender: gender,
      birthYear: birthYear,
      activityLevel: activity,
      mealPattern: pattern,
      bmr: energy.bmr?.roundToDouble(),
      tdee: energy.tdee?.roundToDouble(),
    );
    // The current week now aims at the new profile's target.
    if (_store.plan case final plan?) {
      _store.plan = plan.withTargets(
          goal: _goal,
          dailyTargets: NutritionDto.fromJson(mockDailyTargetsFor(_dailyKcal)));
    }
    return dto;
  }

  /// One `health_metric_logs` row at [profile]'s height and BMI.
  BodyMeasurementDto _logMeasurement(
    HealthProfileDto profile, {
    required MeasurementSource source,
    double? waistCm,
    double? bodyFatPct,
  }) {
    final row = BodyMeasurementDto(
      id: 'm_${userId ?? 'guest'}_${++_store.measurementSeq}',
      weightKg: profile.weightKg,
      heightCm: profile.heightCm,
      bmi: profile.bmi,
      waistCm: waistCm,
      bodyFatPct: bodyFatPct,
      source: source.apiValue,
      loggedAt: _clock(),
    );
    _store.measurements.insert(0, row);
    return row;
  }

  @override
  Future<List<BodyMeasurementDto>> getBodyMeasurements(
      {int limit = 100}) async {
    await mockDelay(500);
    if (userId == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
    final rows = [..._store.measurements]
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return rows.take(limit.clamp(1, 100)).toList();
  }

  @override
  Future<LogMeasurementResultDto> logBodyMeasurement(
      LogMeasurementRequestDto request) async {
    await mockDelay(700);
    if (userId == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
    if (request.weightKg == 99.9) {
      throw const ApiException(
          message: 'Chưa lưu được cân nặng. Thử lại sau ít phút.',
          statusCode: 503);
    }
    if (request.weightKg < 30 || request.weightKg > 250) {
      throw const ApiException(
          message: 'Cân nặng từ 30 đến 250 kg', statusCode: 400);
    }
    if (request.waistCm case final w? when w < 40 || w > 200) {
      throw const ApiException(
          message: 'Vòng eo từ 40 đến 200 cm', statusCode: 400);
    }
    if (request.bodyFatPct case final f? when f < 3 || f > 70) {
      throw const ApiException(
          message: 'Tỉ lệ mỡ từ 3 đến 70 %', statusCode: 400);
    }
    final saved = _healthProfile;
    if (saved == null) {
      throw const ApiException(
          message: 'Bạn chưa tạo hồ sơ sức khỏe.', statusCode: 404);
    }
    // The saved profile with the new weight; everything else is kept.
    final profile = _saveProfile(UpdateHealthProfileRequestDto(
      heightCm: saved.heightCm,
      weightKg: request.weightKg,
      goal: HealthGoal.fromApi(saved.goal),
      allergies: saved.allergies,
      dietaryRestrictions: saved.dietaryRestrictions,
    ));
    final row = _logMeasurement(
      profile,
      source: MeasurementSource.checkIn,
      waistCm: request.waistCm,
      bodyFatPct: request.bodyFatPct,
    );
    return LogMeasurementResultDto(measurement: row, profile: profile);
  }

  @override
  Future<MealPlanDto?> getCurrentMealPlan() async {
    await mockDelay(800);
    if (_store.seeded) _store.plan ??= _buildWeek(startOfWeek(_clock()));
    return _store.plan;
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
    return _store.plan = _emptyWeek(startDate);
  }

  /// This week's plan; a dish added before there is one creates it: the
  /// demo week for the demo accounts, an empty week for anyone else.
  MealPlanDto _currentWeek() {
    final monday = startOfWeek(_clock());
    return _store.plan ??=
        _store.seeded ? _buildWeek(monday) : _emptyWeek(monday);
  }

  /// "Tự lên thực đơn": every slot empty.
  MealPlanDto _emptyWeek(DateTime startDate) => MealPlanDto.fromJson({
        'id': 'mp_${toApiDate(startDate)}_manual',
        'startDate': toApiDate(startDate),
        'goal': _goal,
        'dailyTargets': mockDailyTargetsFor(_dailyKcal),
        'days': [
          for (var i = 0; i < 7; i++)
            {
              'date': toApiDate(startDate.add(Duration(days: i))),
              'meals': <String, Object?>{},
            },
        ],
      });

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
    // An empty slot aims at its share of the day's target.
    final targetKcal = current != null && current.nutrition.calories > 0
        ? current.nutrition.calories
        : MealPattern.kcalTargets(
                {..._pattern, slot}, plan.dailyTargets.calories)[slot] ??
            plan.dailyTargets.calories ~/ 3;

    final suggestions = _swapPool(slot)
        .map((r) => r.scaled(_portionFor(targetKcal, r.nutrition.calories)))
        .where((r) => r.id != current?.id)
        .where(_isSafe)
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
    final sized = recipe.scaled(request.portion);
    final placed = request.source == null
        ? sized
        : sized.withSource(request.source!.apiValue);
    return _put(plan, request.date, request.slot, placed);
  }

  @override
  Future<MealPlanDayDto> addMealToCurrentPlan(AddMealRequestDto request) async {
    await mockDelay(700);
    final plan = _currentWeek();
    if (request.name.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa thêm được món. Thử lại nhé.', statusCode: 503);
    }
    final recipe = _recipeFromRequest(request);
    _store.added[recipe.id] = recipe;
    return _put(plan, request.date, request.slot, recipe);
  }

  /// One round trip for the whole batch (a 7-day chef plan is ~28 dishes).
  /// `#fail` in any dish name → 503 and nothing is placed.
  @override
  Future<AddMealsResultDto> addMealsToCurrentPlan(
      List<AddMealRequestDto> requests) async {
    await mockDelay(900);
    _currentWeek();
    if (requests.any((r) => r.name.toLowerCase().contains('#fail'))) {
      throw const ApiException(
          message: 'Chưa thêm được món. Thử lại nhé.', statusCode: 503);
    }
    final changed = <String, MealPlanDayDto>{};
    var skipped = 0;
    for (final request in requests) {
      final plan = _store.plan!;
      if (!plan.days.any((d) => isSameDay(d.date, request.date))) {
        skipped++;
        continue;
      }
      final recipe = _recipeFromRequest(request);
      _store.added[recipe.id] = recipe;
      final day = _put(plan, request.date, request.slot, recipe);
      changed[toApiDate(day.date)] = day;
    }
    return AddMealsResultDto(
      placed: requests.length - skipped,
      skipped: skipped,
      days: changed.values.toList(),
    );
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

  @override
  Future<PlanAdjustmentDto> adjustPlan(AdjustPlanRequestDto request) async {
    await mockDelay(1200);
    if (request.message.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Trợ lý AI đang bận. Thử lại sau ít phút nhé.',
          statusCode: 503);
    }
    if (request.message.trim().isEmpty) {
      throw const ApiException(
          message: 'Hãy nhập yêu cầu cho AI.', statusCode: 400);
    }
    final plan = _currentWeek();
    final proposal = MockPlanAdjuster(
      plan: plan,
      pattern: _pattern,
      allergies: _allergies,
      today: _clock(),
      dailyKcal: plan.dailyTargets.calories,
      poolFor: (slot) => [
        ..._swapPool(slot),
        if (slot == MealSlot.lunch || slot == MealSlot.dinner)
          ...mockPantryDishes.map(RecipeDto.fromJson),
      ],
    ).propose(request, 'adj_${++_proposalSeq}');
    _store.proposals[proposal.proposalId] =
        _Proposal(planId: plan.id, adjustment: proposal);
    return proposal;
  }

  @override
  Future<MealPlanDto> applyAdjustment({
    required String proposalId,
    required List<String> changeIds,
  }) async {
    await mockDelay(700);
    final proposal = _store.proposals[proposalId];
    if (proposal == null) {
      throw const ApiException(
          message: 'Đề xuất không còn hiệu lực. Hãy hỏi lại AI nhé.',
          statusCode: 404);
    }
    if (proposal.applied) {
      throw const ApiException(
          message: 'Đề xuất này đã được áp dụng.',
          statusCode: 409,
          code: 'already_applied');
    }
    final current = _store.plan;
    if (current == null || current.id != proposal.planId) {
      throw const ApiException(
          message: 'Thực đơn đã thay đổi. Hãy hỏi lại AI nhé.',
          statusCode: 409,
          code: 'plan_changed');
    }
    var plan = current;
    final chosen = proposal.adjustment.changes
        .where((c) => changeIds.contains(c.id))
        .toList();
    if (chosen.isEmpty) {
      throw const ApiException(
          message: 'Chọn ít nhất 1 thay đổi.', statusCode: 400);
    }
    for (final change in chosen) {
      final day = _dayOf(plan, change.date);
      final meals = {...day.meals};
      switch (PlanChangeAction.fromApi(change.action)) {
        case PlanChangeAction.add || PlanChangeAction.replace:
          meals[change.slot] = change.to!.withSource(MealSource.ai.apiValue);
        case PlanChangeAction.remove:
          meals.remove(change.slot);
      }
      plan = plan.copyWithDay(MealPlanDayDto(date: day.date, meals: meals));
    }
    proposal.applied = true;
    return _store.plan = plan;
  }

  // ---------------------------------------------------------------------------

  static String? _accountName(String id) {
    for (final a in mockAccounts) {
      if (a.userId == id) return a.displayName;
    }
    return null;
  }

  /// No tagged allergen and no free-text allergy in the name.
  bool _isSafe(RecipeDto r) => allergyConflicts(
          tags: r.allergens, texts: [r.name], userAllergies: _allergies)
      .isEmpty;

  /// Servings (¼ steps, ½–2) that bring [kcal] closest to [target].
  static double _portionFor(int target, int kcal) {
    if (kcal <= 0 || target <= 0) return 1;
    final quarters = (target / kcal * 4).round();
    return (quarters / 4).clamp(0.5, 2.0).toDouble();
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
  /// Allergens are flagged, never silently dropped. A chef's dish whose
  /// recipe is known ([AddMealRequestDto.sourceId]) is placed as that recipe.
  RecipeDto _recipeFromRequest(AddMealRequestDto request) {
    final manual = request.source == MealSource.manual.apiValue;
    final chef = request.source == MealSource.chef.apiValue;
    if (chef) {
      if (request.sourceId case final id?) {
        final known = _findRecipe(id) ??
            switch (MockRecipeBook.findDetail(id)) {
              final row? => RecipeDto.fromJson(row),
              null => null,
            };
        if (known != null) {
          return known.withSource(MealSource.chef.apiValue,
              sourceName: request.sourceName);
        }
      }
    }
    return RecipeDto(
      id: manual
          ? 'mn_${DateTime.now().microsecondsSinceEpoch}'
          : chef
              ? 'ch_${request.sourceId ?? request.name.hashCode.abs()}'
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
      sourceName: request.sourceName,
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

  /// The week's default dishes for [slot] (one per weekday).
  static List<Map<String, Object?>> _defaults(MealSlot slot) => switch (slot) {
        MealSlot.breakfast => mockBreakfasts,
        MealSlot.lunch => mockLunches,
        MealSlot.dinner => mockDinners,
        MealSlot.snackAm ||
        MealSlot.snackPm ||
        MealSlot.snackLate =>
          mockSnacks,
      };

  /// Default snack of [slot] on weekday [i]: each snack slot starts at a
  /// different one.
  static Map<String, Object?> _snackFor(MealSlot slot, int i) {
    final offset = switch (slot) {
      MealSlot.snackPm => 3,
      MealSlot.snackLate => 5,
      _ => 0,
    };
    return mockSnacks[(i + offset) % mockSnacks.length];
  }

  /// Every catalogue dish that fits [slot].
  static List<RecipeDto> _swapPool(MealSlot slot) => [
        ..._defaults(slot),
        ...switch (slot) {
          MealSlot.breakfast => mockSwapPool['breakfast']!,
          MealSlot.lunch => mockSwapPool['lunch']!,
          MealSlot.dinner => [...mockSwapPool['dinner']!, ...mockExtraDinners],
          MealSlot.snackAm ||
          MealSlot.snackPm ||
          MealSlot.snackLate =>
            mockSnackSwaps,
        },
      ].map(RecipeDto.fromJson).toList();

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
      ...mockSnacks,
      for (final list in mockSwapPool.values) ...list,
      ...mockExtraDinners,
      ...mockSnackSwaps,
      ...mockPantryDishes,
    ];
    for (final json in all) {
      if (json['id'] == id) return RecipeDto.fromJson(json);
    }
    // Any other catalogue recipe (e.g. `menu_2`, added from its page).
    if (mockRecipeDetail(id) case final json?) return RecipeDto.fromJson(json);
    return null;
  }

  /// The seeded current week: the member's slots, one serving each.
  MealPlanDto _buildWeek(DateTime monday) {
    final pattern = _pattern;
    final days = List.generate(7, (i) {
      final date = monday.add(Duration(days: i));
      return {
        'date': toApiDate(date),
        'meals': {
          for (final slot in pattern)
            slot.apiValue:
                slot.isSnack ? _snackFor(slot, i) : _defaults(slot)[i],
        },
      };
    });
    return MealPlanDto.fromJson({
      'id': 'mp_${toApiDate(monday)}',
      'startDate': toApiDate(monday),
      'goal': _goal,
      'dailyTargets': mockDailyTargetsFor(_dailyKcal),
      'days': days,
    });
  }

  /// A generated week for the member's slots: dishes with their allergies
  /// are swapped for the closest safe one, and each dish gets the portion
  /// that brings its slot to its share of the daily target. With a
  /// [pantry], dishes that use more of its vegan items come first, starting
  /// from today (anything not vegan in the fridge is ignored).
  MealPlanDto _generate(DateTime monday, {List<PantryItemDto>? pantry}) {
    final pattern = _pattern;
    final targets = MealPattern.kcalTargets(pattern, _dailyKcal);
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

    final today = dateOnly(_clock()).difference(monday).inDays;
    final order = [
      for (var i = 0; i < 7; i++)
        (i + (today >= 0 && today < 7 ? today : 0)) % 7
    ];
    final meals = List.generate(7, (_) => <String, RecipeDto>{});

    for (final slot in pattern) {
      final defaults = [
        for (var i = 0; i < 7; i++)
          RecipeDto.fromJson(
              slot.isSnack ? _snackFor(slot, i) : _defaults(slot)[i]),
      ];
      final pool = [
        ..._swapPool(slot),
        if (slot == MealSlot.lunch || slot == MealSlot.dinner)
          ...mockPantryDishes.map(RecipeDto.fromJson),
      ].where(_isSafe).toList();
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
        } else if (_isSafe(original) && !used.contains(original.id)) {
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
        final target = targets[slot] ?? pick.nutrition.calories;
        meals[dayIndex][slot.apiValue] = pick
            .scaled(_portionFor(target, pick.nutrition.calories))
            .withSource(MealSource.ai.apiValue);
      }
    }

    return MealPlanDto(
      id: 'mp_${toApiDate(monday)}_${DateTime.now().millisecondsSinceEpoch}',
      startDate: monday,
      goal: _goal,
      dailyTargets: NutritionDto.fromJson(mockDailyTargetsFor(_dailyKcal)),
      days: [
        for (var i = 0; i < 7; i++)
          MealPlanDayDto(date: monday.add(Duration(days: i)), meals: meals[i]),
      ],
    );
  }
}

class _Proposal {
  _Proposal({required this.planId, required this.adjustment});

  final String planId;
  final PlanAdjustmentDto adjustment;
  bool applied = false;
}

class _PlannerStore {
  _PlannerStore(this.profile,
      {List<BodyMeasurementDto> measurements = const []})
      : seeded = profile != null,
        measurements = [...measurements];

  /// A demo account: starts with a profile and the demo week.
  final bool seeded;
  MealPlanDto? plan;

  /// `null` until the member sets one up (new accounts).
  HealthProfileDto? profile;

  /// Dishes added from outside the catalogue (fridge scan, typed in), by id.
  final Map<String, RecipeDto> added = {};

  /// "Chỉnh thực đơn với AI" proposals by id.
  final Map<String, _Proposal> proposals = {};

  /// Weigh-ins, newest first.
  final List<BodyMeasurementDto> measurements;
  int measurementSeq = 0;
}
