// test/community/post_approval_test.dart
// New and edited posts wait for an admin (mock), and whatever status the server
// answers is honoured (real): what the author sees, what everyone else doesn't,
// and "Sửa bài" from the feed, the post page and "Nội dung của tôi".
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_thread.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_status_banner.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_posts_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.user_id': 'u_me',
  'vl.display_name': 'Minh Anh',
  'vl.role': 'User',
};

const _waiting =
    'Chờ duyệt: bài sẽ hiển thị trên bảng tin sau khi Ban quản trị duyệt.';

MockCommunityRepository _repo({String me = 'u_me', bool signedIn = true}) =>
    MockCommunityRepository(
      currentUserName: () => 'Minh Anh',
      isSignedIn: () => signedIn,
      currentUserId: () => me,
    );

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const [],
    Size size = const Size(411, 900)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(_minhAnh);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides
    ],
    child: MaterialApp(home: home),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

/// A new post of Minh Anh's, approved or still waiting.
Future<Post> _seedOwn(WidgetTester tester, String title,
    {PostMediaType media = PostMediaType.text,
    String? mediaUrl,
    bool approved = true}) async {
  final repo = _repo();
  final created = (await tester.runAsync(() => repo.createPost(
        CreatePostRequestDto(
          type: PostType.discussion,
          title: title,
          body: 'Nội dung đủ dài để được đăng lên bảng tin.',
          mediaType: media,
          mediaUrl: mediaUrl,
        ),
      )))!;
  if (!approved) return created.toEntity();
  return (await tester
          .runAsync(() => repo.demoDecide(created.id, approve: true)))!
      .toEntity();
}

Future<void> _editTitle(WidgetTester tester, String title) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Tiêu đề'), title);
  await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
  await _wait(tester, 2500);
}

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('mock rule', () {
    test('the author sees a waiting post, nobody else does', () async {
      final repo = _repo();
      final post = await repo.createPost(const CreatePostRequestDto(
          type: PostType.recipe,
          title: 'Canh chua chay miền Tây',
          body: 'Bạc hà, cà chua, thơm, nêm nhạt rồi rắc rau om.'));
      expect(post.status, 'Pending');
      expect((await repo.getMyPosts()).map((p) => p.id), contains(post.id));
      expect((await repo.getPost(post.id)).status, 'Pending');

      final other = _repo(me: 'u_chef_tam');
      await expectLater(other.getPost(post.id), throwsException);
      await expectLater(
          _repo(signedIn: false).getPost(post.id), throwsException);
      final feed = await other.getFeed(limit: 50);
      expect(feed.items.map((p) => p.id), isNot(contains(post.id)));
    });

    test('a video post goes through the same way, keeping its media', () async {
      final repo = _repo();
      final post = await repo.createPost(const CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Video hỏi về chảo chống dính',
          body: 'Mọi người xem giúp mình loại chảo trong video.',
          mediaType: PostMediaType.video,
          mediaUrl: 'https://cdn.test/v.mp4'));
      expect(post.status, 'Pending');
      final edited = await repo.updatePost(
          post.id,
          UpdatePostRequestDto(
              title: 'Video hỏi về chảo gang',
              body: post.body,
              mediaType: PostMediaType.video,
              mediaUrl: post.mediaUrl));
      expect(edited.status, 'Pending');
      expect(edited.mediaType, 'Video');
      expect(edited.mediaUrl, 'https://cdn.test/v.mp4');
      expect(
          (await repo.demoDecide(post.id, approve: true)).status, 'Published');
    });
  });

  group('author flow (mock)', () {
    testWidgets('posting: not on the feed; the message says why',
        (tester) async {
      await _pump(tester, const FeedScreen(), size: const Size(411, 1600));
      await _wait(tester);
      await tester.tap(find.textContaining('nấu món gì?'));
      await _wait(tester, 500);
      await tester.enterText(find.widgetWithText(TextFormField, 'Tiêu đề'),
          'Bài chờ duyệt ở bảng tin');
      await tester.enterText(find.widgetWithText(TextFormField, 'Nội dung'),
          'Nội dung đủ dài để được gửi cho Ban quản trị.');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng'));
      await _wait(tester, 2000);
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(find.textContaining('sau khi Ban quản trị duyệt'), findsOneWidget);
      expect(find.text('Bài chờ duyệt ở bảng tin'), findsNothing);
      await _dispose(tester);
    });

    testWidgets(
        'post page: "Chờ duyệt", no comments; "Duyệt thử" publishes it and '
        'opens them', (tester) async {
      final post = await _seedOwn(tester, 'Bài thử duyệt trên trang bài',
          approved: false);
      await _pump(tester, PostDetailScreen(post: post));
      await _wait(tester);
      expect(find.text(_waiting), findsOneWidget);
      expect(find.byType(CommentComposer), findsNothing);

      await tester.tap(find.text('Duyệt thử'));
      await _wait(tester, 1500);
      expect(find.text(_waiting), findsNothing);
      expect(find.byType(CommentComposer), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('"Từ chối thử" shows the reason and "Sửa & gửi lại"',
        (tester) async {
      final post = await _seedOwn(tester, 'Bài thử từ chối trên trang bài',
          approved: false);
      await _pump(tester, PostDetailScreen(post: post));
      await _wait(tester);
      await tester.tap(find.text('Từ chối thử'));
      await _wait(tester, 1500);
      expect(
          find.text(
              'Bị từ chối: ${MockCommunityRepository.demoRejectionReason}'),
          findsOneWidget);
      expect(find.text('Sửa & gửi lại'), findsOneWidget);
      expect(find.text('Duyệt thử'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('the real BE gets no demo buttons', (tester) async {
      BackendModules.debugOverride({BackendModule.community});
      await _pump(
        tester,
        Scaffold(
          body: PostStatusBanner(
            post: Post(
              id: 'p1',
              type: PostType.recipe,
              author: const AuthorSummary(id: 'u_me', name: 'Minh Anh'),
              title: 'Bài của tôi',
              body: 'Nội dung',
              createdAt: DateTime(2026),
              coverSeed: 'p1',
              status: PostStatus.pending,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_waiting), findsOneWidget);
      expect(find.text('Duyệt thử'), findsNothing);
    });
  });

  group('"Sửa bài" (mock)', () {
    Future<void> openOwnMenu(WidgetTester tester, Finder scope) async {
      await tester.tap(
          find.descendant(of: scope, matching: find.byTooltip('Tuỳ chọn')));
      await tester.pumpAndSettle();
    }

    testWidgets('from the post page: saved, back to waiting', (tester) async {
      final post = await _seedOwn(tester, 'Bài sửa từ trang bài viết');
      await _pump(tester, PostDetailScreen(post: post));
      await _wait(tester);
      await openOwnMenu(tester, find.byType(PostAuthorRow));
      await tester.tap(find.text('Sửa bài'));
      await tester.pumpAndSettle();
      expect(find.text('Sửa bài viết'), findsOneWidget);
      await _editTitle(tester, 'Bài đã sửa từ trang bài viết');
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(find.text('Bài đã sửa từ trang bài viết'), findsOneWidget);
      expect(find.text(_waiting), findsOneWidget);
      expect(find.textContaining('Đã lưu. Bài sẽ hiển thị'), findsOneWidget);
      await _dispose(tester);
    });

    for (final (media, url, label) in [
      (PostMediaType.video, 'https://cdn.test/edit.mp4', 'Video đã đăng'),
      (PostMediaType.image, 'https://cdn.test/edit.jpg', 'Ảnh đã đăng'),
    ]) {
      testWidgets('a ${media.apiValue} post keeps its attachment',
          (tester) async {
        final post = await _seedOwn(
            tester, 'Bài có tệp ${media.apiValue} để sửa',
            media: media, mediaUrl: url);
        await _pump(tester, CreatePostScreen(editing: post));
        await tester.pump();
        expect(find.text(label), findsOneWidget);
        await _editTitle(tester, 'Đã sửa bài có tệp ${media.apiValue}');
        final after =
            (await tester.runAsync(() => _repo().getPost(post.id)))!.toEntity();
        expect(after.title, 'Đã sửa bài có tệp ${media.apiValue}');
        expect(after.mediaUrl, url);
        expect(after.mediaType, media);
        expect(after.isPending, isTrue);
        await _dispose(tester);
      });
    }

    testWidgets('from the feed: the post leaves it', (tester) async {
      final post = await _seedOwn(tester, 'Bài sửa từ bảng tin nè');
      await _pump(tester, const FeedScreen(), size: const Size(411, 1600));
      await _wait(tester);
      final card = find.ancestor(
          of: find.text(post.title), matching: find.byType(PostCard));
      await openOwnMenu(tester, card);
      await tester.tap(find.text('Sửa bài'));
      await tester.pumpAndSettle();
      await _editTitle(tester, 'Bài đã sửa từ bảng tin');
      expect(find.text('Bài đã sửa từ bảng tin'), findsNothing);
      expect(find.text(post.title), findsNothing);
      expect(find.textContaining('Đã lưu. Bài sẽ hiển thị'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('from "Nội dung của tôi": the list follows', (tester) async {
      final post = await _seedOwn(tester, 'Bài sửa từ nội dung của tôi');
      await _pump(tester, const MyPostsScreen(), size: const Size(411, 3000));
      await _wait(tester);
      final card = find.ancestor(
          of: find.text(post.title), matching: find.byType(PostCard));
      await openOwnMenu(tester, card);
      await tester.tap(find.text('Sửa bài'));
      await tester.pumpAndSettle();
      await _editTitle(tester, 'Bài đã sửa từ nội dung của tôi');
      await _wait(tester, 1500);
      expect(find.text('Bài đã sửa từ nội dung của tôi'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('hidden on the real BE, where PUT /posts/{id} is a 405',
        (tester) async {
      BackendModules.debugOverride({BackendModule.community});
      final post = Post(
        id: 'p1',
        type: PostType.recipe,
        author: const AuthorSummary(id: 'u_me', name: 'Minh Anh'),
        title: 'Bài của tôi trên BE thật',
        body: 'Nội dung',
        createdAt: DateTime(2026),
        coverSeed: 'p1',
      );
      await _pump(tester, Scaffold(body: PostAuthorRow(post: post)));
      await tester.pump();
      await openOwnMenu(tester, find.byType(PostAuthorRow));
      expect(find.text('Sửa bài'), findsNothing);
      expect(find.text('Xoá bài'), findsOneWidget);
    });
  });

  group('whatever status the real server answers', () {
    PostDto answer(String status) => PostDto(
          id: 'p_real',
          type: 'discussion',
          author: const AuthorSummary(id: 'u_me', name: 'Minh Anh'),
          title: 'Bài trả về trạng thái',
          body: 'Nội dung bài viết',
          createdAt: DateTime(2026, 10, 31),
          status: status,
        );

    for (final (status, message) in [
      ('Pending', 'Bài đã gửi và đang chờ duyệt.'),
      ('Rejected', 'Ban quản trị đã từ chối bài này'),
    ]) {
      testWidgets('$status: says so and stays off the feed', (tester) async {
        BackendModules.debugOverride({BackendModule.community});
        final api = _AnsweringCommunity(answer(status));
        Post? popped;
        var closed = false;
        await _pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  popped = await Navigator.of(context)
                      .push<Post>(CreatePostScreen.route());
                  closed = true;
                },
                child: const Text('Mở'),
              ),
            ),
          ),
          overrides: [communityApiProvider.overrideWithValue(api)],
        );
        await tester.tap(find.text('Mở'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, 'Tiêu đề'),
            'Bài trả về trạng thái');
        await tester.enterText(find.widgetWithText(TextFormField, 'Nội dung'),
            'Nội dung đủ dài để gửi cho máy chủ thật.');
        await tester.tap(find.widgetWithText(FilledButton, 'Đăng'));
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        expect(popped, isNull, reason: 'nothing for the feed');
        expect(find.textContaining(message), findsOneWidget);
        await _dispose(tester);
      });
    }

    testWidgets('Published: pops the post for the feed', (tester) async {
      BackendModules.debugOverride({BackendModule.community});
      Post? popped;
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => popped = await Navigator.of(context)
                  .push<Post>(CreatePostScreen.route()),
              child: const Text('Mở'),
            ),
          ),
        ),
        overrides: [
          communityApiProvider
              .overrideWithValue(_AnsweringCommunity(answer('Published'))),
        ],
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Tiêu đề'),
          'Bài trả về trạng thái');
      await tester.enterText(find.widgetWithText(TextFormField, 'Nội dung'),
          'Nội dung đủ dài để gửi cho máy chủ thật.');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng'));
      await tester.pumpAndSettle();
      expect(popped?.isPublished, isTrue);
      await _dispose(tester);
    });
  });
}

class _AnsweringCommunity implements CommunityApiService {
  _AnsweringCommunity(this.answer);

  final PostDto answer;

  @override
  Future<PostDto> createPost(CreatePostRequestDto request) async => answer;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
