// lib/features/meal_planner/data/meal_planner_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/mock_persona.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../recipe/data/recipe_catalog.dart';
import '../domain/entities/health_profile.dart';
import '../domain/entities/meal_plan.dart';
import 'mock/mock_recipe_book.dart';
import 'mock_meal_planner_repository.dart';
import 'models/body_measurement_model.dart';
import 'models/health_profile_model.dart';
import 'models/meal_plan_model.dart';

/// Contract with the ASP.NET Core API. The UI only ever sees this interface.
abstract interface class MealPlannerApiService {
  /// `null` when the member hasn't set a health profile up yet (HTTP 404,
  /// e.g. a new account): the app then asks them to set one up and never
  /// borrows anyone else's.
  Future<HealthProfileDto?> getHealthProfile();

  /// Creates or replaces the profile; returns it with the server-recomputed
  /// `bmi`.
  Future<HealthProfileDto> updateHealthProfile(
      UpdateHealthProfileRequestDto request);

  /// Weigh-ins (`health_metric_logs`), newest first, at most [limit]
  /// (≤ 100). Profile saves that change the weight log one too.
  Future<List<BodyMeasurementDto>> getBodyMeasurements({int limit = 100});

  /// "Cập nhật cân nặng": logs a weigh-in at the saved height and returns
  /// it with the recomputed profile (BMI, BMR, TDEE; the current week's
  /// targets follow). 404 without a health profile.
  Future<LogMeasurementResultDto> logBodyMeasurement(
      LogMeasurementRequestDto request);

  /// `null` when the user has no plan for the current week (HTTP 404).
  Future<MealPlanDto?> getCurrentMealPlan();

  /// AI plan for the week, avoiding the member's allergens. [fromPantry]
  /// builds it around the vegan foods in the fridge (`user_ingredients`).
  Future<MealPlanDto> generateMealPlan(
      {required DateTime startDate, bool fromPantry = false});

  /// "Tự lên thực đơn": a week with every slot empty, filled by hand.
  Future<MealPlanDto> createEmptyMealPlan({required DateTime startDate});

  /// 3 alternatives within ±10 % kcal that avoid the user's allergens.
  Future<List<RecipeDto>> getSwapSuggestions({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  });

  /// Puts a recipe by id in a slot (AI suggestion, own recipe, chef
  /// suggestion). Returns the updated day (server recalculates totals).
  Future<MealPlanDayDto> swapMeal({
    required String planId,
    required SwapMealRequestDto request,
  });

  /// Puts a dish from outside the catalogue (fridge-scan suggestion, a dish
  /// typed in by hand) into a slot of the current plan, replacing that slot's
  /// meal. Returns the updated day; the dish's allergens are flagged, not
  /// blocked (like the planner).
  Future<MealPlanDayDto> addMealToCurrentPlan(AddMealRequestDto request);

  /// Many [addMealToCurrentPlan] dishes in one request (a delivered chef
  /// plan: "Áp dụng kế hoạch vào Thực đơn"). Each replaces its slot; dishes
  /// dated outside the current week are skipped, not errors. Any other
  /// failure applies none of them.
  Future<AddMealsResultDto> addMealsToCurrentPlan(
      List<AddMealRequestDto> requests);

  /// Empties one slot ("Bỏ món"). Returns the updated day.
  Future<MealPlanDayDto> removeMeal({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  });

  /// "Công thức của tôi": recipes the member wrote (`recipes.created_by`).
  Future<List<RecipeDto>> getMyRecipes();

  Future<RecipeDto> createMyRecipe(CreateRecipeRequestDto request);

  /// Dishes chefs suggested to this member ("Từ chuyên gia"); may be empty.
  Future<List<ChefSuggestionDto>> getChefSuggestions();

  /// "Chỉnh thực đơn với AI": a proposal (reply + changes), nothing applied
  /// yet. Every proposed dish is vegan and avoids the member's allergies.
  Future<PlanAdjustmentDto> adjustPlan(AdjustPlanRequestDto request);

  /// Applies the [changeIds] the member kept; returns the updated plan.
  Future<MealPlanDto> applyAdjustment({
    required String proposalId,
    required List<String> changeIds,
  });
}

/// The real BE, with the app working around what it lacks: see the plan's §7.
class RemoteMealPlannerApiService implements MealPlannerApiService {
  RemoteMealPlannerApiService(
    this._dio, {
    this.userId,
    this.personaId,
    DateTime Function() clock = DateTime.now,
    PlanItemSnapshots? snapshots,
    RecipeCatalog Function()? catalog,
  })  : _clock = clock,
        _snapshots = snapshots ?? PlanItemSnapshots(),
        _catalog = catalog;

  final Dio _dio;

  /// The signed-in member: the BE doesn't return `createdBy` on their recipes.
  final String? userId;

  /// Who the member is in the mock stores still used in a hybrid build.
  final String? personaId;
  final DateTime Function() _clock;
  final PlanItemSnapshots _snapshots;
  final RecipeCatalog Function()? _catalog;

  MealPlanDto _plan(Map<String, dynamic> json) {
    _snapshots.registerPlan(json);
    return MealPlanDto.fromJson(json);
  }

  MealPlanDayDto _day(Map<String, dynamic> json) {
    _snapshots.registerDay(json);
    return MealPlanDayDto.fromJson(json);
  }

  List<T> _list<T>(Object? data, T Function(Map<String, dynamic> json) parse) =>
      data is List<Object?>
          ? data.whereType<Map<String, dynamic>>().map(parse).toList()
          : const [];

  @override
  Future<HealthProfileDto?> getHealthProfile() => guardApi(() async {
        try {
          final res =
              await _dio.get<Map<String, dynamic>>(ApiEndpoints.healthProfile);
          return HealthProfileDto.fromJson(res.data!);
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return null;
          rethrow;
        }
      });

  @override
  Future<HealthProfileDto> updateHealthProfile(
          UpdateHealthProfileRequestDto request) =>
      guardApi(() async {
        // A PUT resets what it doesn't get, so missing fields keep their
        // saved value. `null` for a first profile.
        final saved = request.gender == null ||
                request.birthYear == null ||
                request.activityLevel == null ||
                request.mealPattern == null
            ? await getHealthProfile()
            : null;
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.healthProfile,
            data: request.toBackendJson(saved: saved));
        return HealthProfileDto.fromJson(res.data!);
      });

  @override
  Future<List<BodyMeasurementDto>> getBodyMeasurements({int limit = 100}) =>
      guardApi(() async {
        try {
          final res = await _dio.get<List<dynamic>>(ApiEndpoints.healthMetrics,
              queryParameters: {'limit': limit});
          return _list(res.data, BodyMeasurementDto.fromJson);
        } on DioException catch (e) {
          // No health profile yet: no history either.
          if (e.response?.statusCode == 404) return const [];
          rethrow;
        }
      });

  /// The BE has no POST here: saving the profile with the new weight logs the
  /// row, but only when the weight really changed. A row it didn't add comes
  /// back as a `local_` one that isn't part of the history.
  @override
  Future<LogMeasurementResultDto> logBodyMeasurement(
          LogMeasurementRequestDto request) =>
      guardApi(() async {
        final saved = await getHealthProfile();
        if (saved == null) {
          throw const ApiException(
              message: 'Bạn chưa tạo hồ sơ sức khỏe.', statusCode: 404);
        }
        final before = (await getBodyMeasurements(limit: 1)).firstOrNull;
        final res = await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.healthProfile,
          data: UpdateHealthProfileRequestDto(
            heightCm: saved.heightCm,
            weightKg: request.weightKg,
            goal: HealthGoal.fromApi(saved.goal),
            allergies: saved.allergies,
            dietaryRestrictions: saved.dietaryRestrictions,
          ).toBackendJson(saved: saved),
        );
        final profile = HealthProfileDto.fromJson(res.data!);
        final latest = (await getBodyMeasurements(limit: 1)).firstOrNull;
        final isNew = latest != null &&
            (latest.weightKg - request.weightKg).abs() < 0.01 &&
            (before == null || latest.loggedAt.isAfter(before.loggedAt));
        final now = _clock();
        return LogMeasurementResultDto(
          measurement: isNew
              ? latest
              : BodyMeasurementDto(
                  id: 'local_${now.millisecondsSinceEpoch}',
                  weightKg: request.weightKg,
                  heightCm: profile.heightCm,
                  bmi: profile.bmi,
                  loggedAt: now,
                  source: 'check_in',
                ),
          profile: profile,
        );
      });

  @override
  Future<MealPlanDto?> getCurrentMealPlan() => guardApi(() async {
        try {
          final res = await _dio
              .get<Map<String, dynamic>>(ApiEndpoints.currentMealPlan);
          // The BE falls back to the latest old plan, and its week is in UTC.
          final plan = _plan(res.data!);
          return isSameDay(plan.startDate, startOfWeek(_clock())) ? plan : null;
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return null;
          rethrow;
        }
      });

  @override
  Future<MealPlanDto> generateMealPlan(
          {required DateTime startDate, bool fromPantry = false}) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.generateMealPlan,
          data: {
            'startDate': toApiDate(startDate),
            if (fromPantry) 'usePantry': true,
          },
          // Generation can take 10–20 s on the server.
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
        return _plan(res.data!);
      });

  @override
  Future<MealPlanDto> createEmptyMealPlan({required DateTime startDate}) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.mealPlans,
          data: {'startDate': toApiDate(startDate), 'empty': true},
        );
        return _plan(res.data!);
      });

  @override
  Future<List<RecipeDto>> getSwapSuggestions({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  }) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
          ApiEndpoints.swapSuggestions(planId),
          queryParameters: {
            'date': toApiDate(date),
            'slot': slot.apiValue,
            // One more than the sheet shows: the BE includes the current dish.
            'limit': 4
          },
        );
        return _list(res.data, RecipeDto.fromJson);
      });

  @override
  Future<MealPlanDayDto> swapMeal({
    required String planId,
    required SwapMealRequestDto request,
  }) =>
      guardApi(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          ApiEndpoints.swapMeal(planId),
          data: request.toJson(),
        );
        return _day(res.data!);
      });

  @override
  Future<MealPlanDayDto> addMealToCurrentPlan(AddMealRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.currentMealPlanMeals,
          data: request.toJson(),
        );
        return _day(res.data!);
      });

  @override
  Future<AddMealsResultDto> addMealsToCurrentPlan(
          List<AddMealRequestDto> requests) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.currentMealPlanMealsBatch,
          data: {'meals': requests.map((r) => r.toJson()).toList()},
        );
        final days = res.data!['days'];
        if (days is List<Object?>) {
          days
              .whereType<Map<String, dynamic>>()
              .forEach(_snapshots.registerDay);
        }
        return AddMealsResultDto.fromJson(res.data!);
      });

  @override
  Future<MealPlanDayDto> removeMeal({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  }) =>
      guardApi(() async {
        final res = await _dio.delete<Map<String, dynamic>>(
          ApiEndpoints.swapMeal(planId),
          queryParameters: {'date': toApiDate(date), 'slot': slot.apiValue},
        );
        return _day(res.data!);
      });

  RecipeDto _myRecipe(Map<String, dynamic> json) => RecipeDto.fromJson({
        ...json,
        if (userId != null) 'createdBy': userId,
      }).withSource(MealSource.userRecipe.apiValue);

  /// The member's real recipes, plus the variants they saved from a mock
  /// recipe (those stay in the mock store).
  @override
  Future<List<RecipeDto>> getMyRecipes() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myRecipes);
        final persona = personaId;
        return [
          if (persona != null &&
              BackendModules.isMock(BackendModule.recipeSocial))
            for (final row in MockRecipeBook.userRecipes(persona))
              RecipeDto.fromJson(row)
                  .withSource(MealSource.userRecipe.apiValue),
          ..._list(res.data, _myRecipe),
        ];
      });

  @override
  Future<RecipeDto> createMyRecipe(CreateRecipeRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(ApiEndpoints.recipes,
            data: request.toBackendJson());
        _catalog?.call().invalidate();
        return _myRecipe(res.data!);
      });

  /// Chefs' plans are still mock while bookings are, and so are their dishes.
  @override
  Future<List<ChefSuggestionDto>> getChefSuggestions() async {
    if (BackendModules.isMock(BackendModule.bookings)) {
      final persona = personaId;
      if (persona == null) return const [];
      return MockRecipeBook.chefSuggestions(persona)
          .map((s) => ChefSuggestionDto.fromJson(Map<String, dynamic>.from(s)))
          .toList();
    }
    return guardApi(() async {
      final res = await _dio.get<List<dynamic>>(ApiEndpoints.chefSuggestions);
      return _list(res.data, ChefSuggestionDto.fromJson);
    });
  }

  @override
  Future<PlanAdjustmentDto> adjustPlan(AdjustPlanRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.mealPlanAdjust,
          data: request.toJson(),
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
        return PlanAdjustmentDto.fromJson(res.data!);
      });

  @override
  Future<MealPlanDto> applyAdjustment({
    required String proposalId,
    required List<String> changeIds,
  }) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.mealPlanAdjustApply(proposalId),
          data: {'changeIds': changeIds},
        );
        return MealPlanDto.fromJson(res.data!);
      });
}

/// Signed-in user id the planner, the pantry and the scanner tray are keyed
/// on (`null` for guests). Changing account rebuilds everything that watches
/// it, so one member never sees another's plan. Bare unit-test containers
/// have no session (no SharedPreferences) and read as a guest.
final plannerUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(
        sessionControllerProvider.select((s) => s.isGuest ? null : s.userId));
  } catch (_) {
    return null;
  }
});

/// Who the member is in the mock stores: themselves with mock auth; a real
/// account acts as a seeded one (`mockPersonaId`) while the module it uses is
/// still mock. `null` for guests.
final plannerPersonaIdProvider = Provider<String?>((ref) {
  final userId = ref.watch(plannerUserIdProvider);
  if (userId == null || BackendModules.isMock(BackendModule.auth)) {
    return userId;
  }
  try {
    return ref.watch(sessionControllerProvider.select(mockPersonaId));
  } catch (_) {
    return userId;
  }
});

/// "Now" for the planner: which week is current and which day is today.
/// Tests pin it so weekday-dependent screens are deterministic.
final plannerClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Mock or real by `BackendModule.planner`. Rebuilt on account changes, so the
/// controllers that watch it refetch.
final mealPlannerApiProvider = Provider<MealPlannerApiService>((ref) {
  final persona = ref.watch(plannerPersonaIdProvider);
  final clock = ref.watch(plannerClockProvider);
  if (BackendModules.isMock(BackendModule.planner)) {
    return MockMealPlannerRepository(userId: persona, clock: clock);
  }
  return RemoteMealPlannerApiService(
    ref.watch(dioProvider),
    userId: ref.watch(plannerUserIdProvider),
    personaId: persona,
    clock: clock,
    snapshots: ref.watch(planItemSnapshotsProvider),
    catalog: () => ref.read(recipeCatalogProvider),
  );
});

/// Allergies shared with other features (scanner, chat context, recipes);
/// none until the member sets a health profile up.
final userAllergiesProvider = FutureProvider<List<String>>((ref) async {
  final profile = await ref.watch(mealPlannerApiProvider).getHealthProfile();
  return profile?.allergies ?? const [];
});
