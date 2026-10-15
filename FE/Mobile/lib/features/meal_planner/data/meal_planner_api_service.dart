// lib/features/meal_planner/data/meal_planner_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/formatters.dart';
import '../domain/entities/meal_plan.dart';
import 'mock_meal_planner_repository.dart';
import 'models/health_profile_model.dart';
import 'models/meal_plan_model.dart';

/// Contract with the ASP.NET Core API. The UI only ever sees this interface.
abstract interface class MealPlannerApiService {
  Future<HealthProfileDto> getHealthProfile();

  /// `null` when the user has no plan for the current week (HTTP 404).
  Future<MealPlanDto?> getCurrentMealPlan();

  Future<MealPlanDto> generateMealPlan({required DateTime startDate});

  /// 3 alternatives within ±10 % kcal that avoid the user's allergens.
  Future<List<RecipeDto>> getSwapSuggestions({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  });

  /// Returns the updated day (server recalculates totals).
  Future<MealPlanDayDto> swapMeal({
    required String planId,
    required SwapMealRequestDto request,
  });
}

class RemoteMealPlannerApiService implements MealPlannerApiService {
  RemoteMealPlannerApiService(this._dio);

  final Dio _dio;

  @override
  Future<HealthProfileDto> getHealthProfile() => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.healthProfile);
        return HealthProfileDto.fromJson(res.data!);
      });

  @override
  Future<MealPlanDto?> getCurrentMealPlan() => guardApi(() async {
        try {
          final res = await _dio
              .get<Map<String, dynamic>>(ApiEndpoints.currentMealPlan);
          return MealPlanDto.fromJson(res.data!);
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return null;
          rethrow;
        }
      });

  @override
  Future<MealPlanDto> generateMealPlan({required DateTime startDate}) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.generateMealPlan,
          data: {'startDate': toApiDate(startDate)},
          // Generation can take 10–20 s on the server.
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
        return MealPlanDto.fromJson(res.data!);
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
            'limit': 3
          },
        );
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RecipeDto.fromJson)
            .toList();
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
        return MealPlanDayDto.fromJson(res.data!);
      });
}

/// Swaps Mock ↔ Remote with `--dart-define=USE_MOCK_DATA=false`.
final mealPlannerApiProvider = Provider<MealPlannerApiService>((ref) {
  if (Env.useMockData) return MockMealPlannerRepository();
  return RemoteMealPlannerApiService(ref.watch(dioProvider));
});

/// Allergies shared with other features (scanner, chat context).
final userAllergiesProvider = FutureProvider<List<String>>((ref) async {
  final profile = await ref.watch(mealPlannerApiProvider).getHealthProfile();
  return profile.allergies;
});
