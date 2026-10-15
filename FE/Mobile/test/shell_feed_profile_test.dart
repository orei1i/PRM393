// test/shell_feed_profile_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/widgets/trial_exhausted_sheet.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/feed_controller.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/comments_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/feed_filter_chips.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';

/// The mock backend keeps one static in-memory DB per test isolate, so each
/// test below uses its own posts or compares against values read first.
void main() {
  group('FeedFilterChips', () {
    // Reproduces the device bug: Google Fonts arrives after the first layout
    // and is wider than the fallback, so a chip sized from cached metrics
    // clips its label ("Công thứ"). Uses the Roboto files in the Flutter SDK.
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final haveFonts = File('$fonts/roboto-black.ttf').existsSync() &&
        File('$fonts/robotocondensed-bold.ttf').existsSync();

    Future<void> loadFont(String family, String file) async {
      final bytes = await File('$fonts/$file').readAsBytes();
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }

    testWidgets('re-measures labels when a wider font finishes loading',
        (tester) async {
      tester.view
        ..physicalSize = const Size(411, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Same family, narrow face first; the w900 face replaces it on load.
      const family = 'LateLoadingFont';
      await tester.runAsync(() => loadFont(family, 'robotocondensed-bold.ttf'));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          chipTheme: const ChipThemeData(
            labelStyle: TextStyle(
                fontFamily: family, fontWeight: FontWeight.w900, fontSize: 14),
          ),
        ),
        home:
            Scaffold(body: FeedFilterChips(selected: null, onSelected: (_) {})),
      ));
      final narrow = tester
          .renderObject<RenderParagraph>(find.text('Công thức'))
          .size
          .width;

      await tester.runAsync(() => loadFont(family, 'roboto-black.ttf'));
      await tester.pumpAndSettle();

      final paragraph =
          tester.renderObject<RenderParagraph>(find.text('Công thức'));
      final real = TextPainter(
        text: TextSpan(text: 'Công thức', style: paragraph.text.style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      expect(real.width, greaterThan(narrow), reason: 'font did not widen');
      expect(paragraph.size.width, closeTo(real.width, 0.01));
    }, skip: !haveFonts);

    for (final scale in [1.0, 2.0]) {
      testWidgets('shows full labels at 411 dp, text scale $scale',
          (tester) async {
        tester.view
          ..physicalSize = const Size(411, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        PostType? picked;

        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: FeedFilterChips(
                    selected: PostType.recipe, onSelected: (t) => picked = t),
              ),
            ),
          ),
        ));

        for (final label in ['Tất cả', 'Công thức', 'Video', 'Thảo luận']) {
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.size.width,
              greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(800) - 0.01),
              reason: '"$label" is clipped');
          expect(paragraph.size.height,
              greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(800) - 0.01),
              reason: '"$label" is clipped vertically');
        }
        expect(tester.takeException(), isNull);

        // Off-screen chips are reachable by scrolling sideways.
        await tester.ensureVisible(find.text('Thảo luận'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Thảo luận'));
        expect(picked, PostType.discussion);
      });
    }
  });

  testWidgets(
      '"Hỏi AI" bubble steps aside while scrolling, never on the feed end',
      (tester) async {
    tester.view
      ..physicalSize = const Size(411, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pump(const Duration(seconds: 2)); // mock latency
    final ai = find.byKey(const ValueKey('ask-ai'));
    final feed = find.byType(CustomScrollView).first;
    expect(ai, findsOneWidget);

    // The bubble's fade needs a few frames; it returns once scrolling stops.
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    final gesture = await tester.startGesture(tester.getCenter(feed));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(ai, findsNothing);
    await gesture.up();
    await settle();
    expect(ai, findsOneWidget);

    // Scroll to the very end (more pages load on the way): the last line
    // shows above the tab bar and the bubble is not on it.
    final end = find.text('Bạn đã xem hết bài mới');
    for (var i = 0; i < 20 && end.evaluate().isEmpty; i++) {
      await tester.drag(feed, const Offset(0, -2000));
      await tester.pump(const Duration(seconds: 2));
    }
    await tester.drag(feed, const Offset(0, -2000));
    await tester.pump(const Duration(seconds: 2));
    // Full-width posts vary in height, so the list's extent estimate shrinks
    // at the end and it springs back: let that finish.
    await settle();
    await settle();
    expect(ai, findsOneWidget);
    final last = tester.getRect(end);
    expect(last.bottom,
        lessThan(tester.getRect(find.byKey(const ValueKey('shell-nav'))).top));
    expect(last.overlaps(tester.getRect(ai)), isFalse);
    await tester.pump(const Duration(seconds: 3));
  });

  group('TrialExhaustedSheet', () {
    Future<void> pumpSheet(WidgetTester tester,
        {required int remaining, required int limit}) {
      return tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TrialExhaustedSheet(remaining: remaining, limit: limit),
          ),
        ),
      ));
    }

    testWidgets('invites, without "đã dùng hết", while questions remain',
        (tester) async {
      await pumpSheet(tester, remaining: 2, limit: 3);
      expect(find.textContaining('Bạn vẫn còn 2/3 lượt hỏi miễn phí'),
          findsOneWidget);
      expect(find.textContaining('đã dùng hết'), findsNothing);
    });

    testWidgets('says the trial is over with the configured limit',
        (tester) async {
      await pumpSheet(tester, remaining: 0, limit: 5);
      expect(find.textContaining('Bạn đã dùng hết 5 lượt hỏi miễn phí'),
          findsOneWidget);
      expect(find.textContaining('vẫn còn'), findsNothing);
    });
  });

  group('MockCommunityRepository', () {
    var signedIn = true;
    final repo = MockCommunityRepository(
        currentUserName: () => 'Minh Anh', isSignedIn: () => signedIn);
    setUp(() => signedIn = true);

    Future<List<PostDto>> wholeFeed() async {
      final posts = <PostDto>[];
      String? cursor;
      do {
        final page = await repo.getFeed(cursor: cursor);
        posts.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      return posts;
    }

    test('every thread is as long as the post says', () async {
      final posts = await wholeFeed();
      final threads =
          await Future.wait([for (final p in posts) repo.getComments(p.id)]);
      for (var i = 0; i < posts.length; i++) {
        expect(threads[i], hasLength(posts[i].commentCount),
            reason: posts[i].id);
        expect(threads[i].where((c) => c.author.id == 'u_me'), isEmpty,
            reason: '${posts[i].id} has a comment by the member');
      }
      final bunRieu = posts.singleWhere((p) => p.id == 'p_bun_rieu');
      expect(bunRieu.commentCount, 27);
    });

    test('a new comment moves the count and the thread together', () async {
      final before = await repo.getPost('p_sua_chua_dua');
      await repo.addComment('p_sua_chua_dua', 'Ngon quá!');
      final after = await repo.getPost('p_sua_chua_dua');
      final thread = await repo.getComments('p_sua_chua_dua');
      expect(after.commentCount, before.commentCount + 1);
      expect(thread, hasLength(after.commentCount));
      expect(thread.last.text, 'Ngon quá!');
    });

    test('guests never see the member\'s likes, saves or own posts', () async {
      await repo.setSaved('p_quan_chay_q9', saved: true);
      await repo.setLiked('p_quan_chay_q9', liked: true);
      final member = await repo.getPost('p_quan_chay_q9');
      expect(member.savedByMe, isTrue);
      expect(member.likedByMe, isTrue);

      signedIn = false;
      final guest = await repo.getPost('p_quan_chay_q9');
      expect(guest.savedByMe, isFalse);
      expect(guest.likedByMe, isFalse);
      expect(guest.likeCount, member.likeCount,
          reason: 'the public count still includes the like');
      expect(await repo.getSavedPosts(), isEmpty);
      expect(await repo.getMyPosts(), isEmpty);
      await expectLater(
        repo.setSaved('p_quan_chay_q9', saved: false),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      signedIn = true;
      expect((await repo.getPost('p_quan_chay_q9')).savedByMe, isTrue);
      await repo.setSaved('p_quan_chay_q9', saved: false);
      await repo.setLiked('p_quan_chay_q9', liked: false);
    });
  });

  testWidgets('comments page lists the whole thread and shows a new reply',
      (tester) async {
    tester.view
      ..physicalSize = const Size(411, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(
        {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'});
    final prefs = await SharedPreferences.getInstance();
    final post = Post(
      id: 'p_video_meal_prep',
      type: PostType.video,
      author: const AuthorSummary(id: 'u_bep', name: 'Bếp'),
      title: '',
      body: '',
      createdAt: DateTime.now(),
      coverSeed: 'x',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(home: CommentsScreen(post: post)),
    ));
    await tester.pump(const Duration(seconds: 2)); // mock latency
    expect(find.text('88'), findsOneWidget, reason: 'seed commentCount');

    await tester.enterText(find.byType(TextField), 'Cảm ơn bếp nhà mây!');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('89'), findsOneWidget);
    final reply = find.text('Cảm ơn bếp nhà mây!');
    expect(reply, findsOneWidget);
    expect(tester.getRect(reply).bottom,
        lessThan(tester.getRect(find.byType(TextField)).top));
    await tester.pump(const Duration(seconds: 2)); // feed refetch timers
  });

  test(
    'profile stats follow saves / new posts; sign-out resets the feed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      container
        ..listen(feedControllerProvider, (_, __) {})
        ..listen(profileStatsProvider, (_, __) {});

      Future<ProfileStats> stats() async {
        await container.read(myPostsProvider.future);
        await container.read(savedPostsProvider.future);
        return container.read(profileStatsProvider)!;
      }

      Future<Post> feedPost(String id) async =>
          (await container.read(feedControllerProvider.future)).byId(id)!;

      await container
          .read(sessionControllerProvider.notifier)
          .signInWithGoogle();
      final before = await stats();

      final post = await feedPost('p_bun_rieu');
      expect(post.savedByMe, isFalse);
      await container
          .read(feedControllerProvider.notifier)
          .setSaved(post, saved: true);
      expect((await stats()).saved, before.saved + 1);

      final created = await container.read(communityApiProvider).createPost(
          const CreatePostRequestDto(
              type: PostType.recipe, title: 'Gỏi cuốn chay', body: 'Cuốn.'));
      container
          .read(feedControllerProvider.notifier)
          .prepend(created.toEntity());
      final after = await stats();
      expect(after.posts, before.posts + 1);
      expect(after.likesReceived, before.likesReceived);

      await container.read(sessionControllerProvider.notifier).signOut();
      final guestFeed = await container.read(feedControllerProvider.future);
      expect(guestFeed.byId('p_bun_rieu'), isNotNull);
      expect(guestFeed.posts.where((p) => p.savedByMe || p.likedByMe), isEmpty);

      await container
          .read(sessionControllerProvider.notifier)
          .signInWithGoogle();
      expect((await feedPost('p_bun_rieu')).savedByMe, isTrue);
      expect((await stats()).saved, before.saved + 1);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
