// test/hybrid/community_contract_test.dart
// The real community, media and Reels services on recorded BE bodies, through
// the real Dio pipeline. No network.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/backend_posts.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/comment_thread_controller.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/feed_controller.dart';
import 'package:veganlife_mobile/features/reels/data/reels_api_service.dart';
import 'package:veganlife_mobile/features/reels/presentation/controllers/reels_controller.dart';

import 'planner_test_support.dart';

const _postId = '6ae5a8876c01fc07a925777c';
const _commentId = '6ae5a8886c01fc07a9257799';

/// A recorded page; [nextCursor] replaces the one it has, `null` ends the feed.
Map<String, dynamic> _feedPage(String name, {required String? nextCursor}) {
  final body = fixture(name);
  (body['data'] as Map)['nextCursor'] = nextCursor;
  return body;
}

/// A feed of [pages] pages, walked by cursor (`c2`, `c3`…), whose items belong
/// to [authorOf] (a page, an item).
Answer _scanFeed(int pages, String Function(int page, int item) authorOf) =>
    (request) {
      final cursor = request.queryParameters['cursor'] as String?;
      final page = cursor == null ? 1 : int.parse(cursor.substring(1));
      return (
        200,
        envelope({
          'items': [
            for (var i = 0; i < 2; i++)
              {
                'id': 'post_${page}_$i',
                'type': 'recipe',
                'author': {'id': authorOf(page, i), 'fullName': 'Ai đó'},
                'title': 'Bài $page.$i',
                'body': 'Nội dung',
                'createdAt': '2026-10-31T07:19:11.908Z',
                'status': 'Published',
                'mediaType': 'Text',
                'likeCount': 3,
              }
          ],
          'nextCursor': page < pages ? 'c${page + 1}' : null,
          'page': 1,
          'pageSize': 50,
          'totalItems': pages * 2,
          'totalPages': pages,
        })
      );
    };

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  CommunityApiService api(ProviderContainer c) => c.read(communityApiProvider);

  group('feed paging', () {
    test('asks by limit, then by the cursor the BE gave', () async {
      final backend = FakeBackend()
        ..on(
            'GET /posts',
            200,
            _feedPage('community_fixture_feed_page1.json',
                nextCursor: 'post_6'));
      final c = await backendContainer(backend);

      final first = await api(c).getFeed(limit: 6);
      expect(first.items, hasLength(6));
      expect(first.nextCursor, 'post_6');

      await api(c).getFeed(
          type: PostType.discussion,
          mediaType: PostMediaType.video,
          cursor: first.nextCursor);
      expect(backend.seen.first.queryParameters, {'limit': 6});
      expect(backend.seen.last.queryParameters, {
        'type': 'discussion',
        'mediaType': 'Video',
        'cursor': 'post_6',
        'limit': 6,
      });
    });

    test('no nextCursor ends it', () async {
      final backend = FakeBackend()
        ..on('GET /posts', 200,
            _feedPage('community_fixture_feed_page2.json', nextCursor: null));
      final c = await backendContainer(backend);

      final last = await api(c).getFeed(cursor: 'post_6');
      expect(last.items, hasLength(6));
      expect(last.nextCursor, isNull);
    });

    test('limit stays within the BE limit', () async {
      final backend = FakeBackend()
        ..on('GET /posts', 200,
            _feedPage('community_fixture_feed_page1.json', nextCursor: null));
      final c = await backendContainer(backend);
      await api(c).getFeed(limit: 200);
      expect(backend.seen.single.queryParameters['limit'], 50);
    });

    test('load more walks every page once and stops: no loop, no duplicates',
        () async {
      final backend = FakeBackend();
      backend.routes['GET /posts'] = (request) => (
            200,
            request.queryParameters['cursor'] == null
                ? _feedPage('community_fixture_feed_page1.json',
                    nextCursor: 'post_6')
                : _feedPage('community_fixture_feed_page2.json',
                    nextCursor: null)
          );
      final c = await backendContainer(backend);
      final feed = c.read(feedControllerProvider.notifier);
      await c.read(feedControllerProvider.future);

      for (var i = 0; i < 5; i++) {
        await feed.loadMore();
      }
      final state = c.read(feedControllerProvider).requireValue;
      expect(state.hasMore, isFalse);
      expect(state.posts, hasLength(12));
      expect(state.posts.map((p) => p.id).toSet(), hasLength(12));
      expect(backend.calls, ['GET /posts', 'GET /posts']);
    });

    test('a post seen twice is shown once', () async {
      final backend = FakeBackend();
      backend.routes['GET /posts'] = (request) => (
            200,
            _feedPage('community_fixture_feed_page1.json',
                nextCursor:
                    request.queryParameters['cursor'] == null ? 'post_6' : null)
          );
      final c = await backendContainer(backend);
      final feed = c.read(feedControllerProvider.notifier);
      await c.read(feedControllerProvider.future);

      await feed.loadMore();
      final state = c.read(feedControllerProvider).requireValue;
      expect(state.posts, hasLength(6));
      expect(state.hasMore, isFalse);
    });
  });

  group('post shape', () {
    test('an uploaded video: absolute URL, Video type, labelled sample recipe',
        () async {
      final backend = FakeBackend()
        ..on('GET /posts/$_postId', 200,
            fixture('community_fixture_post_get.json'));
      final c = await backendContainer(backend);

      final raw =
          fixtureData<Map<String, dynamic>>('community_fixture_post_get.json');
      expect(raw['mediaUrl'], startsWith('/uploads/videos/'));
      expect(raw['video'], isNull);

      final post = (await api(c).getPost(_postId)).toEntity();
      expect(post.mediaUrl, '${Env.apiOrigin}${raw['mediaUrl']}');
      expect(post.mediaType, PostMediaType.video);
      expect(post.hasVideo, isTrue);
      expect(post.type, PostType.recipe);
      // Module `video` is mock for now; the real-module case is guarded in
      // video_sample_recipe_test.dart, and the sheet labels the sample.
      expect(post.videoId, post.id);
      expect(post.videoDurationSeconds, isNull);
      expect(post.hasAiRecipe, isTrue);
    });

    test('a video from the BE is read as it comes', () async {
      final body = fixture('community_fixture_post_get.json');
      (body['data'] as Map)['video'] = {
        'id': 'vid_1',
        'durationSeconds': 42,
        'aiStatus': 'ready',
      };
      final backend = FakeBackend()..on('GET /posts/$_postId', 200, body);
      final c = await backendContainer(backend);
      expect((await api(c).getPost(_postId)).videoId, 'vid_1');
    });

    test('an uploaded photo shows from its absolute URL', () async {
      final backend = FakeBackend()
        ..on('GET /posts/$_postId', 200,
            fixture('community_fixture_post_image.json'));
      final c = await backendContainer(backend);
      final raw = fixtureData<Map<String, dynamic>>(
          'community_fixture_post_image.json');
      final post = (await api(c).getPost(_postId)).toEntity();
      expect(post.imageSrc, '${Env.apiOrigin}${raw['mediaUrl']}');
    });

    test('a text post has no attachment', () async {
      final backend = FakeBackend()
        ..on('GET /posts/$_postId', 200,
            fixture('community_fixture_post_discussion.json'));
      final c = await backendContainer(backend);
      final post = (await api(c).getPost(_postId)).toEntity();
      expect(post.type, PostType.discussion);
      expect(post.mediaType, PostMediaType.text);
      expect(post.mediaUrl, isNull);
      expect(post.hasCover, isFalse);
    });

    test('a Cloudinary URL stays as it is', () async {
      const url = 'https://res.cloudinary.com/x/video/upload/v1/a.mp4';
      final adapted = adaptBackendPost(
          const {'id': 'p', 'mediaUrl': url, 'mediaType': 'Video'}, null);
      expect(adapted['mediaUrl'], url);
    });

    test('POST /posts sends the raw upload URL and shows the absolute one',
        () async {
      final created = fixture('community_fixture_post_image.json');
      final rawUrl =
          ((created['data'] as Map)['mediaUrl'] as String?).toString();
      final backend = FakeBackend()..on('POST /posts', 201, created);
      final c = await backendContainer(backend);

      final post = await api(c).createPost(CreatePostRequestDto(
        type: PostType.recipe,
        title: 'Đậu hũ sốt cà tại nhà',
        body: 'Nguyên liệu đơn giản.',
        mediaType: PostMediaType.image,
        mediaUrl: rawUrl,
      ));

      final body = backend.bodyOf('POST /posts');
      expect(body['mediaUrl'], rawUrl);
      expect(body['mediaType'], 'Image');
      expect(body['type'], 'recipe');
      expect(post.mediaUrl, '${Env.apiOrigin}$rawUrl');
    });

    test('the BE refusing an absolute URL reads in Vietnamese', () async {
      final backend = FakeBackend()
        ..on('POST /posts', 400,
            fixture('community_fixture_post_absolute_url_400.json'));
      final c = await backendContainer(backend);
      await expectLater(
        api(c).createPost(const CreatePostRequestDto(
            type: PostType.recipe, title: 'Tiêu đề', body: 'Nội dung')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            'Tài nguyên media không tồn tại hoặc không thuộc quyền sở hữu của bạn.')),
      );
    });
  });

  test('a video post with no text: the BE message, in Vietnamese', () async {
    final backend = FakeBackend()
      ..on('POST /posts', 400,
          fixture('community_fixture_post_empty_body_400.json'));
    final c = await backendContainer(backend);
    await expectLater(
      api(c).createPost(const CreatePostRequestDto(
          type: PostType.recipe, title: 'Tiêu đề', body: '')),
      throwsA(isA<ApiException>().having(
          (e) => e.message, 'message', 'Nội dung bài viết là bắt buộc.')),
    );
  });

  group('likes', () {
    test('liking is one POST (PUT and DELETE are 405 on the BE)', () async {
      final backend = FakeBackend()
        ..on('POST /posts/$_postId/like', 200,
            fixture('community_fixture_like_on.json'));
      final c = await backendContainer(backend);
      await api(c).setLiked(_postId, liked: true);
      expect(backend.calls, ['POST /posts/$_postId/like']);
    });

    test('unliking is one POST', () async {
      final backend = FakeBackend()
        ..on('POST /posts/$_postId/like', 200,
            fixture('community_fixture_like_off.json'));
      final c = await backendContainer(backend);
      await api(c).setLiked(_postId, liked: false);
      expect(backend.calls, hasLength(1));
    });

    test('the toggle landing on the wrong state is toggled back', () async {
      var liked = true; // already liked on another device
      final backend = FakeBackend();
      backend.routes['POST /posts/$_postId/like'] = (_) {
        liked = !liked;
        return (200, envelope({'liked': liked, 'likeCount': liked ? 1 : 0}));
      };
      final c = await backendContainer(backend);
      await api(c).setLiked(_postId, liked: true);
      expect(liked, isTrue);
      expect(backend.calls, hasLength(2));
    });
  });

  group('reports', () {
    late FakeBackend backend;
    late ProviderContainer c;

    setUp(() async {
      backend = FakeBackend()
        ..on('POST /posts/$_postId/reports', 200,
            fixture('community_fixture_report_ok.json'));
      c = await backendContainer(backend);
    });

    Map<String, dynamic> sent() =>
        backend.bodyOf('POST /posts/$_postId/reports');

    test('only reason is sent, with the note in it', () async {
      await api(c).reportPost(_postId,
          reason: ReportReason.spamPromo, note: ' Quảng cáo lặp lại ');
      expect(sent(), {'reason': 'spam_promo: Quảng cáo lặp lại'});
    });

    test('no note, or an empty one', () async {
      await api(c)
          .reportPost(_postId, reason: ReportReason.spamPromo, note: '  ');
      expect(sent(), {'reason': 'spam_promo'});
    });

    test('at most 500 characters', () async {
      await api(c)
          .reportPost(_postId, reason: ReportReason.spamPromo, note: 'x' * 600);
      expect(sent()['reason'], hasLength(500));
      expect(sent()['reason'], startsWith('spam_promo: xxx'));
    });

    test('reporting twice: the BE message', () async {
      backend.on('POST /posts/$_postId/reports', 409,
          fixture('community_fixture_report_409.json'));
      await expectLater(
        api(c).reportPost(_postId, reason: ReportReason.spamPromo),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.message, 'message',
                'Bạn đã báo cáo bài viết này rồi.')),
      );
    });
  });

  group('comments', () {
    FakeBackend commentsBackend() {
      final backend = FakeBackend();
      backend.routes['GET /posts/$_postId/comments'] = (request) => (
            200,
            fixture(request.queryParameters['page'] == 1
                ? 'community_fixture_comments_page1.json'
                : 'community_fixture_comments_page2.json')
          );
      return backend;
    }

    test('pages by page and pageSize; a short page ends it', () async {
      final backend = commentsBackend();
      final c = await backendContainer(backend);

      final first = await api(c).getComments(_postId, limit: 10);
      expect(first.items, hasLength(10));
      expect(first.nextCursor, '2');
      final second = await api(c).getComments(_postId, cursor: '2', limit: 10);
      expect(second.items, hasLength(1));
      expect(second.nextCursor, isNull);
      expect(backend.seen.first.queryParameters, {'page': 1, 'pageSize': 10});
      expect(backend.seen.last.queryParameters, {'page': 2, 'pageSize': 10});
    });

    test('an empty page after a full one ends it', () async {
      final backend = FakeBackend()
        ..on('GET /posts/$_postId/comments', 200, envelope(const []));
      final c = await backendContainer(backend);
      final page = await api(c).getComments(_postId, cursor: '2');
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test(
        '"(đã sửa)" follows `updatedAt`, which the BE leaves empty until a '
        'real edit (B17)', () async {
      final raw =
          fixtureData<List<Object?>>('community_fixture_comments_page1.json')
              .first as Map<String, dynamic>;
      final never = {
        ...raw,
        'updatedAt': null,
        'replies': [
          {...raw, 'id': 'r1', 'parentId': raw['id'], 'updatedAt': null},
        ],
      };
      final backend = FakeBackend()
        ..on('GET /posts/$_postId/comments', 200, envelope([never, raw]));
      final c = await backendContainer(backend);
      final page = (await api(c).getComments(_postId)).toEntity();
      expect(page.items.first.isEdited, isFalse);
      expect(page.items.first.replies.single.isEdited, isFalse);
      expect(page.items.last.isEdited, isTrue, reason: 'a real edit');
    });

    test('previews and the true reply count', () async {
      final c = await backendContainer(commentsBackend());
      final thread = CommentThreadController(
        api: api(c),
        postId: _postId,
        initialCount: 14,
        me: () => const AuthorSummary(id: testUserId, name: 'FE Test'),
      );
      addTearDown(thread.dispose);

      await thread.loadMore();
      expect(thread.threads, hasLength(10));
      expect(thread.hasMore, isTrue);
      final first = thread.threads.first;
      expect(first.comment.replyCount, 3);
      expect(first.replies, hasLength(2));
      expect(first.hiddenReplies, 1);

      await thread.loadMore();
      expect(thread.threads, hasLength(11));
      expect(thread.hasMore, isFalse);
      await thread.loadMore();
      expect(thread.threads, hasLength(11));
    });

    test('replies past the preview: the route answers with all of them',
        () async {
      final reply = fixtureData<Map<String, dynamic>>(
          'community_fixture_comment_reply.json');
      final backend = FakeBackend()
        ..on(
            'GET /posts/$_postId/comments/$_commentId/replies',
            200,
            envelope([
              for (var i = 0; i < 4; i++)
                {
                  ...reply,
                  'id': 'reply_$i',
                  'updatedAt': null,
                },
            ]));
      final c = await backendContainer(backend);
      final page = await api(c).getReplies(_postId, _commentId);
      expect(page.items.map((r) => r.id),
          ['reply_0', 'reply_1', 'reply_2', 'reply_3']);
      expect(page.nextCursor, isNull);
      expect(page.items.first.toEntity().isEdited, isFalse);
      expect(backend.seen.single.queryParameters, isEmpty);
    });

    test('"Xem thêm": the thread ends up with every reply', () async {
      final reply = fixtureData<Map<String, dynamic>>(
          'community_fixture_comment_reply.json');
      final backend = commentsBackend();
      final c = await backendContainer(backend);
      final thread = CommentThreadController(
        api: api(c),
        postId: _postId,
        initialCount: 14,
        me: () => const AuthorSummary(id: testUserId, name: 'FE Test'),
      );
      addTearDown(thread.dispose);
      await thread.loadMore();
      final first = thread.threads.first;
      backend.on(
          'GET /posts/$_postId/comments/${first.comment.id}/replies',
          200,
          envelope([
            for (final (i, r) in first.replies.indexed)
              {
                ...reply,
                'id': r.id,
                'parentId': first.comment.id,
                'createdAt': '2026-10-31T07:2$i:00Z',
              },
            {
              ...reply,
              'id': 'the_third',
              'parentId': first.comment.id,
              'createdAt': '2026-10-31T07:29:00Z',
            },
          ]));

      await thread.loadReplies(first.comment.id);

      final after = thread.threadOf(first.comment.id)!;
      expect(after.replies, hasLength(3));
      expect(after.replies.map((r) => r.id), contains('the_third'));
      expect(after.hiddenReplies, 0);
    });

    test('adding a comment and a reply', () async {
      final backend = FakeBackend()
        ..on('POST /posts/$_postId/comments', 201,
            fixture('community_fixture_comment_reply.json'));
      final c = await backendContainer(backend);
      final reply =
          await api(c).addComment(_postId, 'Phản hồi', parentId: _commentId);
      expect(reply.parentId, isNotNull);
      expect(reply.toEntity().isEdited, isFalse);
      expect(backend.bodyOf('POST /posts/$_postId/comments'),
          {'content': 'Phản hồi', 'parentId': _commentId});
    });

    test('deleting goes to /comments/{id}', () async {
      final backend = FakeBackend()
        ..on('DELETE /comments/$_commentId', 200,
            fixture('community_fixture_comment_deleted.json'));
      final c = await backendContainer(backend);
      await api(c).deleteComment(_postId, _commentId);
      expect(backend.calls, ['DELETE /comments/$_commentId']);
    });

    test('"my comments": read from the route, with the post they are on',
        () async {
      final backend = FakeBackend()
        ..on(
            'GET /users/me/comments',
            200,
            envelope([
              {
                'id': _commentId,
                'postId': _postId,
                'postTitle': 'Bài có bình luận',
                'parentId': null,
                'content': 'Ngon quá',
                'createdAt': '2026-10-31T07:19:11Z',
                'updatedAt': null,
              },
            ]));
      final c = await backendContainer(backend);
      final mine = await api(c).getMyComments();
      expect(mine.single.text, 'Ngon quá');
      expect(mine.single.postId, _postId);
      expect(mine.single.postTitle, 'Bài có bình luận');
      expect(mine.single.updatedAt, isNull);
    });
  });

  group('deleting a post', () {
    test('the member\'s own', () async {
      final backend = FakeBackend()
        ..on('DELETE /posts/$_postId', 200,
            fixture('community_fixture_post_deleted.json'));
      final c = await backendContainer(backend);
      await api(c).setSaved(_postId, saved: true);
      await api(c).deletePost(_postId);
      expect(backend.calls, ['DELETE /posts/$_postId']);
      expect(c.read(savedPostsStoreProvider).ids, isEmpty);
    });
  });

  group('saved posts stay on this device (D8)', () {
    test('saving asks nothing and survives a restart of the app', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend);

      await api(c).setSaved('a', saved: true);
      await api(c).setSaved('b', saved: true);
      expect(backend.seen, isEmpty);
      expect(
          c
              .read(sharedPreferencesProvider)
              .getStringList('vl.saved_posts.$testUserId'),
          ['b', 'a']);

      await api(c).setSaved('a', saved: false);
      expect(c.read(savedPostsStoreProvider).ids, ['b']);
    });

    test('the feed, the post and Reels show them as saved', () async {
      final page =
          _feedPage('community_fixture_feed_page1.json', nextCursor: null);
      final video = fixture('community_fixture_feed_video.json');
      final savedId = (((page['data'] as Map)['items'] as List).first
          as Map)['id'] as String;
      final videoId = (((video['data'] as Map)['items'] as List).first
          as Map)['id'] as String;
      final backend = FakeBackend();
      backend.routes['GET /posts'] = (request) =>
          (200, request.queryParameters['mediaType'] == 'Video' ? video : page);
      final c = await backendContainer(backend);
      await api(c).setSaved(savedId, saved: true);
      await api(c).setSaved(videoId, saved: true);

      final items = (await api(c).getFeed()).items;
      expect(items.where((p) => p.savedByMe).map((p) => p.id), [savedId]);

      final reels = await c.read(reelsApiProvider).getReels();
      expect(reels.where((r) => r.post.savedByMe).map((r) => r.post.id),
          [videoId]);
    });

    test('each account has its own list; guests have none', () async {
      final c = await backendContainer(FakeBackend());
      await api(c).setSaved('a', saved: true);
      final other = SavedPostsStore(
          prefs: c.read(sharedPreferencesProvider),
          currentUserId: () => 'someone_else');
      expect(other.ids, isEmpty);
      final guest = SavedPostsStore(
          prefs: c.read(sharedPreferencesProvider), currentUserId: () => null);
      expect(guest.contains('a'), isFalse);
      await expectLater(guest.setSaved('a', saved: true),
          throwsA(isA<ApiException>().having((e) => e.statusCode, '', 401)));
    });

    test('the list fetches each post, newest saved first, and skips a gone one',
        () async {
      final post = fixture('community_fixture_post_get.json');
      final backend = FakeBackend()
        ..on('GET /posts/kept_old', 200, post)
        ..on('GET /posts/gone', 404, fixture('community_fixture_post_404.json'))
        ..on('GET /posts/kept_new', 200, {
          ...post,
          'data': {...post['data'] as Map, 'title': 'Mới lưu'},
        });
      final c = await backendContainer(backend);
      for (final id in ['kept_old', 'gone', 'kept_new']) {
        await api(c).setSaved(id, saved: true);
      }

      final saved = await api(c).getSavedPosts();
      expect(saved, hasLength(2));
      expect(saved.first.title, 'Mới lưu');
      // Hidden by reports may come back: it stays in the list.
      expect(c.read(savedPostsStoreProvider).contains('gone'), isTrue);
    });

    test('a failure other than 404 is an error, not an empty list', () async {
      final backend = FakeBackend()
        ..on('GET /posts/a', 500, {'success': false, 'message': 'Lỗi máy chủ'});
      final c = await backendContainer(backend);
      await api(c).setSaved('a', saved: true);
      await expectLater(api(c).getSavedPosts(), throwsA(isA<ApiException>()));
    });
  });

  group('my posts come from GET /users/me/posts', () {
    Map<String, dynamic> post(String id, String status, String createdAt) => {
          'id': id,
          'type': 'recipe',
          'author': {'id': testUserId, 'fullName': 'FE Test'},
          'title': 'Bài $id',
          'body': 'Nội dung',
          'createdAt': createdAt,
          'status': status,
          'mediaType': 'Text',
        };

    test('walks the pages by cursor, until the last one', () async {
      final backend = FakeBackend();
      backend.routes['GET /users/me/posts'] =
          _scanFeed(2, (page, i) => testUserId);
      final c = await backendContainer(backend);

      final mine = await api(c).getMyPosts();
      expect(mine.map((p) => p.id),
          ['post_1_0', 'post_1_1', 'post_2_0', 'post_2_1']);
      expect(backend.seen, hasLength(2));
      expect(backend.seen.first.queryParameters, {'limit': 50});
      expect(backend.seen.last.queryParameters, {'cursor': 'c2', 'limit': 50});
      expect((api(c) as RemoteCommunityApiService).myPostsTruncated, isFalse);
    });

    test('stops after 5 pages and says so', () async {
      final backend = FakeBackend();
      backend.routes['GET /users/me/posts'] =
          _scanFeed(9, (_, __) => testUserId);
      final c = await backendContainer(backend);

      expect(await api(c).getMyPosts(), hasLength(10));
      expect(backend.seen, hasLength(5));
      expect((api(c) as RemoteCommunityApiService).myPostsTruncated, isTrue);
    });

    test('exactly 5 pages is not cut short', () async {
      final backend = FakeBackend();
      backend.routes['GET /users/me/posts'] =
          _scanFeed(5, (_, __) => testUserId);
      final c = await backendContainer(backend);
      await api(c).getMyPosts();
      expect((api(c) as RemoteCommunityApiService).myPostsTruncated, isFalse);
    });

    test('a guest has none and asks nothing', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend, signedIn: false);
      expect(await api(c).getMyPosts(), isEmpty);
      expect(backend.seen, isEmpty);
    });

    test('every status is listed, each as it stands', () async {
      final backend = FakeBackend()
        ..on(
            'GET /users/me/posts',
            200,
            envelope({
              'items': [
                post('wait', 'Pending', '2026-10-31T07:19:11Z'),
                post('hid', 'Hidden', '2026-10-30T07:19:11Z'),
                post('new', 'Archived', '2026-10-29T07:19:11Z'),
                post('live', 'Published', '2026-10-28T07:19:11Z'),
              ],
              'nextCursor': null,
            }));
      final c = await backendContainer(backend);
      final mine = [for (final p in await api(c).getMyPosts()) p.toEntity()];
      expect(mine.map((p) => p.status), [
        PostStatus.pending,
        PostStatus.hidden,
        PostStatus.unknown,
        PostStatus.published,
      ]);
      expect(mine[1].isPublished, isFalse);
    });

    test('a feed row with a status this app does not know stays off the feed',
        () async {
      final backend = FakeBackend()
        ..on(
            'GET /posts',
            200,
            envelope({
              'items': [
                post('live', 'Published', '2026-10-31T07:19:11Z'),
                post('new', 'Archived', '2026-10-31T07:19:11Z'),
                post('hid', 'Hidden', '2026-10-31T07:19:11Z'),
              ],
              'nextCursor': null,
            }));
      final c = await backendContainer(backend);
      final page = await api(c).getFeed();
      expect(page.items.map((p) => p.id), ['live']);
    });

    test('a failure is an error, not an empty list', () async {
      final backend = FakeBackend()
        ..on('GET /users/me/posts', 500,
            {'success': false, 'message': 'Lỗi máy chủ'});
      final c = await backendContainer(backend);
      await expectLater(api(c).getMyPosts(), throwsA(isA<ApiException>()));
    });
  });

  group('PUT /posts/{id}', () {
    test('the body of POST /posts, with the raw media URL', () async {
      final backend = FakeBackend()
        ..on(
            'PUT /posts/$_postId',
            200,
            envelope({
              'id': _postId,
              'type': 'discussion',
              'author': {'id': testUserId, 'fullName': 'FE Test'},
              'title': 'Tiêu đề mới',
              'body': 'Nội dung mới',
              'createdAt': '2026-10-31T07:19:11Z',
              'status': 'Pending',
              'mediaType': 'Image',
              'mediaUrl': '/uploads/images/a.png',
            }));
      final c = await backendContainer(backend);

      final saved = await api(c).updatePost(
          _postId,
          UpdatePostRequestDto(
            type: PostType.discussion,
            title: 'Tiêu đề mới',
            body: 'Nội dung mới',
            tags: const ['quick'],
            mediaType: PostMediaType.image,
            mediaUrl: '${Env.apiOrigin}/uploads/images/a.png',
          ));
      expect(saved.toEntity().isPending, isTrue);
      expect(saved.mediaUrl, '${Env.apiOrigin}/uploads/images/a.png');
      expect(backend.bodyOf('PUT /posts/$_postId'), {
        'type': 'discussion',
        'title': 'Tiêu đề mới',
        'body': 'Nội dung mới',
        'tags': ['quick'],
        'mediaType': 'Image',
        'mediaUrl': '/uploads/images/a.png',
        'restaurantId': null,
      });
    });

    test("today's 405 is an error, never a saved post", () async {
      final backend = FakeBackend()..on('PUT /posts/$_postId', 405, null);
      final c = await backendContainer(backend);
      await expectLater(
        api(c).updatePost(
            _postId,
            const UpdatePostRequestDto(
                title: 'Tiêu đề',
                body: 'Nội dung',
                mediaType: PostMediaType.text)),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('media', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('vl_media'));
    tearDown(() => dir.deleteSync(recursive: true));

    String file(String name) {
      final f = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3, 4]);
      return f.path;
    }

    test('an image: multipart "file", raw and absolute URLs', () async {
      final backend = FakeBackend()
        ..on('POST /media/images', 200,
            fixture('community_fixture_media_image.json'));
      final c = await backendContainer(backend);

      final uploaded = await c.read(mediaApiProvider).uploadImage(
            PickedMedia.image(
                name: 'dau_hu.png', sizeBytes: 4, path: file('dau_hu.png')),
          );

      expect(uploaded.mediaUrl, startsWith('/uploads/images/'));
      expect(uploaded.absoluteUrl, '${Env.apiOrigin}${uploaded.mediaUrl}');
      expect(uploaded.width, 800);
      final form = backend.seen.single.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'dau_hu.png');
    });

    test('a video', () async {
      final backend = FakeBackend()
        ..on('POST /media/videos', 200,
            fixture('community_fixture_media_video.json'));
      final c = await backendContainer(backend);

      final uploaded = await c.read(mediaApiProvider).uploadVideo(
            PickedMedia.video(
                name: 'banh_xeo.mp4',
                sizeBytes: 4,
                durationSeconds: 0,
                path: file('banh_xeo.mp4')),
          );
      expect(uploaded.mediaUrl, startsWith('/uploads/videos/'));
      expect(uploaded.absoluteUrl, startsWith('${Env.apiOrigin}/uploads/'));
      expect(uploaded.durationSeconds, 0, reason: 'the BE sends null');
    });

    test('a file that cannot be read says so before any request', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend);
      await expectLater(
        c.read(mediaApiProvider).uploadImage(
            const PickedMedia.image(name: 'mau.jpg', sizeBytes: 1)),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'no_file')),
      );
      expect(backend.seen, isEmpty);
    });

    test('a Cloudinary URL is already absolute', () {
      const url = 'https://res.cloudinary.com/x/a.jpg';
      expect(
          const UploadedImageDto(mediaUrl: url, sizeBytes: 1).absoluteUrl, url);
    });

    test('the limits follow the module', () {
      const big = PickedMedia.video(
          name: 'a.mp4', sizeBytes: 150 * 1024 * 1024, durationSeconds: 1);
      expect(MediaUploadRules.maxVideoBytes, 100 * 1024 * 1024);
      expect(MediaUploadRules.videoHint, 'Video MP4, MOV, WEBM tối đa 100 MB');
      expect(MediaUploadRules.validate(big), 'Video vượt quá 100 MB');
      expect(MediaUploadRules.statusFor(big), 413);

      BackendModules.debugOverride(const {});
      expect(MediaUploadRules.videoHint, 'Video MP4, MOV, WEBM tối đa 200 MB');
      expect(MediaUploadRules.validate(big), isNull);
    });
  });

  group('reels', () {
    test('page 1 by pageSize, absolute URL, labelled sample recipe', () async {
      final body = fixture('community_fixture_feed_video.json');
      final raw = (((body['data'] as Map)['items'] as List).first
          as Map)['mediaUrl'] as String;
      final backend = FakeBackend()..on('GET /posts', 200, body);
      final c = await backendContainer(backend);

      final reels = await c.read(reelsApiProvider).getReels(limit: 20);

      expect(backend.seen.single.queryParameters,
          {'mediaType': 'Video', 'page': 1, 'pageSize': 20});
      expect(reels, hasLength(2));
      final reel = reels.first.toEntity();
      expect(reel.videoUrl, '${Env.apiOrigin}$raw');
      expect(reel.post.mediaUrl, '${Env.apiOrigin}$raw');
      expect(reel.post.videoId, reel.post.id);
      expect(reel.post.hasAiRecipe, isTrue);
      expect(reel.durationSeconds, isNull);
    });

    test('the Bếp nhanh strip reads them', () async {
      final backend = FakeBackend()
        ..on('GET /posts', 200, fixture('community_fixture_feed_video.json'));
      final c = await backendContainer(backend);
      expect(await c.read(reelsProvider.future), hasLength(2));
    });

    test('a video post with no file is not a reel', () async {
      final body = fixture('community_fixture_feed_video.json');
      (((body['data'] as Map)['items'] as List).first as Map)['mediaUrl'] =
          null;
      final backend = FakeBackend()..on('GET /posts', 200, body);
      final c = await backendContainer(backend);
      expect(await c.read(reelsApiProvider).getReels(), hasLength(1));
    });
  });
}
