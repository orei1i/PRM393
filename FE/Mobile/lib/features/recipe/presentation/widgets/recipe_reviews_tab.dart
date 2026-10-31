// lib/features/recipe/presentation/widgets/recipe_reviews_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/recipe_review.dart';
import '../controllers/recipe_social_controllers.dart';
import 'rating_summary.dart';
import 'recipe_review_sheet.dart';

/// "Đánh giá" tab of a public recipe: the summary, the member's own review
/// ("Viết đánh giá" / "Sửa" / "Xoá") and everyone else's, 10 at a time.
/// Guests read everything; writing asks them to sign in first.
class RecipeReviewsTab extends ConsumerStatefulWidget {
  const RecipeReviewsTab({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<RecipeReviewsTab> createState() => _RecipeReviewsTabState();
}

class _RecipeReviewsTabState extends ConsumerState<RecipeReviewsTab> {
  String get _id => widget.recipeId;

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _write() async {
    final ok = await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để đánh giá công thức.');
    if (!ok || !mounted) return;
    final provider = recipeReviewsProvider(_id);
    final RecipeReview? existing;
    try {
      // After signing in the page is refetched with the member's review.
      existing = (await ref.read(provider.future)).myReview;
    } catch (e) {
      if (mounted) _snack(describeError(e));
      return;
    }
    if (!mounted) return;
    final saved = await showRecipeReviewSheet(
      context,
      existing: existing,
      onSubmit: (rating, content) =>
          ref.read(provider.notifier).submit(rating: rating, content: content),
    );
    if (saved && mounted) {
      _snack(existing == null ? 'Đã gửi đánh giá' : 'Đã cập nhật đánh giá');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá đánh giá của bạn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(recipeReviewsProvider(_id).notifier).deleteMine();
      if (mounted) _snack('Đã xoá đánh giá');
    } catch (e) {
      if (mounted) _snack(describeError(e));
    }
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(recipeReviewsProvider(_id).notifier).loadMore();
    } catch (e) {
      if (mounted) _snack(describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recipeReviewsProvider(_id));
    final value = async.valueOrNull;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    if (value == null) {
      if (async.hasError) {
        return Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
              error: async.error!,
              onRetry: () => ref.invalidate(recipeReviewsProvider(_id)),
            ),
          ),
        );
      }
      return const _ReviewsSkeleton();
    }
    final mine = value.myReview;
    return ListView(
      key: const PageStorageKey('recipe-reviews'),
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottom),
      children: [
        RatingSummaryCard(summary: value.summary),
        const SizedBox(height: 16),
        if (mine == null)
          VLCard(
            child: Row(
              children: [
                Expanded(
                  child: Text('Bạn đã nấu món này?',
                      style: context.textStyles.titleSmall),
                ),
                FilledButton(
                  onPressed: _write,
                  child: const Text('Viết đánh giá'),
                ),
              ],
            ),
          )
        else
          VLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đánh giá của bạn',
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _ReviewBody(review: mine),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _write, child: const Text('Sửa')),
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                          foregroundColor: context.colors.error),
                      child: const Text('Xoá'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        for (final r in value.items) ...[
          const Divider(height: 24),
          _ReviewTile(review: r),
        ],
        if (value.hasMore) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: value.loadingMore ? null : _loadMore,
            child: value.loadingMore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Xem thêm đánh giá'),
          ),
        ],
      ],
    );
  }
}

/// Stars, "· 3 ngày trước (đã sửa)" and the text.
class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.review});

  final RecipeReview review;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StarRow(rating: review.rating.toDouble(), size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${relativeTime(review.createdAt)}'
                '${review.isEdited ? ' (đã sửa)' : ''}',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
              ),
            ),
          ],
        ),
        if (review.content != null) ...[
          const SizedBox(height: 4),
          Text(review.content!, style: context.textStyles.bodyMedium),
        ],
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final RecipeReview review;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(name: review.authorName, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(review.authorName,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (review.isVerifiedChef) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded,
                        size: 16,
                        color: context.colors.primary,
                        semanticLabel: 'Chuyên gia đã xác minh'),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              _ReviewBody(review: review),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewsSkeleton extends StatelessWidget {
  const _ReviewsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 160, height: 48),
            SizedBox(height: 16),
            SkeletonBox(height: 64, radius: 16),
            SizedBox(height: 20),
            SkeletonBox(width: 200, height: 14),
            SizedBox(height: 8),
            SkeletonBox(height: 14),
            SizedBox(height: 20),
            SkeletonBox(width: 200, height: 14),
            SizedBox(height: 8),
            SkeletonBox(height: 14),
          ],
        ),
      ),
    );
  }
}
