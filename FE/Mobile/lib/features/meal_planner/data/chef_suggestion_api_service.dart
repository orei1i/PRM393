// lib/features/meal_planner/data/chef_suggestion_api_service.dart
//
// Chef side of "Từ chuyên gia": a chef suggests a dish to a member who uses
// one of their packages; the member then finds it in Thực đơn › Chọn món ›
// Từ chuyên gia (`MealPlannerApiService.getChefSuggestions`).
//
// POST /chefs/me/clients/{userId}/suggestions          (role Chef only)
// { "name": "Bún gạo lứt xào rau củ", "calories": 480,
//   "ingredients": ["Bún gạo lứt", "Cải thìa"], "note": "…",
//   "slot": "dinner" | null, "targetDate": "2026-10-17" | null }
// → SentSuggestionDto (201). 400 on invalid input, 403 for non-chefs, 404
// when the member has no package with this chef.
// GET /chefs/me/clients/{userId}/suggestions → [SentSuggestionDto]
// { "id": "sg_…", "userId": 7, "createdAt": "…", "note": "…",
//   "slot": "dinner", "targetDate": "2026-10-17",
//   "recipe": { "id": "cs_…", "name": "…", "caloriesCache": 480,
//               "ingredients": [{ "name": "…" }], … } }
// Proposed table `chef_meal_suggestions (id, chef_id, user_id, recipe_id, note,
// slot, target_date, created_at)`; the dish itself is a `recipes` row
// created by the chef.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/session/user_role.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json_helpers.dart';
import '../../../core/utils/mock_delay.dart';
import '../domain/entities/meal_plan.dart';
import 'mock/mock_recipe_book.dart';
import 'mock_meal_planner_repository.dart';

/// Limits of the "Đề xuất món" form, mirrored by the server (400).
abstract final class SuggestionRules {
  static const nameMin = 3;
  static const nameMax = 120;
  static const caloriesMin = 50;
  static const caloriesMax = 3000;
  static const noteMax = 300;
  static const ingredientsMax = 30;

  /// `null` when valid, otherwise the first problem (Vietnamese).
  static String? validate(SendChefSuggestionDto r) {
    final name = r.name.trim();
    if (name.length < nameMin || name.length > nameMax) {
      return 'Tên món cần từ $nameMin đến $nameMax ký tự.';
    }
    final kcal = r.calories;
    if (kcal != null && (kcal < caloriesMin || kcal > caloriesMax)) {
      return 'Năng lượng cần từ $caloriesMin đến ${formatInt(caloriesMax)} kcal.';
    }
    if ((r.note?.trim().length ?? 0) > noteMax) {
      return 'Lời nhắn tối đa $noteMax ký tự.';
    }
    if (r.ingredients.length > ingredientsMax) {
      return 'Tối đa $ingredientsMax nguyên liệu.';
    }
    return null;
  }
}

class SendChefSuggestionDto {
  const SendChefSuggestionDto({
    required this.name,
    this.calories,
    this.ingredients = const [],
    this.note,
    this.slot,
    this.targetDate,
  });

  final String name;
  final int? calories;
  final List<String> ingredients;
  final String? note;
  final MealSlot? slot;
  final DateTime? targetDate;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'calories': calories,
        'ingredients': ingredients,
        'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
        'slot': slot?.apiValue,
        'targetDate': targetDate == null ? null : toApiDate(targetDate!),
      };
}

/// A dish this chef suggested to one member.
class SentSuggestionDto {
  const SentSuggestionDto({
    required this.id,
    required this.dishName,
    this.recipeId,
    this.calories,
    this.ingredients = const [],
    this.note,
    this.slot,
    this.targetDate,
    this.createdAt,
  });

  factory SentSuggestionDto.fromJson(Map<String, dynamic> json) {
    final recipe = readMap(json['recipe']);
    final kcal = recipe['caloriesCache'] ?? recipe['calories'];
    return SentSuggestionDto(
      id: json['id']?.toString() ?? '',
      dishName: recipe['name'] as String? ?? json['dishName'] as String? ?? '',
      recipeId: recipe['id']?.toString(),
      calories: kcal == null || readInt(kcal) <= 0 ? null : readInt(kcal),
      ingredients: recipe['ingredients'] is List<Object?>
          ? [
              for (final i in recipe['ingredients'] as List<Object?>)
                if (i is Map<String, dynamic> && i['name'] is String)
                  i['name'] as String
                else if (i is String)
                  i,
            ]
          : const [],
      note: json['note'] as String?,
      slot: json['slot'] is String
          ? MealSlot.fromApi(json['slot'] as String)
          : null,
      targetDate:
          json['targetDate'] == null ? null : readDateTime(json['targetDate']),
      createdAt: readDateTime(json['createdAt']),
    );
  }

  final String id;
  final String dishName;

  /// Opens with `RecipeDetailScreen.route(recipeId)`.
  final String? recipeId;
  final int? calories;
  final List<String> ingredients;
  final String? note;
  final MealSlot? slot;
  final DateTime? targetDate;
  final DateTime? createdAt;
}

abstract interface class ChefSuggestionApiService {
  /// What the signed-in chef suggested to [userId], newest first.
  Future<List<SentSuggestionDto>> sentTo(String userId);

  /// Sends a dish to [userId]'s "Từ chuyên gia" list.
  Future<SentSuggestionDto> send(String userId, SendChefSuggestionDto request);
}

class RemoteChefSuggestionApiService implements ChefSuggestionApiService {
  RemoteChefSuggestionApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<SentSuggestionDto>> sentTo(String userId) => guardApi(() async {
        final res = await _dio
            .get<List<dynamic>>(ApiEndpoints.myChefClientSuggestions(userId));
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SentSuggestionDto.fromJson)
            .toList();
      });

  @override
  Future<SentSuggestionDto> send(
          String userId, SendChefSuggestionDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.myChefClientSuggestions(userId),
            data: request.toJson());
        return SentSuggestionDto.fromJson(res.data!);
      });
}

/// Writes through [MockRecipeBook], the store the member's planner reads,
/// so a suggestion shows up in their "Từ chuyên gia" list after switching
/// accounts. `#fail` in the dish name or the note → 503.
class MockChefSuggestionRepository implements ChefSuggestionApiService {
  MockChefSuggestionRepository({
    required this.chefUserId,
    required this.chefName,
    required this.isChef,
  });

  final String? Function() chefUserId;
  final String Function() chefName;
  final bool Function() isChef;

  String _me() {
    final id = chefUserId();
    if (id == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
    if (!isChef()) {
      throw const ApiException(
          message: 'Chỉ dành cho chuyên gia.',
          statusCode: 403,
          code: 'not_chef');
    }
    return id;
  }

  @override
  Future<List<SentSuggestionDto>> sentTo(String userId) async {
    await mockDelay(400);
    final me = _me();
    return MockRecipeBook.chefSuggestions(userId)
        .where((s) => s['chefId'] == me)
        .map((s) => SentSuggestionDto.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  @override
  Future<SentSuggestionDto> send(
      String userId, SendChefSuggestionDto request) async {
    await mockDelay(700);
    final me = _me();
    final problem = SuggestionRules.validate(request);
    if (problem != null) {
      throw ApiException(message: problem, statusCode: 400, code: 'validation');
    }
    final name = request.name.trim();
    final note = request.note?.trim();
    if ('$name ${note ?? ''}'.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa gửi được đề xuất. Thử lại sau ít phút.',
          statusCode: 503);
    }
    final ingredients = [
      for (final i in request.ingredients)
        if (i.trim().isNotEmpty) i.trim(),
    ];
    final row = MockRecipeBook.addChefSuggestion(
      userId: userId,
      chefId: me,
      chefName: chefName(),
      note: (note?.isEmpty ?? true) ? null : note,
      slot: request.slot?.apiValue,
      targetDate:
          request.targetDate == null ? null : toApiDate(request.targetDate!),
      recipe: {
        'name': name,
        // kcal only when the chef gave it; no macros were entered, so none
        // are stored (the member sees no "Đạm 0 g").
        if (request.calories != null) 'caloriesCache': request.calories,
        // Like the server: allergens inferred from the name + ingredients,
        // so the member's planner warns about them.
        'allergens':
            MockMealPlannerRepository.detectAllergens(name, ingredients)
                .toList(),
        'dietTags': <String>[],
        'servings': 1,
        'ingredients': [
          for (final i in ingredients)
            {'name': i, 'quantity': null, 'unit': ''},
        ],
        'instructions': '',
      },
    );
    return SentSuggestionDto.fromJson(Map<String, dynamic>.from(row));
  }
}

final chefSuggestionApiProvider = Provider<ChefSuggestionApiService>((ref) {
  if (Env.useMockData) {
    return MockChefSuggestionRepository(
      chefUserId: () => ref.read(sessionControllerProvider).userId,
      chefName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Chuyên gia',
      isChef: () =>
          ref.read(sessionControllerProvider).role == UserRole.chef &&
          !ref.read(sessionControllerProvider).isGuest,
    );
  }
  return RemoteChefSuggestionApiService(ref.watch(dioProvider));
});
