// lib/features/recipe/presentation/controllers/recipe_social_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../data/models/recipe_review_model.dart';
import '../../data/recipe_community_api_service.dart';
import '../../domain/entities/recipe_review.dart';

/// The "Đánh giá" tab of a public recipe: summary, the member's own review
/// and the others, page by page.
class RecipeReviewsState {
  const RecipeReviewsState({
    required this.summary,
    this.myReview,
    this.items = const [],
    this.nextCursor,
    this.loadingMore = false,
  });

  final RatingSummary summary;
  final RecipeReview? myReview;

  /// Everyone else's, newest first.
  final List<RecipeReview> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  RecipeReviewsState copyWith({
    RatingSummary? summary,
    RecipeReview? myReview,
    bool clearMyReview = false,
    List<RecipeReview>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
  }) =>
      RecipeReviewsState(
        summary: summary ?? this.summary,
        myReview: clearMyReview ? null : (myReview ?? this.myReview),
        items: items ?? this.items,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Reviews of a public recipe by id. Refetched when the account changes
/// (the own review comes with the page); the previous value stays on
/// screen meanwhile.
final recipeReviewsProvider = AsyncNotifierProvider.autoDispose
    .family<RecipeReviewsController, RecipeReviewsState, String>(
        RecipeReviewsController.new);

class RecipeReviewsController
    extends AutoDisposeFamilyAsyncNotifier<RecipeReviewsState, String> {
  RecipeCommunityApiService get _api => ref.read(recipeCommunityApiProvider);

  @override
  Future<RecipeReviewsState> build(String recipeId) async {
    final page =
        await ref.watch(recipeCommunityApiProvider).getReviews(recipeId);
    return RecipeReviewsState(
      summary: page.summary,
      myReview: page.myReview,
      items: page.items,
      nextCursor: page.nextCursor,
    );
  }

  /// "Xem thêm đánh giá". Throws `ApiException` (the list stays).
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _api.getReviews(arg, cursor: current.nextCursor);
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(
        items: [...latest.items, ...page.items],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      ));
    } catch (_) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// "Gửi đánh giá" / "Lưu": creates or replaces the member's review; the
  /// summary (and the header line) follow at once. Throws `ApiException`.
  Future<RecipeReview> submit({required int rating, String? content}) async {
    final result = await _api.upsertMyReview(
        arg, UpsertReviewRequestDto(rating: rating, content: content));
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        myReview: result.review,
        summary: current.summary.apply(
          before: current.myReview?.rating,
          after: result.review.rating,
          average: result.averageRating,
          count: result.ratingCount,
        ),
      ));
    }
    return result.review;
  }

  /// "Xoá" (after the confirmation). Throws `ApiException`.
  Future<void> deleteMine() async {
    final totals = await _api.deleteMyReview(arg);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        clearMyReview: true,
        summary: current.summary.apply(
          before: current.myReview?.rating,
          average: totals.averageRating,
          count: totals.ratingCount,
        ),
      ));
    }
  }
}

/// The member's private note on a recipe ("Ghi chú của tôi"); `null` when
/// there is none, and always for guests (nothing is requested).
final recipeNoteProvider = AsyncNotifierProvider.autoDispose
    .family<RecipeNoteController, RecipeNote?, String>(
        RecipeNoteController.new);

class RecipeNoteController
    extends AutoDisposeFamilyAsyncNotifier<RecipeNote?, String> {
  @override
  Future<RecipeNote?> build(String recipeId) async {
    final api = ref.watch(recipeCommunityApiProvider);
    if (ref.watch(plannerUserIdProvider) == null) return null;
    return (await api.getMyNote(recipeId))?.toEntity();
  }

  /// Saves [content]; an empty note is deleted (returns `null`). Throws
  /// `ApiException` (the state is unchanged).
  Future<RecipeNote?> save(String content) async {
    final saved =
        (await ref.read(recipeCommunityApiProvider).saveMyNote(arg, content))
            ?.toEntity();
    state = AsyncData(saved);
    return saved;
  }

  /// "Xoá ghi chú". Throws `ApiException`.
  Future<void> delete() async {
    await ref.read(recipeCommunityApiProvider).deleteMyNote(arg);
    state = const AsyncData(null);
  }
}
