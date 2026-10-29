// lib/features/recipe/data/mock_recipe_community_repository.dart
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/mock_auth_db.dart';
import '../../../core/session/user_role.dart';
import '../../../core/utils/mock_delay.dart';
import '../../meal_planner/data/mock/mock_recipe_book.dart';
import '../domain/entities/recipe_review.dart';
import '../domain/recipe_customization.dart';
import 'mock/recipe_mock_data.dart';
import 'models/recipe_detail_model.dart';
import 'models/recipe_review_model.dart';
import 'models/recipe_variant_model.dart';
import 'recipe_community_api_service.dart';

class _StoredReview {
  _StoredReview({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.rating,
    required this.createdAt,
    this.isVerifiedChef = false,
    this.content,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String authorName;
  final bool isVerifiedChef;
  int rating;
  String? content;
  final DateTime createdAt;
  DateTime? updatedAt;

  RecipeReview toEntity() => RecipeReview(
        id: id,
        rating: rating,
        content: content,
        authorId: userId,
        authorName: authorName,
        isVerifiedChef: isVerifiedChef,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// In-memory state of the recipe community features, kept for the app
/// session: reviews (seeded on `l5`, `b1`, `menu_1`) and private notes
/// (none seeded). Saved variants live in [MockRecipeBook] (they are recipes
/// in "Công thức của tôi"), so `MockMealPlannerRepository.reset` clears them.
abstract final class MockRecipeCommunityStore {
  static int _variantCount = 0;
  static int _seq = 0;
  static final Map<String, List<_StoredReview>> _reviews = _seedReviews();

  /// recipe id → user id → note.
  static final Map<String, Map<String, RecipeNote>> _notes = {};

  /// Variants saved since the last [reset] (tests).
  static int get variantCount => _variantCount;

  /// Back to the seeds (tests).
  @visibleForTesting
  static void reset() {
    _variantCount = 0;
    _seq = 0;
    _reviews
      ..clear()
      ..addAll(_seedReviews());
    _notes.clear();
  }

  /// Average (1 decimal, `null` without reviews) and count of a recipe's
  /// ratings, as `GET /recipes/{id}` returns them.
  static ({double? average, int count}) ratingOf(String recipeId) {
    final all = _reviews[recipeId] ?? const <_StoredReview>[];
    return (average: _average(all), count: all.length);
  }

  static double? _average(List<_StoredReview> all) {
    if (all.isEmpty) return null;
    final sum = all.fold<int>(0, (s, r) => s + r.rating);
    return double.parse((sum / all.length).toStringAsFixed(1));
  }

  static Map<String, List<_StoredReview>> _seedReviews() {
    final now = DateTime.now();
    DateTime ago(int days, [int hours = 0]) =>
        now.subtract(Duration(days: days, hours: hours));
    var n = 0;
    _StoredReview seed(String recipeId, String userId, String name, int rating,
            String? content, DateTime at,
            {bool chef = false, DateTime? edited}) =>
        _StoredReview(
          id: 'rv_${recipeId}_${++n}',
          userId: userId,
          authorName: name,
          isVerifiedChef: chef,
          rating: rating,
          content: content,
          createdAt: at,
          updatedAt: edited,
        );
    return {
      'l5': [
        seed('l5', 'u_chef_tam', 'Lê Quang Tâm', 5,
            'Riêu nấm nhẹ mà vẫn thơm, cả nhà khen.', ago(2),
            chef: true),
        seed(
            'l5',
            'u_seed_hoang_nam',
            'Hoàng Nam',
            5,
            'Nước dùng ngọt thanh từ củ cải và bắp, giống bún riêu ngoài hàng.',
            ago(4)),
        seed('l5', 'u_seed_thao_vy', 'Thảo Vy', 4,
            'Ngon, mình giảm bớt mắm ruốc để bé ăn được.', ago(6),
            edited: ago(5)),
        seed('l5', 'u_seed_ngoc_tram', 'Ngọc Trâm', 5, null, ago(9)),
        seed('l5', 'u_seed_gia_han', 'Gia Hân', 4,
            'Lần sau sẽ thêm nấm rơm cho riêu mềm hơn.', ago(14)),
      ],
      'b1': [
        seed('b1', 'u_seed_thao_vy', 'Thảo Vy', 5,
            'Bữa sáng no lâu, ngâm hạt chia qua đêm là chuẩn.', ago(3)),
        seed('b1', 'u_seed_hoang_nam', 'Hoàng Nam', 4,
            'Ngon nhưng hơi ngọt, lần sau mình bớt trái cây.', ago(8)),
      ],
      'menu_1': [
        seed('menu_1', 'u_seed_gia_han', 'Gia Hân', 4,
            'Chiên đậu hũ vàng trước rồi mới xào thì không bị nát.', ago(5)),
      ],
    };
  }
}

/// Behaves like the server for saved customizations
/// (`POST /recipes/{id}/variants`: validates the changes, recomputes the
/// figures with the same rules as the recipe page preview and stores a
/// private recipe), reviews and private notes.
///
/// Mock triggers: `#fail` in a variant name, a review's text or a note
/// → 503.
class MockRecipeCommunityRepository implements RecipeCommunityApiService {
  MockRecipeCommunityRepository({this.userId});

  /// Signed-in user; `null` for guests.
  final String? userId;

  static const _unauthorized =
      ApiException(message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
  static const _notFound = ApiException(
      message: 'Không tìm thấy công thức.', statusCode: 404, code: 'not_found');

  String _requireUser() => userId ?? (throw _unauthorized);

  static Map<String, Object?> _requireRecipe(String recipeId) =>
      mockRecipeDetail(recipeId) ?? (throw _notFound);

  // --------------------------------------------------------------- variants --

  @override
  Future<RecipeDetailDto> createVariant(
      String recipeId, CreateVariantRequestDto request) async {
    await mockDelay(700);
    final owner = _requireUser();
    final json = _requireRecipe(recipeId);
    if (validateVariantName(request.name) case final message?) {
      throw ApiException(
          message: message, statusCode: 400, code: 'invalid_name');
    }
    if (request.name.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa lưu được công thức. Thử lại nhé.', statusCode: 503);
    }
    final base =
        RecipeDetailDto.fromJson(Map<String, dynamic>.from(json)).toEntity();
    final choices = request.choices;
    if (validateCustomization(base, choices) case final error?) {
      throw ApiException(
          message: error.message, statusCode: 400, code: error.code);
    }
    if (!choices.isModified) {
      throw const ApiException(
          message: 'Chưa có thay đổi nào để lưu.',
          statusCode: 400,
          code: 'no_changes');
    }

    final custom = CustomizedRecipe(base, choices);
    final energy = custom.energy;
    double? grams(double? v) => v?.roundToDouble();
    final row = MockRecipeBook.addUserRecipe(
      userId: owner,
      userName: _author(owner).name,
      recipe: {
        'name': request.name.trim(),
        'caloriesCache': energy.shown,
        'proteinG': grams(energy.proteinG),
        'carbsG': grams(energy.carbsG),
        'fatG': grams(energy.fatG),
        'fiberG': grams(energy.fiberG),
        'allergens': custom.allergens,
        'dietTags': <String>[],
        'prepMinutes': base.prepMinutes,
        'imageUrl': base.imageUrl,
        'servings': base.baseServings,
        'basedOnRecipeId': base.id,
        'basedOnName': base.name,
        'customizations': [
          for (final c in custom.changeNotes()) recipeChangeNoteToJson(c),
        ],
        'nutritionEstimated': energy.unknown.isNotEmpty,
        'ingredients': [
          for (final i in custom.variantRows()) recipeIngredientToJson(i),
        ],
        'instructions': base.instructions,
      },
    );
    MockRecipeCommunityStore._variantCount++;
    return RecipeDetailDto.fromJson(Map<String, dynamic>.from(row));
  }

  // ---------------------------------------------------------------- reviews --

  /// Public recipes only: a member's or chef's recipe (and every variant)
  /// is private → 404.
  static Map<String, Object?> _requirePublic(String recipeId) {
    final json = _requireRecipe(recipeId);
    if (json['createdBy'] != null) {
      throw const ApiException(
          message: 'Công thức riêng tư không có đánh giá.',
          statusCode: 404,
          code: 'private_recipe');
    }
    return json;
  }

  static List<_StoredReview> _reviewsOf(String recipeId) =>
      MockRecipeCommunityStore._reviews[recipeId] ??= [];

  static Map<String, Object?> _summaryJson(List<_StoredReview> all) => {
        'averageRating': MockRecipeCommunityStore._average(all),
        'ratingCount': all.length,
      };

  @override
  Future<RecipeReviewsPageDto> getReviews(String recipeId,
      {String? cursor, int limit = recipeReviewsPageSize}) async {
    await mockDelay(400);
    _requirePublic(recipeId);
    final all = [..._reviewsOf(recipeId)]..sort((a, b) {
        // Newest first; ties in a fixed order so pages never overlap.
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    final me = userId;
    final mine =
        me == null ? null : all.where((r) => r.userId == me).firstOrNull;
    final others = [
      for (final r in all)
        if (r.userId != me) r
    ];
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final size = limit.clamp(1, 50);
    final next = offset + size;
    return RecipeReviewsPageDto.fromJson({
      'recipeId': recipeId,
      ..._summaryJson(all),
      'distribution': {
        for (var s = 5; s >= 1; s--)
          '$s': all.where((r) => r.rating == s).length,
      },
      'myReview': mine == null ? null : recipeReviewToJson(mine.toEntity()),
      'items': [
        for (final r in others.skip(offset).take(size))
          recipeReviewToJson(r.toEntity()),
      ],
      'nextCursor': next < others.length ? '$next' : null,
    });
  }

  @override
  Future<ReviewWriteResultDto> upsertMyReview(
      String recipeId, UpsertReviewRequestDto request) async {
    await mockDelay(600);
    final me = _requireUser();
    final json = _requireRecipe(recipeId);
    if (json['createdBy'] == me) {
      throw const ApiException(
          message: 'Bạn không thể đánh giá công thức của chính mình.',
          statusCode: 403,
          code: 'own_recipe');
    }
    _requirePublic(recipeId);
    if (validateReviewRating(request.rating) case final message?) {
      throw ApiException(
          message: message, statusCode: 400, code: 'invalid_rating');
    }
    final content = request.content?.trim();
    if (validateReviewContent(content) case final message?) {
      throw ApiException(
          message: message, statusCode: 400, code: 'invalid_content');
    }
    if (content != null && content.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa gửi được đánh giá. Thử lại nhé.', statusCode: 503);
    }

    final all = _reviewsOf(recipeId);
    final text = content == null || content.isEmpty ? null : content;
    var review = all.where((r) => r.userId == me).firstOrNull;
    if (review == null) {
      final author = _author(me);
      review = _StoredReview(
        id: 'rv_${recipeId}_u${++MockRecipeCommunityStore._seq}',
        userId: me,
        authorName: author.name,
        isVerifiedChef: author.chef,
        rating: request.rating,
        content: text,
        createdAt: DateTime.now(),
      );
      all.add(review);
    } else {
      review
        ..rating = request.rating
        ..content = text
        ..updatedAt = DateTime.now();
    }
    return ReviewWriteResultDto.fromJson({
      'review': recipeReviewToJson(review.toEntity()),
      ..._summaryJson(all),
    });
  }

  @override
  Future<RatingTotalsDto> deleteMyReview(String recipeId) async {
    await mockDelay(500);
    final me = _requireUser();
    _requirePublic(recipeId);
    final all = _reviewsOf(recipeId);
    final before = all.length;
    all.removeWhere((r) => r.userId == me);
    if (all.length == before) {
      throw const ApiException(
          message: 'Bạn chưa đánh giá công thức này.', statusCode: 404);
    }
    return RatingTotalsDto.fromJson(_summaryJson(all));
  }

  // ------------------------------------------------------------------ notes --

  static Map<String, RecipeNote> _notesOf(String recipeId) =>
      MockRecipeCommunityStore._notes[recipeId] ??= {};

  static Map<String, Object?> _noteJson(RecipeNote n) => {
        'recipeId': n.recipeId,
        'content': n.content,
        'updatedAt': n.updatedAt.toUtc().toIso8601String(),
      };

  @override
  Future<RecipeNoteDto?> getMyNote(String recipeId) async {
    await mockDelay(400);
    final me = _requireUser();
    // The server answers 404 when there is no note (or no recipe): none.
    final note = MockRecipeCommunityStore._notes[recipeId]?[me];
    return note == null
        ? null
        : RecipeNoteDto.fromJson(Map<String, dynamic>.from(_noteJson(note)));
  }

  @override
  Future<RecipeNoteDto?> saveMyNote(String recipeId, String content) async {
    await mockDelay(500);
    final me = _requireUser();
    _requireRecipe(recipeId);
    final text = content.trim();
    if (validateNoteContent(text) case final message?) {
      throw ApiException(
          message: message, statusCode: 400, code: 'invalid_content');
    }
    if (text.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa lưu được ghi chú. Thử lại nhé.', statusCode: 503);
    }
    final notes = _notesOf(recipeId);
    if (text.isEmpty) {
      notes.remove(me);
      return null;
    }
    final note = RecipeNote(
        recipeId: recipeId, content: text, updatedAt: DateTime.now());
    notes[me] = note;
    return RecipeNoteDto.fromJson(Map<String, dynamic>.from(_noteJson(note)));
  }

  @override
  Future<void> deleteMyNote(String recipeId) async {
    await mockDelay(400);
    final me = _requireUser();
    _requireRecipe(recipeId);
    _notesOf(recipeId).remove(me);
  }

  /// Display name and verified-chef flag of an account (seeded or
  /// registered in this run).
  static ({String name, bool chef}) _author(String id) {
    final user = MockAuthDb.byId(id);
    return (
      name: user?.fullName ?? 'Thành viên VeganLife',
      chef: user?.role == UserRole.chef,
    );
  }
}
