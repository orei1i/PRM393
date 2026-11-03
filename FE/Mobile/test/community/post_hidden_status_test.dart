// test/community/post_hidden_status_test.dart
// `Hidden` (an admin took the post off the feed) and a status this app doesn't
// know: labels, filters, what the author may still do, and a post that gets
// hidden while it is open.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/feed_controller.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_thread.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_status_banner.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_posts_screen.dart';
import 'package:veganlife_mobile/features/search/data/models/search_models.dart';

const _me = 'u_me';
const _hiddenBanner =
    'Đã ẩn: Ban quản trị đã ẩn bài này nên bài không hiển thị trên bảng tin.';
const _unknownBanner =
    'Chưa rõ trạng thái: bài có thể chưa hiển thị trên bảng tin. Thử tải lại sau.';
const _gone = 'Bài viết này không còn hiển thị.';

PostDto _dto(String id, String status,
        {String author = _me, bool saved = false, int comments = 0}) =>
    PostDto(
      id: id,
      type: 'discussion',
      author: AuthorSummary(id: author, name: 'Minh Anh'),
      title: 'Bài $id',
      body: 'Nội dung bài $id',
      createdAt: DateTime(2026, 10, 31),
      status: status,
      savedByMe: saved,
      commentCount: comments,
    );

/// Answers what the test says, and counts what the app asks.
class _Community implements CommunityApiService {
  _Community({this.mine = const [], this.savedPosts = const []});

  List<PostDto> mine;
  List<PostDto> savedPosts;

  /// By post id: what `getPost` answers; `null` is a 404.
  final answers = <String, PostDto?>{};
  var getPostCalls = 0;
  final liked = <String>[];
  final saved = <String>[];
  var commentsRead = 0;
  var feed = const <PostDto>[];
  Object? commentError;

  @override
  Future<PostDto> getPost(String id) async {
    getPostCalls++;
    if (!answers.containsKey(id)) return _dto(id, 'Published', author: 'u_x');
    final answer = answers[id];
    if (answer == null) {
      throw const ApiException(
          message: 'Bài viết đang chờ duyệt hoặc không khả dụng.',
          statusCode: 404,
          code: 'not_found');
    }
    return answer;
  }

  @override
  Future<FeedPageDto> getFeed({
    PostType? type,
    PostMediaType? mediaType,
    String? cursor,
    int limit = 6,
  }) async =>
      FeedPageDto(items: feed);

  @override
  Future<List<PostDto>> getMyPosts() async => mine;

  @override
  Future<List<PostDto>> getSavedPosts() async => savedPosts;

  @override
  Future<CommentPageDto> getComments(String postId,
      {String? cursor, int limit = 10}) async {
    commentsRead++;
    return const CommentPageDto(items: []);
  }

  @override
  Future<CommentDto> addComment(String postId, String text,
      {String? parentId}) async {
    final error = commentError;
    if (error != null) throw error;
    return CommentDto(
      id: 'c1',
      author: const AuthorSummary(id: _me, name: 'Minh Anh'),
      text: text,
      createdAt: DateTime(2026, 10, 31),
    );
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async =>
      this.liked.add(postId);

  @override
  Future<void> setSaved(String postId, {required bool saved}) async =>
      this.saved.add(postId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(WidgetTester tester, Widget home, _Community api) async {
  tester.view
    ..physicalSize = const Size(411, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'vl.access_token': 'mock.jwt',
    'vl.user_id': _me,
    'vl.display_name': 'Minh Anh',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      communityApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('reading the status', () {
    test('Hidden is its own state, whatever the case', () {
      for (final value in ['Hidden', 'hidden', ' HIDDEN ']) {
        expect(PostStatus.fromApi(value), PostStatus.hidden);
      }
      final post = _dto('p', 'Hidden').toEntity();
      expect(post.isHidden, isTrue);
      expect(post.isPublished, isFalse);
      expect(post.canEdit, isFalse);
      expect(PostStatus.hidden.label, 'Đã ẩn');
    });

    test('a value this app does not know never reads as published', () {
      for (final value in ['Archived', 'weird', '', '  ', null, 3, true]) {
        final status = PostStatus.fromApi(value);
        expect(status, PostStatus.unknown, reason: '$value');
        expect(status, isNot(PostStatus.published));
      }
      expect(PostStatus.unknown.label, isNot(PostStatus.published.label));
    });

    test('a body with no status is unknown, and stays so through the DTO', () {
      final json = {
        'id': 'p',
        'type': 'recipe',
        'author': {'id': 'u', 'fullName': 'Ai đó'},
        'title': 'Bún',
        'body': '…',
        'createdAt': '2026-10-14T02:10:00Z',
      };
      final dto = PostDto.fromJson(json);
      expect(dto.toEntity().status, PostStatus.unknown);
      expect(
          PostDto.fromJson(dto.toJson()).toEntity().status, PostStatus.unknown);
      expect(dto.toEntity().canEdit, isFalse);
    });

    test('the known states can be edited, as before', () {
      for (final status in ['Published', 'Pending', 'Rejected']) {
        expect(_dto('p', status).toEntity().canEdit, isTrue, reason: status);
      }
    });

    test('search shows neither hidden nor unknown posts', () {
      Map<String, dynamic> row(String id, String? status) => {
            'id': id,
            'type': 'recipe',
            'author': {'id': 'u', 'fullName': 'Ai đó'},
            'title': 'Bún',
            'body': '…',
            'createdAt': '2026-10-14T02:10:00Z',
            if (status != null) 'status': status,
          };
      final parsed = SearchResultDto.fromJson({
        'query': 'x',
        'posts': [
          row('ok', 'Published'),
          row('hid', 'Hidden'),
          row('new', 'Archived'),
          row('none', null),
        ],
      }).toEntity();
      expect(parsed.posts.map((p) => p.id), ['ok']);
    });
  });

  group('the feed', () {
    Future<ProviderContainer> ready(_Community api) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        communityApiProvider.overrideWithValue(api),
      ]);
      addTearDown(c.dispose);
      await c.read(feedControllerProvider.future);
      return c;
    }

    test('an edit that comes back hidden leaves it, and so does a 404',
        () async {
      final api = _Community()
        ..feed = [_dto('a', 'Published'), _dto('b', 'Published')];
      final c = await ready(api);
      final feed = c.read(feedControllerProvider.notifier);
      final revision = c.read(communityRevisionProvider);

      feed.postUpdated(_dto('a', 'Hidden').toEntity());
      expect(c.read(feedControllerProvider).requireValue.byId('a'), isNull);

      feed.postGone('b');
      expect(c.read(feedControllerProvider).requireValue.posts, isEmpty);
      expect(c.read(communityRevisionProvider), revision + 2,
          reason: 'the other lists refetch');
    });

    test('a hidden post is not prepended', () async {
      final c = await ready(_Community());
      c
          .read(feedControllerProvider.notifier)
          .prepend(_dto('h', 'Hidden').toEntity());
      expect(c.read(feedControllerProvider).requireValue.posts, isEmpty);
    });
  });

  group('the banner', () {
    for (final (status, text) in [
      ('Hidden', _hiddenBanner),
      ('Weird', _unknownBanner),
    ]) {
      testWidgets('$status says so, with nothing to resubmit', (tester) async {
        await _pump(
          tester,
          Scaffold(
            body: PostStatusBanner(
              post: _dto('p', status).toEntity(),
              onResubmit: () {},
            ),
          ),
          _Community(),
        );
        expect(find.text(text), findsOneWidget);
        expect(find.text('Sửa & gửi lại'), findsNothing);
        expect(find.text('Duyệt thử'), findsNothing);
      });
    }
  });

  group('"Bài của tôi"', () {
    _Community all() => _Community(mine: [
          _dto('live', 'Published'),
          _dto('wait', 'Pending'),
          _dto('hid', 'Hidden'),
          _dto('new', 'Archived'),
        ]);

    testWidgets('a hidden post reads "Đã ẩn", never "Đã đăng"', (tester) async {
      await _pump(tester, const MyPostsScreen(), all());
      expect(find.text('Tất cả (4)'), findsOneWidget);
      expect(find.text('Đã đăng (1)'), findsOneWidget);
      expect(find.text('Đã ẩn (1)'), findsOneWidget);

      await tester.ensureVisible(find.text('Đã ẩn (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đã ẩn (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Bài hid'), findsOneWidget);
      expect(find.text(_hiddenBanner), findsOneWidget);
      expect(find.text('Bài live'), findsNothing);
    });

    testWidgets('its actions are off, and "Sửa bài" is gone, "Xoá bài" stays',
        (tester) async {
      final api = _Community(mine: [_dto('hid', 'Hidden')]);
      await _pump(tester, const MyPostsScreen(), api);
      expect(tester.widget<PostActionsBar>(find.byType(PostActionsBar)).enabled,
          isFalse);

      await tester.tap(find.byTooltip('Tuỳ chọn'));
      await tester.pumpAndSettle();
      expect(find.text('Sửa bài'), findsNothing);
      expect(find.text('Xoá bài'), findsOneWidget);
    });

    testWidgets('a status this app does not know gets a filter of its own',
        (tester) async {
      await _pump(tester, const MyPostsScreen(), all());
      await tester.ensureVisible(find.text('Chưa rõ trạng thái (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chưa rõ trạng thái (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Bài new'), findsOneWidget);
      expect(find.text(_unknownBanner), findsOneWidget);
    });

    testWidgets('that filter only shows when a post is in it', (tester) async {
      await _pump(tester, const MyPostsScreen(),
          _Community(mine: [_dto('live', 'Published')]));
      expect(find.textContaining('Chưa rõ trạng thái'), findsNothing);
    });

    for (final (status, title) in [
      (PostStatus.hidden, 'Không có bài bị ẩn'),
      (PostStatus.unknown, 'Không có bài nào chưa rõ trạng thái'),
    ]) {
      testWidgets('opened on "${status.label}" with none: the empty state',
          (tester) async {
        await _pump(tester, MyPostsScreen(initialStatus: status), _Community());
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('"Đã lưu"', () {
    testWidgets('an own hidden post says why, and can still be taken out',
        (tester) async {
      final api = _Community(savedPosts: [_dto('hid', 'Hidden', saved: true)]);
      await _pump(tester, const MyPostsScreen(initialTab: 1), api);
      expect(find.text(_hiddenBanner), findsOneWidget);
      expect(tester.widget<PostActionsBar>(find.byType(PostActionsBar)).enabled,
          isFalse);

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(api.saved, ['hid']);
    });

    testWidgets('a saved post not saved by me stays off when off the feed',
        (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: PostActionsBar(
            post: _dto('hid', 'Hidden').toEntity(),
            onLike: () => fail('like'),
            onComment: () => fail('comment'),
            onSave: () => fail('save'),
            enabled: false,
          ),
        ),
        _Community(),
      );
      await tester.tap(find.text('Lưu'));
      await tester.pump();
    });
  });

  group('the post detail', () {
    testWidgets('own hidden post: banner, no comments, no composer',
        (tester) async {
      final api = _Community();
      await _pump(
          tester,
          PostDetailScreen(post: _dto('hid', 'Hidden', comments: 3).toEntity()),
          api);
      expect(find.text(_hiddenBanner), findsOneWidget);
      expect(find.text('Bài đang bị ẩn nên không nhận bình luận.'),
          findsOneWidget);
      expect(find.byType(CommentComposer), findsNothing);
      expect(api.commentsRead, 0);
      expect(tester.widget<PostActionsBar>(find.byType(PostActionsBar)).enabled,
          isFalse);

      await tester.tap(find.byTooltip('Tuỳ chọn'));
      await tester.pumpAndSettle();
      expect(find.text('Sửa bài'), findsNothing);
      expect(find.text('Xoá bài'), findsOneWidget);
    });

    testWidgets('unknown status: same, with its own words', (tester) async {
      await _pump(
          tester,
          PostDetailScreen(post: _dto('x', 'Archived').toEntity()),
          _Community());
      expect(find.text(_unknownBanner), findsOneWidget);
      expect(find.text('Chưa rõ trạng thái của bài nên chưa nhận bình luận.'),
          findsOneWidget);
      expect(find.byType(CommentComposer), findsNothing);
    });

    group('on the real BE', () {
      setUp(() => BackendModules.debugOverride({BackendModule.community}));

      testWidgets('opening a post that is gone says so and closes it',
          (tester) async {
        final api = _Community()..answers['p'] = null;
        await _pump(
            tester,
            PostDetailScreen(
                post: _dto('p', 'Published', author: 'u_x').toEntity()),
            api);
        expect(api.getPostCalls, 1);
        expect(find.text(_gone), findsWidgets);
        expect(find.byType(CommentComposer), findsNothing);
        expect(find.byTooltip('Báo cáo'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'hidden while open: the next like finds out, and the composer goes',
          (tester) async {
        final api = _Community()
          ..answers['p'] = _dto('p', 'Published', author: 'u_x');
        await _pump(
            tester,
            PostDetailScreen(
                post: _dto('p', 'Published', author: 'u_x').toEntity()),
            api);
        expect(find.byType(CommentComposer), findsOneWidget);

        api.answers['p'] = null; // what a stranger gets for a hidden post
        await tester.tap(find.text('Thích'));
        await tester.pumpAndSettle();
        expect(api.liked, ['p'], reason: 'the BE still takes it (B69)');
        expect(find.byType(CommentComposer), findsNothing);
        expect(find.text(_gone), findsWidgets);
        expect(
            tester.widget<PostActionsBar>(find.byType(PostActionsBar)).enabled,
            isFalse);
      });

      testWidgets('hidden while its author has it open: the banner appears',
          (tester) async {
        final api = _Community()..answers['p'] = _dto('p', 'Published');
        await _pump(tester,
            PostDetailScreen(post: _dto('p', 'Published').toEntity()), api);
        expect(find.text(_hiddenBanner), findsNothing);

        api.answers['p'] = _dto('p', 'Hidden');
        await tester.enterText(find.byType(TextField), 'Bình luận mới');
        await tester.tap(find.byTooltip('Gửi'));
        await tester.pumpAndSettle();
        expect(find.text(_hiddenBanner), findsOneWidget);
        expect(find.byType(CommentComposer), findsNothing);
      });

      testWidgets('a comment refused with a 404 closes it too', (tester) async {
        final api = _Community()
          ..answers['p'] = _dto('p', 'Published', author: 'u_x');
        await _pump(
            tester,
            PostDetailScreen(
                post: _dto('p', 'Published', author: 'u_x').toEntity()),
            api);
        api
          ..answers['p'] = null
          ..commentError = const ApiException(
              message: 'Không tìm thấy bài viết.', statusCode: 404);
        await tester.enterText(find.byType(TextField), 'Bình luận mới');
        await tester.tap(find.byTooltip('Gửi'));
        await tester.pumpAndSettle();
        expect(find.byType(CommentComposer), findsNothing);
      });

      testWidgets('a post that came back opens its comments', (tester) async {
        final api = _Community()..answers['p'] = _dto('p', 'Published');
        await _pump(tester,
            PostDetailScreen(post: _dto('p', 'Hidden').toEntity()), api);
        expect(find.text(_hiddenBanner), findsNothing);
        expect(find.byType(CommentComposer), findsOneWidget);
        expect(api.commentsRead, 1);
      });

      testWidgets('a failed read changes nothing', (tester) async {
        final api = _FailingRead();
        await _pump(
            tester,
            PostDetailScreen(
                post: _dto('p', 'Published', author: 'u_x').toEntity()),
            api);
        expect(find.byType(CommentComposer), findsOneWidget);
        expect(find.text(_gone), findsNothing);
      });
    });

    testWidgets('the mock asks nothing: nothing changes behind its back',
        (tester) async {
      final api = _Community();
      await _pump(tester,
          PostDetailScreen(post: _dto('p', 'Published').toEntity()), api);
      expect(api.getPostCalls, 0);
    });
  });
}

class _FailingRead extends _Community {
  @override
  Future<PostDto> getPost(String id) async => throw const ApiException(
      message: 'Máy chủ đang gặp sự cố.', statusCode: 500);
}
