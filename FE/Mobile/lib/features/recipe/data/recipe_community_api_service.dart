// lib/features/recipe/data/recipe_community_api_service.dart
//
// Recipe calls that depend on who is signed in: saved customizations,
// reviews (with the caller's own) and private notes. Kept apart from
// `recipeApiProvider`, which stays user-independent so signing in on a
// recipe page never reloads the recipe or resets the cook's preview.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../meal_planner/data/meal_planner_api_service.dart';
import 'mock_recipe_community_repository.dart';
import 'models/recipe_detail_model.dart';
import 'models/recipe_review_model.dart';
import 'models/recipe_variant_model.dart';

/// Reviews per page ("Xem thêm đánh giá").
const recipeReviewsPageSize = 10;

abstract interface class RecipeCommunityApiService {
  /// "Lưu thành công thức của tôi": the server applies the swaps and
  /// removals to recipe [recipeId], recomputes energy, macros and allergens
  /// and stores a private recipe for the caller (in "Công thức của tôi").
  Future<RecipeDetailDto> createVariant(
      String recipeId, CreateVariantRequestDto request);

  /// A page of a public recipe's reviews, newest first, with the summary
  /// and (signed in) the caller's own review. 404 for a private recipe.
  Future<RecipeReviewsPageDto> getReviews(String recipeId,
      {String? cursor, int limit = recipeReviewsPageSize});

  /// Creates or replaces the caller's review (one per member per recipe).
  /// 400 rating / text length, 401, 403 `own_recipe`, 404.
  Future<ReviewWriteResultDto> upsertMyReview(
      String recipeId, UpsertReviewRequestDto request);

  Future<RatingTotalsDto> deleteMyReview(String recipeId);

  /// The caller's private note, or `null` when there is none.
  Future<RecipeNoteDto?> getMyNote(String recipeId);

  /// Saves the note (trimmed, ≤ 2000 chars); an empty one deletes it and
  /// returns `null`.
  Future<RecipeNoteDto?> saveMyNote(String recipeId, String content);

  Future<void> deleteMyNote(String recipeId);
}

class RemoteRecipeCommunityApiService implements RecipeCommunityApiService {
  RemoteRecipeCommunityApiService(this._dio);

  final Dio _dio;

  @override
  Future<RecipeDetailDto> createVariant(
          String recipeId, CreateVariantRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.recipeVariants(recipeId),
          data: request.toJson(),
        );
        return RecipeDetailDto.fromJson(res.data!);
      });

  @override
  Future<RecipeReviewsPageDto> getReviews(String recipeId,
          {String? cursor, int limit = recipeReviewsPageSize}) =>
      guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.recipeReviews(recipeId),
          queryParameters: {
            if (cursor != null) 'cursor': cursor,
            'limit': limit,
          },
        );
        return RecipeReviewsPageDto.fromJson(res.data!);
      });

  @override
  Future<ReviewWriteResultDto> upsertMyReview(
          String recipeId, UpsertReviewRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.recipeMyReview(recipeId),
          data: request.toJson(),
        );
        return ReviewWriteResultDto.fromJson(res.data!);
      });

  @override
  Future<RatingTotalsDto> deleteMyReview(String recipeId) => guardApi(() async {
        final res = await _dio.delete<Map<String, dynamic>>(
            ApiEndpoints.recipeMyReview(recipeId));
        return RatingTotalsDto.fromJson(res.data!);
      });

  @override
  Future<RecipeNoteDto?> getMyNote(String recipeId) async {
    try {
      return await guardApi(() async {
        final res = await _dio
            .get<Map<String, dynamic>>(ApiEndpoints.recipeMyNote(recipeId));
        final data = res.data;
        return data == null ? null : RecipeNoteDto.fromJson(data);
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null; // no note yet
      rethrow;
    }
  }

  @override
  Future<RecipeNoteDto?> saveMyNote(String recipeId, String content) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.recipeMyNote(recipeId),
          data: {'content': content.trim()},
        );
        final data = res.data;
        return data == null ? null : RecipeNoteDto.fromJson(data);
      });

  @override
  Future<void> deleteMyNote(String recipeId) => guardApi(() async {
        await _dio.delete<Object?>(ApiEndpoints.recipeMyNote(recipeId));
      });
}

/// Rebuilt when the account changes (the mock is keyed on the user). The BE has
/// none of this yet: it stays mock, and only mock recipes show it.
final recipeCommunityApiProvider = Provider<RecipeCommunityApiService>((ref) {
  final userId = ref.watch(plannerPersonaIdProvider);
  if (BackendModules.isMock(BackendModule.recipeSocial)) {
    return MockRecipeCommunityRepository(userId: userId);
  }
  return RemoteRecipeCommunityApiService(ref.watch(dioProvider));
});
