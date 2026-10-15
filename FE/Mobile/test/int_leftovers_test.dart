// test/int_leftovers_test.dart
// INT: sponsored card inside food posts, chef-suggestion target day, the
// fuller Reels strip.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/ads/data/mock_ads_repository.dart';
import 'package:veganlife_mobile/features/ads/data/models/ad_feed_item.dart';
import 'package:veganlife_mobile/features/ads/domain/post_ad_picker.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/reels/data/reels_api_service.dart';

const _q1 = (lat: 10.7769, lng: 106.7009);

Post _post(
  String title, {
  String body = '',
  PostType type = PostType.discussion,
  PostStatus status = PostStatus.published,
}) =>
    Post(
      id: 'p_int_${title.hashCode}',
      type: type,
      author: const AuthorSummary(id: 'u_hoang_nam', name: 'Hoàng Nam'),
      title: title,
      body: body,
      createdAt: DateTime(2026, 10, 14, 9),
      coverSeed: 'int',
      status: status,
    );

Future<void> _pumpApp(WidgetTester tester, Widget home,
    {Size size = const Size(411, 1400)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'vl.access_token': 'mock.jwt',
    'vl.display_name': 'Minh Anh',
    'vl.user_id': 'u_me',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: home),
  ));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  group('sponsored card inside food posts', () {
    late List<AdFeedItemDto> nearestFirst;

    setUpAll(() async {
      nearestFirst = await MockAdsRepository(scenario: 'normal').getFeed(
          city: 'TP. Hồ Chí Minh', lat: _q1.lat, lng: _q1.lng, limit: 10);
      expect(nearestFirst.map((a) => a.id), ['ad_hanh_tam', 'ad_moc_nhien']);
    });

    test('the store serving the dish wins over a nearer one', () {
      final mocFirst = nearestFirst.reversed.toList();
      expect(
          sponsoredAdForPost(
                  _post('Bún riêu chay cà chua đậu hũ', type: PostType.recipe),
                  mocFirst)
              ?.id,
          'ad_hanh_tam');
      expect(
          sponsoredAdForPost(
                  _post('Tối nay ăn gì?',
                      body: 'Nhóm mình 5 người muốn đi lẩu nấm cuối tuần.'),
                  nearestFirst)
              ?.id,
          'ad_moc_nhien');
    });

    test('food without a matching store gets the nearest campaign', () {
      final ad = sponsoredAdForPost(
          _post('Cơm chiên hạt sen thập cẩm', type: PostType.recipe),
          nearestFirst.reversed.toList());
      expect(ad?.id, 'ad_moc_nhien');
      expect(
          sponsoredAdForPost(
                  _post('5 nguồn đạm thực vật',
                      body: 'Đậu hũ, đậu xanh nguyên vỏ và tempeh.'),
                  nearestFirst)
              ?.id,
          'ad_hanh_tam');
    });

    test('no card without food talk, on videos, or on held posts', () {
      expect(
          sponsoredAdForPost(
              _post('Mới ăn chay 3 tuần, nên bổ sung B12 thế nào?',
                  body: 'Bổ sung bằng viên uống hay thực phẩm tăng cường?'),
              nearestFirst),
          isNull);
      expect(
          sponsoredAdForPost(
              _post('Bún riêu chay', type: PostType.video), nearestFirst),
          isNull);
      expect(
          sponsoredAdForPost(
              _post('Bún riêu chay', status: PostStatus.pending), nearestFirst),
          isNull);
      expect(sponsoredAdForPost(_post('Bún riêu chay'), const []), isNull);
    });

    test('food words match with their accents', () {
      expect(mentionsFood('Quán chay ngon trên phố đi bộ'), isFalse);
      expect(mentionsFood('Lâu lắm rồi mới ghé'), isFalse);
      expect(mentionsFood('Phở chay ngon nhất Q.5'), isTrue);
      expect(mentionsFood('Cách làm sữa đậu nành tại nhà'), isTrue);
    });

    testWidgets('post detail: one card after the post, before comments',
        (tester) async {
      await _pumpApp(
          tester,
          PostDetailScreen(
              post: _post('Bún riêu chay cà chua đậu hũ',
                  body: 'Nước dùng ngọt từ củ quả.', type: PostType.recipe)));
      await _wait(tester);
      expect(find.text('Được tài trợ'), findsOneWidget);
      expect(find.byKey(const ValueKey('post-ad-ad_hanh_tam')), findsOneWidget);
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsOneWidget);
      final card = tester.getTopLeft(find.text('Được tài trợ')).dy;
      // Below the like / comment / save bar, above the "Bình luận" header.
      expect(card, greaterThan(tester.getTopLeft(find.text('Thích').first).dy));
      expect(card, lessThan(tester.getTopLeft(find.text('Bình luận').last).dy));
      await _wait(tester, 1000);
    });

    testWidgets('post detail: none on a non-food discussion', (tester) async {
      await _pumpApp(
          tester,
          PostDetailScreen(
              post: _post('Mới ăn chay 3 tuần, nên bổ sung B12 thế nào?')));
      await _wait(tester);
      expect(find.text('Được tài trợ'), findsNothing);
      await _wait(tester, 1000);
    });
  });

  group('chef suggestion target day (member side)', () {
    test('DTO reads targetDate; the label names the meal and the day', () {
      final dto = ChefSuggestionDto.fromJson({
        'id': 'sg_1',
        'chefId': 'u_chef_tam',
        'chefName': 'Lê Quang Tâm',
        'slot': 'dinner',
        'targetDate': '2026-10-17',
        'recipe': {
          'id': 'cs_1',
          'name': 'Bún gạo lứt xào',
          'caloriesCache': 480
        },
      });
      expect(dto.targetDate, DateTime(2026, 10, 17));
      final s = dto.toEntity();
      expect(s.targetDate, DateTime(2026, 10, 17));
      expect(s.scheduleLabel, 'Cho bữa tối · Thứ Bảy, 17/10');

      final dayOnly = ChefSuggestionDto.fromJson({
        'id': 'sg_2',
        'targetDate': '2026-10-19',
        'recipe': {'id': 'cs_2', 'name': 'Cháo'},
      }).toEntity();
      expect(dayOnly.scheduleLabel, 'Cho Thứ Hai, 19/10');

      final none = ChefSuggestionDto.fromJson({
        'id': 'sg_3',
        'slot': 'lunch',
        'targetDate': null,
        'recipe': {'id': 'cs_3', 'name': 'Cơm'},
      }).toEntity();
      expect(none.targetDate, isNull);
      expect(none.scheduleLabel, isNull);
    });

    test('Minh Anh\'s seeded dinner suggestion is for tomorrow', () async {
      final list =
          await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
      final dinner = list
          .map((d) => d.toEntity())
          .firstWhere((s) => s.slot == MealSlot.dinner);
      expect(dinner.targetDate,
          dateOnly(DateTime.now().add(const Duration(days: 1))));
    });

    testWidgets('"Từ chuyên gia" shows "Cho bữa tối · <Thứ>, dd/MM"',
        (tester) async {
      await _pumpApp(tester, const MealPlannerScreen(),
          size: const Size(411, 2600));
      await _wait(tester, 3000);
      await tester.tap(find.byTooltip('Đổi bữa sáng'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final chefTab = find.descendant(
          of: find.byType(TabBar), matching: find.text('Từ chuyên gia'));
      await tester.ensureVisible(chefTab); // the tab row scrolls
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chefTab);
      await _wait(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(find.text('Cho bữa tối · ${formatLongDate(tomorrow)}'),
          findsOneWidget);
      expect(find.text('Lê Quang Tâm đề xuất cho bữa sáng'), findsOneWidget);
      expect(find.text('Lê Quang Tâm đề xuất'), findsOneWidget);
      await _wait(tester, 1000);
    });
  });

  group('Reels strip', () {
    test('at least 7 clips for a guest, sample files kept per post', () async {
      final reels = await MockReelsRepository(MockCommunityRepository(
          currentUserName: () => 'Khách', isSignedIn: () => false)).getReels();
      expect(reels.length, greaterThanOrEqualTo(7));
      for (final r in reels) {
        expect(reelSampleVideos, contains(r.videoUrl));
        expect(r.durationSeconds, isNotNull);
      }
      final added =
          reels.where((r) => r.post.id.startsWith('p_reel_')).toList();
      expect(added, hasLength(4));
      for (final r in added) {
        expect(r.videoUrl, r.post.mediaUrl);
        expect(r.durationSeconds, lessThan(70));
        expect(r.toEntity().hasRecipe, isTrue);
      }
    });
  });
}
