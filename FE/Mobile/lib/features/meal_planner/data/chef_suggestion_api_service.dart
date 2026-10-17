// lib/features/meal_planner/data/chef_suggestion_api_service.dart
//
// How dishes reach the member's Thực đơn › Chọn món › "Từ chuyên gia"
// (`MealPlannerApiService.getChefSuggestions`).
//
// Since the chef business moved to N-day meal-plan bookings (plan D15b),
// a chef no longer suggests single dishes to "clients": the server turns
// every plan day the chef sends (`POST /chefs/me/bookings/{id}/plan/days/
// {dayIndex}/send` or `/plan/send`) into "Từ chuyên gia" rows with the slot,
// the target date and the chef's name. There is no client endpoint for it
// any more (`/chefs/me/clients/{userId}/suggestions` is obsolete).
//
// This file is the mock side of that delivery: [deliverChefPlanMeal] is
// what the mock booking server calls when a day is sent, and
// [MockChefSuggestionRepository] keeps the old single-dish entry point for
// tests and seeds. Both write through [MockRecipeBook], the store the
// member's planner reads.
//
// A delivered row (MockRecipeBook / GET /meal-plans/chef-suggestions):
// { "id": "sg_…", "chefId": "u_chef_tam", "chefName": "Lê Quang Tâm", "note": "…",
//   "slot": "dinner", "targetDate": "2026-10-17", "createdAt": "…",
//   "recipe": { "id": "cs_…", "name": "…", "caloriesCache": 480,
//               "ingredients": [{ "name": "…" }], … } }
// Deprecated table `chef_meal_suggestions`; the BE derives these rows from
// `booking_plan_days` / `booking_plan_meals`.
import '../../../core/network/api_exception.dart';
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

/// Single-dish delivery (mock and tests only; see the file header).
abstract interface class ChefSuggestionApiService {
  /// What the signed-in chef delivered to [userId], newest first.
  Future<List<SentSuggestionDto>> sentTo(String userId);

  /// Puts a dish in [userId]'s "Từ chuyên gia" list.
  Future<SentSuggestionDto> send(String userId, SendChefSuggestionDto request);
}

/// Delivers one meal of a sent booking plan day to the member's "Từ chuyên
/// gia" list (D15b): [slot] and [date] become the suggestion's slot and
/// target date, [chefName] its source. Allergens are inferred from the name
/// and [ingredients] like the server does, so the planner warns about
/// them. Returns the stored row.
Map<String, Object?> deliverChefPlanMeal({
  required String memberId,
  required String chefUserId,
  required String chefName,
  required MealSlot slot,
  required DateTime date,
  required String name,
  int? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  List<String> ingredients = const [],
  String? instructions,
  String? note,
}) {
  final cleanIngredients = [
    for (final i in ingredients)
      if (i.trim().isNotEmpty) i.trim(),
  ];
  return MockRecipeBook.addChefSuggestion(
    userId: memberId,
    chefId: chefUserId,
    chefName: chefName,
    note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    slot: slot.apiValue,
    targetDate: toApiDate(date),
    recipe: {
      'name': name.trim(),
      // Only what the chef entered: no "Đạm 0 g" for unknown macros.
      if (calories != null) 'caloriesCache': calories,
      if (proteinG != null) 'proteinG': proteinG,
      if (carbsG != null) 'carbsG': carbsG,
      if (fatG != null) 'fatG': fatG,
      'allergens':
          MockMealPlannerRepository.detectAllergens(name, cleanIngredients)
              .toList(),
      'dietTags': <String>[],
      'servings': 1,
      'ingredients': [
        for (final i in cleanIngredients)
          {'name': i, 'quantity': null, 'unit': ''},
      ],
      'instructions': instructions?.trim() ?? '',
    },
  );
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
