// test/community/shell_feed_profile_test.dart
// Split from test/shell_feed_profile_test.dart: FeedFilterChips,
// MockCommunityRepository threads and the profile stats. (The comments page
// is gone: the thread lives in the post detail, see post_detail_test.)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/feed_controller.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/feed_filter_chips.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';

import '../helpers/session_helpers.dart';

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
        home: Scaffold(
            body:
                FeedFilterChips(selected: FeedFilter.all, onSelected: (_) {})),
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
        FeedFilter? picked;

        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: FeedFilterChips(
                    selected: FeedFilter.recipe, onSelected: (f) => picked = f),
              ),
            ),
          ),
        ));

        expect(FeedFilter.values.map((f) => f.label),
            ['Tất cả', 'Công thức', 'Hỏi đáp', 'Có video']);
        for (final label in ['Tất cả', 'Công thức', 'Hỏi đáp', 'Có video']) {
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

        expect(find.text('Video'), findsNothing);
        expect(find.text('Thảo luận'), findsNothing);

        // Off-screen chips are reachable by scrolling sideways.
        await tester.ensureVisible(find.text('Có video'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Có video'));
        expect(picked, FeedFilter.video);
      });
    }
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

    Future<List<CommentDto>> topLevel(String postId) async {
      final all = <CommentDto>[];
      String? cursor;
      do {
        final page = await repo.getComments(postId, cursor: cursor);
        all.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      return all;
    }

    test('every thread (replies included) is as long as the post says',
        () async {
      final posts = await wholeFeed();
      final threads =
          await Future.wait([for (final p in posts) topLevel(p.id)]);
      for (var i = 0; i < posts.length; i++) {
        final total =
            threads[i].fold<int>(0, (sum, c) => sum + 1 + c.replyCount);
        expect(total, posts[i].commentCount, reason: posts[i].id);
        expect(
            threads[i].any((c) =>
                c.author.id == 'u_me' ||
                c.replies.any((r) => r.author.id == 'u_me')),
            isFalse,
            reason: '${posts[i].id} has a comment by the member');
      }
      final bunRieu = posts.singleWhere((p) => p.id == 'p_bun_rieu');
      expect(bunRieu.commentCount, 27);
      expect(threads.expand((t) => t).any((c) => c.replyCount > 0), isTrue,
          reason: 'long threads have replies');
    });

    test('a new comment moves the count and lands on top', () async {
      final before = await repo.getPost('p_sua_chua_dua');
      final added = await repo.addComment('p_sua_chua_dua', 'Ngon quá!');
      final after = await repo.getPost('p_sua_chua_dua');
      final first = await repo.getComments('p_sua_chua_dua');
      expect(after.commentCount, before.commentCount + 1);
      expect(first.items.first.id, added.id);
      expect(first.items.first.text, 'Ngon quá!');
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

      await signInAs(container, minhAnhAccount);
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

      await signInAs(container, minhAnhAccount);
      expect((await feedPost('p_bun_rieu')).savedByMe, isTrue);
      expect((await stats()).saved, before.saved + 1);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
