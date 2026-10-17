// test/community/m4_reels_ads_test.dart
// Trang chủ (TestPRM p01, p04, p05, p08, p10): no "+", logo title, composer
// without icons, no "Xem tất cả", filters, no sponsored cards, entry points;
// Reels (p06): comments and recipe in bottom sheets, no share.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/app_logo.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_thread.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comments_sheet.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';
import 'package:veganlife_mobile/features/reels/data/reels_api_service.dart';
import 'package:veganlife_mobile/features/reels/domain/reel.dart';
import 'package:veganlife_mobile/features/reels/presentation/controllers/reels_controller.dart';
import 'package:veganlife_mobile/features/reels/presentation/screens/reels_player_screen.dart';
import 'package:veganlife_mobile/features/reels/presentation/widgets/reels_strip.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';
import 'package:veganlife_mobile/features/video/presentation/widgets/video_recipe_sheet.dart';
import 'package:video_player/video_player.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

/// Plays without the video plugin and records what the page asks of it.
class _FakeVideo extends VideoPlayerController {
  _FakeVideo(String url) : super.networkUrl(Uri.parse(url));

  bool disposed = false;
  final seeks = <Duration>[];

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(minutes: 12),
      size: const Size(720, 1280),
    );
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setLooping(bool looping) async =>
      value = value.copyWith(isLooping: looping);

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const [],
    Map<String, Object> session = _minhAnh}) async {
  tester.view
    ..physicalSize = const Size(411, 913)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pump(const Duration(seconds: 3)); // mock latency
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Future<List<Reel>> _reels(WidgetTester tester) async {
  final repo = MockReelsRepository(MockCommunityRepository(
      currentUserName: () => 'Minh Anh', isSignedIn: () => true));
  return (await tester.runAsync(repo.getReels))!
      .map((d) => d.toEntity())
      .toList();
}

final _feedScroll = find.byType(Scrollable).first;

/// Scrolls [finder] into view (horizontal chips, scrollable tabs), taps it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  group('Trang chủ', () {
    testWidgets(
        'logo title; search and nearby only (no "+"); composer without icons; '
        'Reels without "Xem tất cả"', (tester) async {
      await _pump(tester, const FeedScreen());
      expect(find.byType(VeganLifeLogo), findsOneWidget);
      expect(find.byTooltip('Tìm kiếm'), findsOneWidget);
      expect(find.byTooltip('Quán chay gần bạn'), findsOneWidget);
      expect(find.byTooltip('Tạo bài viết'), findsNothing);
      expect(find.byIcon(Icons.add_box_outlined), findsNothing);
      expect(find.text('Hôm nay Minh Anh nấu món gì?'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
      expect(find.byIcon(Icons.restaurant_menu_rounded), findsNothing);
      expect(find.text('Bếp nhanh'), findsOneWidget);
      expect(find.text('Xem tất cả'), findsNothing);
      for (final label in ['Tất cả', 'Công thức', 'Hỏi đáp', 'Có video']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget,
            reason: label);
      }

      await tester.tap(find.byTooltip('Tìm kiếm'));
      await _frames(tester);
      expect(find.byType(SearchScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(SearchScreen))).pop();
      await _frames(tester);

      await tester.tap(find.byTooltip('Quán chay gần bạn'));
      await _frames(tester);
      expect(find.byType(RestaurantNearbyScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(RestaurantNearbyScreen))).pop();
      await _frames(tester);
      await _dispose(tester);
    });

    testWidgets('no "Được tài trợ" card anywhere in the feed', (tester) async {
      await _pump(tester, const FeedScreen());
      for (var i = 0;
          i < 60 && find.text('Bạn đã xem hết bài mới').evaluate().isEmpty;
          i++) {
        expect(find.text('Được tài trợ'), findsNothing);
        await tester.drag(_feedScroll, const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 900));
      }
      expect(find.text('Bạn đã xem hết bài mới'), findsOneWidget);
      expect(find.text('Được tài trợ'), findsNothing);
      // The check-in post shows its restaurant instead.
      await _dispose(tester);
    });

    testWidgets('"Có video" keeps the Reels strip; "Hỏi đáp" hides it',
        (tester) async {
      await _pump(tester, const FeedScreen());
      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Có video'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ReelsStrip), findsOneWidget);
      final cards = tester.widgetList<PostCard>(find.byType(PostCard));
      expect(cards, isNotEmpty);
      expect(cards.every((c) => c.post.hasVideo), isTrue);

      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Hỏi đáp'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ReelsStrip), findsNothing);
      final qa = tester.widgetList<PostCard>(find.byType(PostCard));
      expect(qa.every((c) => c.post.type == PostType.discussion), isTrue);
      await _dispose(tester);
    });

    testWidgets(
        'the composer opens Tạo bài viết; a card\'s "Bình luận" opens the '
        'post at the comments', (tester) async {
      await _pump(tester, const FeedScreen());
      await tester.tap(find.text('Hôm nay Minh Anh nấu món gì?'));
      await _frames(tester);
      expect(find.byType(CreatePostScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(CreatePostScreen))).pop();
      await _frames(tester);

      await tester.scrollUntilVisible(
          find.descendant(
              of: find.byType(PostCard).first,
              matching: find.text('Bình luận')),
          300,
          scrollable: _feedScroll);
      await tester.tap(find
          .descendant(
              of: find.byType(PostCard).first, matching: find.text('Bình luận'))
          .hitTestable());
      await _frames(tester);
      final detail =
          tester.widget<PostDetailScreen>(find.byType(PostDetailScreen));
      expect(detail.entry, PostDetailEntry.writeComment);
      await tester.pump(const Duration(seconds: 2));
      await _dispose(tester);
    });

    testWidgets(
        'a guest sees "Hôm nay bạn nấu món gì?" and is asked to sign in',
        (tester) async {
      await _pump(tester, const FeedScreen(), session: const {});
      expect(find.text('Hôm nay bạn nấu món gì?'), findsOneWidget);
      await tester.tap(find.text('Hôm nay bạn nấu món gì?'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
      expect(find.byType(CreatePostScreen), findsNothing);
      await _dispose(tester);
    });

    test('reels are the video posts, with playable clips', () async {
      final repo = MockReelsRepository(MockCommunityRepository(
          currentUserName: () => 'Minh Anh', isSignedIn: () => true));
      final reels = await repo.getReels();
      expect(reels, isNotEmpty);
      for (final r in reels) {
        final reel = r.toEntity();
        expect(reel.post.mediaType, PostMediaType.video);
        expect(reelSampleVideos, contains(reel.videoUrl));
      }
      expect(reels.first.toEntity().hasRecipe, isTrue);
    });

    testWidgets(
        'Reels strip opens the player; a failed clip offers retry; no share',
        (tester) async {
      await _pump(tester, const FeedScreen(), overrides: [
        reelVideoFactoryProvider
            .overrideWithValue((_) => throw Exception('no video plugin')),
      ]);
      await tester.tap(
          find.text('Chả lụa chay từ đậu hũ ky — không cần máy xay').first);
      await _frames(tester);
      expect(find.byType(ReelsPlayerScreen), findsOneWidget);
      expect(find.textContaining('Không phát được video'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      for (final t in ['Thích', 'Bình luận', 'Lưu']) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      expect(find.byTooltip('Chia sẻ'), findsNothing);
      expect(find.text('Chia sẻ'), findsNothing);
      expect(find.text('Xem công thức'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await _frames(tester);
      expect(find.byType(ReelsPlayerScreen), findsNothing);
      await _dispose(tester);
    });
  });

  group('Reels player', () {
    testWidgets(
        'plays the active clip only, pauses on swipe, mute toggle, '
        'disposes every player', (tester) async {
      final created = <_FakeVideo>[];
      final reels = await _reels(tester);
      expect(reels.length, greaterThanOrEqualTo(2));
      await _pump(tester, ReelsPlayerScreen(reels: reels), overrides: [
        reelVideoFactoryProvider.overrideWithValue((url) {
          final v = _FakeVideo(url);
          created.add(v);
          return v;
        }),
      ]);
      expect(created, hasLength(1));
      expect(created.first.value.isPlaying, isTrue);
      expect(created.first.value.volume, 0, reason: 'autoplays muted');

      await tester.tap(find.byTooltip('Bật tiếng'));
      await tester.pump();
      expect(created.first.value.volume, 1);

      // Tap pauses, tap again resumes.
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      expect(created.first.value.isPlaying, isFalse);
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      expect(created.first.value.isPlaying, isTrue);

      await tester.fling(find.byType(PageView), const Offset(0, -500), 2000);
      await _frames(tester);
      expect(created, hasLength(2));
      expect(created[1].value.isPlaying, isTrue);
      expect(!created.first.value.isPlaying || created.first.disposed, isTrue);
      expect(created[1].value.volume, 1, reason: 'sound stays on');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(created.every((v) => v.disposed), isTrue);
    });

    testWidgets(
        '"Bình luận" opens the thread in a sheet (paused while open); '
        '"Xem công thức" opens the recipe sheet and a timestamp seeks',
        (tester) async {
      final created = <_FakeVideo>[];
      final reels = await _reels(tester);
      await _pump(tester, ReelsPlayerScreen(reels: reels), overrides: [
        reelVideoFactoryProvider.overrideWithValue((url) {
          final v = _FakeVideo(url);
          created.add(v);
          return v;
        }),
      ]);
      final video = created.single;
      expect(video.value.isPlaying, isTrue);

      await tester.tap(find.byTooltip('Bình luận'));
      await _frames(tester, 8);
      expect(find.byType(CommentsSheet), findsOneWidget);
      expect(find.textContaining('Bình luận ('), findsOneWidget);
      expect(find.byType(CommentComposer), findsOneWidget);
      expect(find.byType(ReelsPlayerScreen), findsOneWidget,
          reason: 'a sheet, not a new page');
      expect(video.value.isPlaying, isFalse);
      await tester.tap(find.byTooltip('Đóng').last);
      await _frames(tester);
      expect(find.byType(CommentsSheet), findsNothing);
      expect(video.value.isPlaying, isTrue);

      await tester.tap(find.text('Xem công thức'));
      await _frames(tester, 8);
      expect(find.byType(VideoRecipeSheet), findsOneWidget);
      expect(video.value.isPlaying, isFalse);
      await _tapVisible(tester, find.widgetWithText(Tab, 'Các bước'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ActionChip).first);
      await _frames(tester);
      expect(find.byType(VideoRecipeSheet), findsNothing);
      expect(video.seeks, hasLength(1));
      expect(video.seeks.single, greaterThan(Duration.zero));
      expect(video.value.isPlaying, isTrue);
      await _dispose(tester);
    });

    testWidgets('the comments sheet sends a comment and moves the count',
        (tester) async {
      final reels = await _reels(tester);
      final reel = reels.firstWhere((r) => r.id == 'p_reel_che_dau_xanh');
      final changes = <int>[];
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCommentsSheet(context, reel.post,
                    onCountChanged: changes.add),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await _frames(tester, 8);
      final before = reel.post.commentCount;
      expect(find.text('Bình luận ($before)'), findsOneWidget);
      await tester.enterText(
          find.descendant(
              of: find.byType(CommentComposer),
              matching: find.byType(TextField)),
          'Nấu thử rồi, ngon!');
      await tester.tap(find.byTooltip('Gửi'));
      await _frames(tester, 8);
      expect(find.text('Bình luận (${before + 1})'), findsOneWidget);
      expect(find.text('Nấu thử rồi, ngon!'), findsOneWidget);
      expect(changes, [1]);
      await _dispose(tester);
    });
  });
}
