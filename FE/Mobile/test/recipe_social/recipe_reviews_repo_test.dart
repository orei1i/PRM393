// test/recipe_social/recipe_reviews_repo_test.dart
// Recipe reviews in mock mode (§3.3): seeds, one review per member (upsert,
// edit, delete), the summary, errors (401 / 403 own recipe / 404 private /
// 400 rating and length / 503 #fail), pages of 10, and the controller that
// keeps the tab and the header line in step.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_review_model.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_review.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_social_controllers.dart';

Matcher _apiError(int status, [String? message]) => throwsA(isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => message == null || e.message == message, 'message $message',
        isTrue));

MockRecipeCommunityRepository _as(String? userId) =>
    MockRecipeCommunityRepository(userId: userId);

const _good = 'Riêu nấm ngon, dễ nấu cho cả nhà.';

void main() {
  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
  });

  group('seeds', () {
    test(
        'l5: 5 reviews 5,5,5,4,4 → 4,6; newest first; Tâm is a verified '
        'chef', () async {
      final page = await _as(null).getReviews('l5');
      expect(page.summary.average, 4.6);
      expect(page.summary.count, 5);
      expect(page.summary.headline, '★ 4,6 · 5 đánh giá');
      expect(page.summary.distribution, {1: 0, 2: 0, 3: 0, 4: 2, 5: 3});
      expect(page.myReview, isNull);
      expect(page.nextCursor, isNull);
      expect(page.items.map((r) => r.authorName), [
        'Lê Quang Tâm',
        'Hoàng Nam',
        'Thảo Vy',
        'Ngọc Trâm',
        'Gia Hân',
      ]);
      expect(page.items.first.isVerifiedChef, isTrue);
      expect(page.items.skip(1).any((r) => r.isVerifiedChef), isFalse);
      expect(page.items[2].isEdited, isTrue, reason: '"(đã sửa)"');
      expect(page.items[3].content, isNull, reason: 'stars only');
    });

    test('b1: 5,4 → 4,5; menu_1: 4; others none; the recipe carries them',
        () async {
      expect((await _as(null).getReviews('b1')).summary.average, 4.5);
      expect((await _as(null).getReviews('b1')).summary.count, 2);
      expect((await _as(null).getReviews('menu_1')).summary.average, 4.0);
      final none = await _as(null).getReviews('menu_3');
      expect(none.summary.isEmpty, isTrue);
      expect(none.summary.average, isNull);
      expect(none.summary.headline, 'Chưa có đánh giá');

      final l5 = (await MockRecipeRepository().getRecipe('l5')).toEntity();
      expect(l5.averageRating, 4.6);
      expect(l5.ratingCount, 5);
      final menu3 =
          (await MockRecipeRepository().getRecipe('menu_3')).toEntity();
      expect(menu3.averageRating, isNull);
      expect(menu3.ratingCount, 0);
    });
  });

  group('one review per member', () {
    test('write, edit, delete; the own review is not repeated in items',
        () async {
      final me = _as('u_me');
      final written = await me.upsertMyReview(
          'l5', const UpsertReviewRequestDto(rating: 4, content: '  $_good  '));
      expect(written.averageRating, 4.5);
      expect(written.ratingCount, 6);
      expect(written.review.content, _good);
      expect(written.review.authorName, 'Minh Anh');
      expect(written.review.isEdited, isFalse);

      final mine = await me.getReviews('l5');
      expect(mine.myReview?.id, written.review.id);
      expect(mine.items, hasLength(5));
      expect(mine.summary.count, 6);
      expect((await _as(null).getReviews('l5')).items, hasLength(6));

      final edited = await me.upsertMyReview(
          'l5', const UpsertReviewRequestDto(rating: 5));
      expect(edited.review.id, written.review.id);
      expect(edited.ratingCount, 6, reason: 'replaced, not added');
      expect(edited.averageRating, 4.7);
      expect(edited.review.content, isNull);
      expect(edited.review.isEdited, isTrue);

      final totals = await me.deleteMyReview('l5');
      expect(totals.ratingCount, 5);
      expect(totals.averageRating, 4.6);
      expect((await me.getReviews('l5')).myReview, isNull);
      await expectLater(me.deleteMyReview('l5'), _apiError(404));
    });

    test('Tâm\'s seeded review comes back as his own', () async {
      final page = await _as('u_chef_tam').getReviews('l5');
      expect(page.myReview?.authorName, 'Lê Quang Tâm');
      expect(page.items, hasLength(4));
    });
  });

  group('errors', () {
    test('guest → 401; unknown recipe → 404', () async {
      await expectLater(
          _as(null)
              .upsertMyReview('l5', const UpsertReviewRequestDto(rating: 5)),
          _apiError(401));
      await expectLater(_as(null).deleteMyReview('l5'), _apiError(401));
      await expectLater(_as(null).getReviews('khong_co'), _apiError(404));
    });

    test('own recipe → 403; someone else\'s private recipe → 404', () async {
      final variant = (await _as('u_me').createVariant(
              'l5',
              const CreateVariantRequestDto(
                  name: 'Bún riêu nấm', swaps: {'rieu': 'rieu_nam'})))
          .toEntity();
      await expectLater(
          _as('u_me').upsertMyReview(
              variant.id, const UpsertReviewRequestDto(rating: 5)),
          _apiError(403, 'Bạn không thể đánh giá công thức của chính mình.'));
      await expectLater(
          _as('u_chef_tam').upsertMyReview(
              variant.id, const UpsertReviewRequestDto(rating: 5)),
          _apiError(404));
      await expectLater(_as(null).getReviews(variant.id), _apiError(404));
    });

    test('rating 1–5 required; text optional but 10–500 chars', () async {
      final me = _as('u_me');
      for (final r in [0, 6]) {
        await expectLater(
            me.upsertMyReview('l5', UpsertReviewRequestDto(rating: r)),
            _apiError(400, 'Chọn từ 1 đến 5 sao.'));
      }
      await expectLater(
          me.upsertMyReview(
              'l5', const UpsertReviewRequestDto(rating: 4, content: 'Ngon')),
          _apiError(400, 'Nhận xét cần ít nhất 10 ký tự'));
      await expectLater(
          me.upsertMyReview(
              'l5', UpsertReviewRequestDto(rating: 4, content: 'a' * 501)),
          _apiError(400, 'Tối đa 500 ký tự'));
      expect(
          (await me.upsertMyReview(
                  'l5', UpsertReviewRequestDto(rating: 4, content: 'a' * 500)))
              .ratingCount,
          6);
    });

    test('#fail in the text → 503, nothing saved', () async {
      await expectLater(
          _as('u_me').upsertMyReview(
              'l5',
              const UpsertReviewRequestDto(
                  rating: 4, content: 'Thử lỗi #fail')),
          _apiError(503));
      expect((await _as(null).getReviews('l5')).summary.count, 5);
    });
  });

  test('pages of 10, newest first, no overlap', () async {
    for (var i = 0; i < 12; i++) {
      await _as('u_p$i')
          .upsertMyReview('menu_3', UpsertReviewRequestDto(rating: 1 + i % 5));
    }
    final first = await _as(null).getReviews('menu_3');
    expect(first.items, hasLength(10));
    expect(first.nextCursor, isNotNull);
    expect(first.summary.count, 12);
    final second =
        await _as(null).getReviews('menu_3', cursor: first.nextCursor);
    expect(second.items, hasLength(2));
    expect(second.nextCursor, isNull);
    final ids = {
      ...first.items.map((r) => r.id),
      ...second.items.map((r) => r.id)
    };
    expect(ids, hasLength(12));
  });

  test('RatingSummary.apply moves the member\'s star in the distribution', () {
    const s = RatingSummary(
        average: 4.6, count: 5, distribution: {5: 3, 4: 2, 3: 0, 2: 0, 1: 0});
    final added = s.apply(after: 4, average: 4.5, count: 6);
    expect(added.countOf(4), 3);
    expect(added.headline, '★ 4,5 · 6 đánh giá');
    final edited = added.apply(before: 4, after: 2, average: 4.2, count: 6);
    expect([edited.countOf(4), edited.countOf(2)], [2, 1]);
    final removed = edited.apply(before: 2, average: 4.6, count: 5);
    expect(removed.countOf(2), 0);
    expect(const RatingSummary().apply(before: 5, count: 0).average, isNull);
  });

  test('the controller keeps the summary in step with writes', () async {
    final container = ProviderContainer(
        overrides: [plannerUserIdProvider.overrideWithValue('u_me')]);
    addTearDown(container.dispose);
    final provider = recipeReviewsProvider('l5');
    container.listen(provider, (_, __) {});
    final loaded = await container.read(provider.future);
    expect(loaded.myReview, isNull);
    expect(loaded.items, hasLength(5));

    final controller = container.read(provider.notifier);
    await controller.submit(rating: 4, content: _good);
    var state = container.read(provider).requireValue;
    expect(state.myReview?.rating, 4);
    expect(state.summary.headline, '★ 4,5 · 6 đánh giá');
    expect(state.summary.countOf(4), 3);

    await controller.submit(rating: 5);
    state = container.read(provider).requireValue;
    expect(state.summary.count, 6);
    expect([state.summary.countOf(5), state.summary.countOf(4)], [4, 2]);

    await controller.deleteMine();
    state = container.read(provider).requireValue;
    expect(state.myReview, isNull);
    expect(state.summary.headline, '★ 4,6 · 5 đánh giá');
    expect([state.summary.countOf(5), state.summary.countOf(4)], [3, 2]);

    await expectLater(
        controller.submit(rating: 3, content: 'Lỗi mạng #fail rồi'),
        _apiError(503));
    expect(container.read(provider).requireValue.myReview, isNull);
  });
}
