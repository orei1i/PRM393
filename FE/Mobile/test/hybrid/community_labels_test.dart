// test/hybrid/community_labels_test.dart
// §9 of the plan, word for word: what the community screens hide and say when
// the real BE can't do something, and that a mock build keeps all of it.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/comment_thread_controller.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_thread.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';

const _me = '6ae5962396695f5c139fa9b0';
const _author = AuthorSummary(id: _me, name: 'FE Test');
const _realModules = {
  BackendModule.community,
  BackendModule.media,
};

final _createdAt = DateTime(2026, 10, 31, 9);

/// What the thread and the composer ask of the community API.
class _Community implements CommunityApiService {
  CreatePostRequestDto? created;

  @override
  Future<CommentPageDto> getComments(String postId,
          {String? cursor, int limit = 10}) async =>
      CommentPageDto(items: [
        CommentDto(
          id: 'c1',
          author: _author,
          text: 'Bình luận gốc',
          createdAt: _createdAt,
          replyCount: 3,
          replies: [
            CommentDto(
                id: 'r1',
                author: _author,
                text: 'Phản hồi một',
                parentId: 'c1',
                createdAt: _createdAt),
            CommentDto(
                id: 'r2',
                author: _author,
                text: 'Phản hồi hai',
                parentId: 'c1',
                createdAt: _createdAt),
          ],
        ),
      ]);

  @override
  Future<PostDto> createPost(CreatePostRequestDto request) async {
    created = request;
    return PostDto(
      id: 'p1',
      type: request.type.apiValue,
      author: _author,
      title: request.title,
      body: request.body,
      createdAt: _createdAt,
      mediaType: request.mediaType.apiValue,
      mediaUrl: request.mediaUrl,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Picker implements MediaPickerService {
  _Picker(this.media);

  final PickedMedia media;

  @override
  Future<PickedMedia?> pick(BuildContext context,
          {Set<MediaKind> kinds = const {
            MediaKind.image,
            MediaKind.video
          }}) async =>
      media;
}

/// Uploads like the BE in dev: a host-relative URL.
class _Uploads implements MediaApiService {
  @override
  Future<UploadedImageDto> uploadImage(PickedMedia image,
          {void Function(double progress)? onProgress,
          CancelToken? cancelToken}) async =>
      const UploadedImageDto(mediaUrl: '/uploads/images/a.png', sizeBytes: 1);

  @override
  Future<UploadedVideoDto> uploadVideo(PickedMedia video,
          {void Function(double progress)? onProgress,
          CancelToken? cancelToken}) async =>
      const UploadedVideoDto(
          mediaUrl: '/uploads/videos/a.mp4', durationSeconds: 15, sizeBytes: 1);
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(411, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SessionController.accessTokenKey: 'test-token',
    'vl.user_id': _me,
    'vl.display_name': 'FE Test',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: home)),
  ));
  await tester.pump();
}

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('comment thread', () {
    Future<void> open(WidgetTester tester) async {
      final controller = CommentThreadController(
        api: _Community(),
        postId: 'p1',
        initialCount: 4,
        me: () => _author,
      );
      addTearDown(controller.dispose);
      await controller.loadMore();
      await _pump(
        tester,
        SingleChildScrollView(
          child: CommentThreadList(
            controller: controller,
            currentUserId: _me,
            onReply: (_) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onMoreReplies: (_) {},
          ),
        ),
      );
    }

    testWidgets('real: replies past the preview are a statement', (t) async {
      BackendModules.debugOverride(_realModules);
      await open(t);
      expect(find.text('Còn 1 phản hồi khác, chưa xem được trên bản này'),
          findsOneWidget);
      expect(find.textContaining('Xem thêm'), findsNothing);
    });

    testWidgets('real: "Sửa" is gone, "Xoá" stays, nothing reads as edited',
        (t) async {
      BackendModules.debugOverride(_realModules);
      await open(t);
      expect(find.text('(đã sửa)'), findsNothing);
      await t.tap(find.byTooltip('Tuỳ chọn bình luận').first);
      await t.pumpAndSettle();
      expect(find.text('Sửa'), findsNothing);
      expect(find.text('Xoá'), findsOneWidget);
    });

    testWidgets('mock: "Xem thêm" and "Sửa" stay', (t) async {
      BackendModules.debugOverride(const {});
      await open(t);
      expect(find.text('Xem thêm 1 phản hồi'), findsOneWidget);
      await t.tap(find.byTooltip('Tuỳ chọn bình luận').first);
      await t.pumpAndSettle();
      expect(find.text('Sửa'), findsOneWidget);
    });
  });

  group('post menu', () {
    final post = Post(
      id: 'p1',
      type: PostType.recipe,
      author: _author,
      title: 'Bài của tôi',
      body: 'Nội dung',
      createdAt: _createdAt,
      coverSeed: 'p1',
    );

    testWidgets('real: only "Xoá bài"', (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, PostAuthorRow(post: post));
      await t.tap(find.byTooltip('Tuỳ chọn'));
      await t.pumpAndSettle();
      expect(find.text('Sửa bài'), findsNothing);
      expect(find.text('Xoá bài'), findsOneWidget);
    });

    testWidgets('mock: "Sửa bài" stays', (t) async {
      BackendModules.debugOverride(const {});
      await _pump(t, PostAuthorRow(post: post));
      await t.tap(find.byTooltip('Tuỳ chọn'));
      await t.pumpAndSettle();
      expect(find.text('Sửa bài'), findsOneWidget);
    });
  });

  group('Tạo bài viết', () {
    Future<_Community> open(WidgetTester tester, PickedMedia media) async {
      final community = _Community();
      await _pump(
        tester,
        const CreatePostScreen(),
        overrides: [
          communityApiProvider.overrideWithValue(community),
          mediaPickerProvider.overrideWithValue(_Picker(media)),
          mediaApiProvider.overrideWithValue(_Uploads()),
        ],
      );
      return community;
    }

    const small = PickedMedia.video(
        name: 'banh_xeo.mp4', sizeBytes: 1024, durationSeconds: 5);

    testWidgets('real: no "Gắn quán"', (t) async {
      BackendModules.debugOverride(_realModules);
      await open(t, small);
      expect(find.text('Gắn quán'), findsNothing);
      expect(find.text('Gắn thẻ'), findsOneWidget);
    });

    testWidgets('mock: "Gắn quán" stays', (t) async {
      BackendModules.debugOverride(const {});
      await open(t, small);
      expect(find.text('Gắn quán'), findsOneWidget);
    });

    testWidgets('real: a video over 100 MB is refused, with the limit',
        (t) async {
      BackendModules.debugOverride(_realModules);
      await open(
          t,
          const PickedMedia.video(
              name: 'dai.mp4',
              sizeBytes: 150 * 1024 * 1024,
              durationSeconds: 900));
      await t.tap(find.text('Ảnh/Video'));
      await t.pump();
      expect(find.text('Video vượt quá 100 MB'), findsOneWidget);
      expect(find.text('Video MP4, MOV, WEBM tối đa 100 MB'), findsOneWidget);
      expect(find.text('Đã tải lên'), findsNothing);
    });

    testWidgets(
        'real: no AI promise, a video needs a line of text, and the raw URL is posted',
        (t) async {
      BackendModules.debugOverride(_realModules);
      final community = await open(t, small);
      await t.tap(find.text('Ảnh/Video'));
      await t.pump();
      await t.pump();
      expect(find.text('Đã tải lên'), findsOneWidget);
      expect(find.textContaining('AI sẽ nghe lời thoại'), findsNothing);

      await t.enterText(
          find.widgetWithText(TextFormField, 'Tiêu đề'), 'Bánh xèo chay giòn');
      await t.pump();
      await t.tap(find.text('Đăng'));
      await t.pump();
      expect(
          find.text('Viết vài dòng giới thiệu cho video nhé.'), findsOneWidget);
      expect(community.created, isNull);

      await t.enterText(find.widgetWithText(TextFormField, 'Nội dung'), 'Hay');
      await t.pump();
      await t.tap(find.text('Đăng'));
      await t.pump();
      expect(community.created?.mediaUrl, '/uploads/videos/a.mp4');
      expect(community.created?.mediaType, PostMediaType.video);
      await t.pumpAndSettle();
    });

    testWidgets('mock: the AI promise stays and a video needs no text',
        (t) async {
      BackendModules.debugOverride(const {});
      final community = await open(t, small);
      await t.tap(find.text('Ảnh/Video'));
      await t.pump();
      await t.pump();
      expect(find.textContaining('AI sẽ nghe lời thoại'), findsOneWidget);

      await t.enterText(
          find.widgetWithText(TextFormField, 'Tiêu đề'), 'Bánh xèo chay giòn');
      await t.pump();
      await t.tap(find.text('Đăng'));
      await t.pump();
      expect(community.created, isNotNull);
      await t.pumpAndSettle();
    });
  });
}
