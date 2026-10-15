// test/m3_content_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/data/video_picker.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';

Matcher _apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status));

/// The mock community DB is static per test isolate: tests below create
/// their own posts or read values first.
void main() {
  group('PostDto status & media', () {
    Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
          'id': 7,
          'type': 'recipe',
          'author': {'id': 3, 'fullName': 'Minh Anh'},
          'title': 'Bún riêu chay',
          'body': '…',
          'createdAt': '2026-10-14T02:10:00Z',
          ...extra,
        };

    test('missing status reads as Published, values are case-insensitive', () {
      expect(PostDto.fromJson(json()).toEntity().status, PostStatus.published);
      expect(PostDto.fromJson(json({'status': 'pending'})).toEntity().status,
          PostStatus.pending);
      final rejected = PostDto.fromJson(json({
        'status': 'REJECTED',
        'rejectionReason': 'Thiếu nguồn.',
        'updatedAt': '2026-10-15T01:00:00Z',
      })).toEntity();
      expect(rejected.isRejected, isTrue);
      expect(rejected.rejectionReason, 'Thiếu nguồn.');
      expect(rejected.updatedAt, isNotNull);
      expect(PostStatus.fromApi('weird'), PostStatus.published);
    });

    test('mediaType is derived when missing and survives a round trip', () {
      expect(PostDto.fromJson(json()).toEntity().mediaType, PostMediaType.text);
      expect(
          PostDto.fromJson(json({'imageUrl': 'https://x/a.jpg'}))
              .toEntity()
              .mediaType,
          PostMediaType.image);
      final video = PostDto.fromJson(json({'type': 'video'}));
      expect(video.toEntity().mediaType, PostMediaType.video);
      expect(video.toEntity().id, '7', reason: 'INT ids become strings');
      final again = PostDto.fromJson(PostDto.fromJson(
              json({'mediaType': 'Image', 'mediaUrl': 'https://x/b.jpg'}))
          .toJson());
      expect(again.mediaType, 'Image');
      expect(again.mediaUrl, 'https://x/b.jpg');
    });

    test('comments carry postId and show as edited once updatedAt is set', () {
      final c = CommentDto.fromJson({
        'id': 1,
        'postId': 7,
        'author': {'id': 3, 'fullName': 'Minh Anh'},
        'text': 'Ngon',
        'createdAt': '2026-10-14T02:10:00Z',
        'updatedAt': '2026-10-14T03:00:00Z',
      }).toEntity();
      expect(c.postId, '7');
      expect(c.isEdited, isTrue);
    });

    test('a video post sends mediaType/mediaUrl and the legacy videoUrl', () {
      const request = CreatePostRequestDto(
        type: PostType.video,
        title: 'Bánh xèo chay',
        body: '',
        mediaUrl: 'https://res.cloudinary.com/v.mp4',
      );
      expect(request.toJson(), containsPair('mediaType', 'Video'));
      expect(request.toJson()['videoUrl'], request.toJson()['mediaUrl']);
      const text = CreatePostRequestDto(
          type: PostType.recipe, title: 'Gỏi cuốn', body: 'Cuốn.');
      expect(text.toJson(), containsPair('mediaType', 'Text'));
      expect(text.toJson().containsKey('videoUrl'), isFalse);
    });
  });

  test('the AI pre-screen flags trigger words, accents or not', () {
    expect(
        MockCommunityRepository.preScreenFlags('Bài thử', 'có #flag'), isTrue);
    expect(MockCommunityRepository.preScreenFlags('Nước ép chua khoi bệnh', ''),
        isTrue);
    expect(MockCommunityRepository.preScreenFlags('Liên hệ', 'Inbox Zalo'),
        isTrue);
    expect(
        MockCommunityRepository.preScreenFlags(
            'Đậu hũ sốt cà', 'Rán vàng đậu, om sốt cà chua.'),
        isFalse);
  });

  group('MockCommunityRepository: own content', () {
    var signedIn = true;
    var userId = 'u_me';
    // Same two-argument shape older tests use, plus the session's user id.
    final repo = MockCommunityRepository(
      currentUserName: () => userId == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
      isSignedIn: () => signedIn,
      currentUserId: () => userId,
    );
    setUp(() {
      signedIn = true;
      userId = 'u_me';
    });

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

    test('comments: Minh Anh starts with none, Tâm has his 2 seeds', () async {
      expect(await repo.getMyComments(), isEmpty);
      userId = 'u_chef_tam';
      final tam = await repo.getMyComments();
      expect(tam, hasLength(2));
      expect(tam.every((c) => c.postTitle.isNotEmpty), isTrue);
      signedIn = false;
      expect(await repo.getMyComments(), isEmpty);
    });

    test('a flagged post is held: not in the feed, listed as mine', () async {
      final created = await repo.createPost(const CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Bài kiểm tra pre-screen',
          body: 'Nội dung có #flag để AI giữ lại.'));
      expect(created.status, 'Pending');
      final feed = await wholeFeed();
      expect(feed.map((p) => p.id), isNot(contains(created.id)));
      expect(feed.every((p) => p.status == 'Published'), isTrue);
      final mine = await repo.getMyPosts();
      expect(mine.map((p) => p.id), contains(created.id));
      expect(mine.map((p) => p.id),
          containsAll(['p_me_pending_celery', 'p_me_rejected_detox']));

      // Others (and guests) get a 404 for it.
      userId = 'u_chef_tam';
      await expectLater(repo.getPost(created.id), _apiError(404));
      signedIn = false;
      await expectLater(repo.getPost(created.id), _apiError(404));
    });

    test('edit transitions follow "publish unless AI flags"', () async {
      UpdatePostRequestDto edit(String title, String body) =>
          UpdatePostRequestDto(
              title: title, body: body, mediaType: PostMediaType.text);

      final post = await repo.createPost(const CreatePostRequestDto(
          type: PostType.recipe,
          title: 'Canh bí đỏ đậu phộng',
          body: 'Bí đỏ nấu với đậu phộng, nêm nhạt.'));
      expect(post.status, 'Published');

      // Published + clean → stays published, still in the feed.
      final clean =
          await repo.updatePost(post.id, edit('Canh bí đỏ hầm', post.body));
      expect(clean.status, 'Published');
      expect(clean.updatedAt, isNotNull);
      expect((await wholeFeed()).singleWhere((p) => p.id == post.id).title,
          'Canh bí đỏ hầm');

      // Published + flagged → Pending, leaves the feed.
      final flagged = await repo.updatePost(
          post.id, edit('Canh bí đỏ hầm', 'Mua nguyên liệu inbox zalo nhé'));
      expect(flagged.status, 'Pending');
      expect((await wholeFeed()).map((p) => p.id), isNot(contains(post.id)));

      // Pending stays Pending even when clean again.
      final still =
          await repo.updatePost(post.id, edit('Canh bí đỏ hầm', 'Nấu nhạt.'));
      expect(still.status, 'Pending');

      // Rejected → always back to Pending, the old reason is cleared.
      final resubmitted = await repo.updatePost('p_me_rejected_detox',
          edit('Trà thảo mộc mình hay uống', 'Ghi chú cá nhân, có nguồn.'));
      expect(resubmitted.status, 'Pending');
      expect(resubmitted.rejectionReason, isNull);

      // #fail → 503.
      await expectLater(
          repo.updatePost(post.id, edit('Canh bí đỏ hầm', '#fail')),
          _apiError(503));
    });

    test('only the author edits or deletes; delete removes everywhere',
        () async {
      final post = await repo.createPost(const CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Câu hỏi sẽ bị xoá',
          body: 'Mọi người cho mình hỏi về sữa hạt nhé.'));

      userId = 'u_chef_tam';
      await expectLater(
          repo.updatePost(
              post.id,
              const UpdatePostRequestDto(
                  title: 'Sửa trộm', body: '', mediaType: PostMediaType.text)),
          _apiError(403));
      await expectLater(repo.deletePost(post.id), _apiError(403));

      userId = 'u_me';
      await repo.deletePost(post.id);
      expect(
          (await repo.getMyPosts()).map((p) => p.id), isNot(contains(post.id)));
      expect((await wholeFeed()).map((p) => p.id), isNot(contains(post.id)));
      await expectLater(repo.getPost(post.id), _apiError(404));
    });

    test('own comments: edit marks them edited, delete moves the count',
        () async {
      final before = await repo.getPost('p_com_chien_hat_sen');
      final added =
          await repo.addComment('p_com_chien_hat_sen', 'Cho thêm nấm nhé!');
      final edited = await repo.updateComment(
          'p_com_chien_hat_sen', added.id, 'Cho thêm nấm đông cô nhé!');
      expect(edited.updatedAt, isNotNull);
      expect(edited.toEntity().isEdited, isTrue);

      final mine = await repo.getMyComments();
      final listed = mine.firstWhere((c) => c.id == added.id);
      expect(listed.postTitle, before.title);
      expect(listed.updatedAt, isNotNull);

      userId = 'u_chef_tam';
      await expectLater(
          repo.updateComment('p_com_chien_hat_sen', added.id, 'x'),
          _apiError(403));
      userId = 'u_me';
      await expectLater(
          repo.updateComment('p_com_chien_hat_sen', added.id, '#fail'),
          _apiError(503));

      await repo.deleteComment('p_com_chien_hat_sen', added.id);
      final after = await repo.getPost('p_com_chien_hat_sen');
      expect(after.commentCount, before.commentCount);
      expect(await repo.getComments('p_com_chien_hat_sen'),
          hasLength(after.commentCount));
    });

    test('saves belong to the account, not the device', () async {
      await repo.setSaved('p_sua_chua_dua', saved: true);
      userId = 'u_chef_tam';
      expect((await repo.getPost('p_sua_chua_dua')).savedByMe, isFalse);
      expect((await repo.getSavedPosts()).map((p) => p.id),
          isNot(contains('p_sua_chua_dua')));
      userId = 'u_me';
      expect((await repo.getPost('p_sua_chua_dua')).savedByMe, isTrue);
      await repo.setSaved('p_sua_chua_dua', saved: false);
    });

    test('an uploaded video keeps its duration and starts the AI pipeline',
        () async {
      final upload = await MockMediaRepository(tick: Duration.zero)
          .uploadVideo(MockVideoPickerService.samples.first);
      final post = await repo.createPost(CreatePostRequestDto(
        type: PostType.video,
        title: 'Bánh xèo chay nhân nấm',
        body: '',
        mediaType: PostMediaType.video,
        mediaUrl: upload.mediaUrl,
      ));
      expect(post.videoId, isNotNull);
      expect(post.videoDurationSeconds, 486);
      expect(post.videoAiStatus, 'queued');
      expect(post.mediaUrl, upload.mediaUrl);
    });
  });

  group('video upload', () {
    final media = MockMediaRepository(tick: const Duration(milliseconds: 1));
    final banhXeo = MockVideoPickerService.samples[0];
    final matKetNoi = MockVideoPickerService.samples[1];
    final quaLon = MockVideoPickerService.samples[2];

    test('client rules: 200 MB and mp4/mov/webm', () {
      expect(VideoUploadRules.validate(banhXeo), isNull);
      expect(VideoUploadRules.validate(quaLon), 'Video vượt quá 200 MB');
      expect(
          VideoUploadRules.validate(const PickedVideo(
              name: 'clip.avi', sizeBytes: 1000, durationSeconds: 10)),
          'Định dạng chưa hỗ trợ');
      expect(banhXeo.summary, '48 MB · 8:06');
    });

    test('progress rises monotonically to 1.0 and returns a mediaUrl',
        () async {
      final progress = <double>[];
      final result = await media.uploadVideo(banhXeo, onProgress: progress.add);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThan(progress[i - 1]));
      }
      expect(result.mediaUrl, startsWith('https://'));
      expect(result.durationSeconds, 486);
    });

    test('mat_ket_noi.mp4 fails at 60 %', () async {
      final progress = <double>[];
      await expectLater(
        media.uploadVideo(matKetNoi, onProgress: progress.add),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
      );
      expect(progress.last, 0.6);
    });

    test('cancel stops it with code "cancelled"; too big is refused', () async {
      final token = CancelToken();
      final upload =
          media.uploadVideo(banhXeo, cancelToken: token, onProgress: (p) {
        if (p >= 0.3) token.cancel();
      });
      await expectLater(
        upload,
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'cancelled')),
      );
      await expectLater(media.uploadVideo(quaLon), _apiError(413));
    });
  });
}
