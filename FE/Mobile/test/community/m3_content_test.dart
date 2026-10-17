// test/community/m3_content_test.dart
// Community data layer: PostDto (types, attachment, restaurant tag),
// requests, the AI pre-screen, own content, comment paging and replies, and
// photo / video uploads.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/controllers/comment_thread_controller.dart';

Matcher _apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status));

/// The mock community DB is static per test isolate: tests below create
/// their own posts or read values first.
void main() {
  group('PostDto status, type & media', () {
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

    test('only Công thức and Hỏi đáp; legacy "video" is a recipe with a video',
        () {
      expect(PostType.values.map((t) => t.label), ['Công thức', 'Hỏi đáp']);
      final legacy = PostDto.fromJson(json({
        'type': 'video',
        'video': {'id': 'vid_1', 'durationSeconds': 60, 'aiStatus': 'ready'},
      }));
      expect(legacy.type, 'recipe');
      final post = legacy.toEntity();
      expect(post.type, PostType.recipe);
      expect(post.mediaType, PostMediaType.video);
      expect(post.hasVideo, isTrue);
      expect(post.hasAiRecipe, isTrue);
      expect(PostDto.fromJson(json({'type': 'video'})).toEntity().hasVideo,
          isTrue);
      expect(PostDto.fromJson(json({'type': 'question'})).type, 'discussion');
    });

    test('mediaType is derived when missing and survives a round trip', () {
      expect(PostDto.fromJson(json()).toEntity().mediaType, PostMediaType.text);
      final photo = PostDto.fromJson(json({'imageUrl': 'https://x/a.jpg'}));
      expect(photo.toEntity().mediaType, PostMediaType.image);
      expect(photo.toEntity().id, '7', reason: 'INT ids become strings');
      final again = PostDto.fromJson(PostDto.fromJson(
              json({'mediaType': 'Image', 'mediaUrl': 'https://x/b.jpg'}))
          .toJson());
      expect(again.mediaType, 'Image');
      expect(again.mediaUrl, 'https://x/b.jpg');
      expect(again.toEntity().imageSrc, 'https://x/b.jpg');
      // A Hỏi đáp with a video has no AI recipe, but plays its file.
      final qa = PostDto.fromJson(json({
        'type': 'discussion',
        'mediaType': 'Video',
        'mediaUrl': 'https://x/c.mp4'
      })).toEntity();
      expect(qa.hasVideo, isTrue);
      expect(qa.hasAiRecipe, isFalse);
      expect(qa.hasCover, isTrue);
      expect(PostDto.fromJson(json({'type': 'discussion'})).toEntity().hasCover,
          isFalse);
    });

    test('the tagged restaurant is parsed and kept', () {
      final post = PostDto.fromJson(json({
        'restaurant': {
          'id': 21,
          'name': 'Quán Chay An Lạc',
          'district': 'Q.1',
          'isCertified': true
        },
      }));
      final r = post.toEntity().restaurant!;
      expect(r.id, '21');
      expect(r.name, 'Quán Chay An Lạc');
      expect(r.district, 'Q.1');
      expect(r.isCertified, isTrue);
      expect(
          PostDto.fromJson(post.toJson()).restaurant?.name, 'Quán Chay An Lạc');
      expect(PostDto.fromJson(json({'restaurant': null})).restaurant, isNull);
      expect(
          TaggedRestaurant.districtOf(
              '152 Đinh Tiên Hoàng, P.1, Q. Bình Thạnh, TP.HCM'),
          'Q. Bình Thạnh');
      expect(
          TaggedRestaurant.districtOf(
              '12 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP.HCM'),
          'Q.1');
    });

    test('comments carry postId, parentId, content and their reply preview',
        () {
      final c = CommentDto.fromJson({
        'id': 1,
        'postId': 7,
        'parentId': null,
        'author': {'id': 3, 'fullName': 'Minh Anh'},
        'content': 'Ngon',
        'createdAt': '2026-10-14T02:10:00Z',
        'updatedAt': '2026-10-14T03:00:00Z',
        'replyCount': 3,
        'replies': [
          {
            'id': 2,
            'postId': 7,
            'parentId': 1,
            'author': {'id': 4, 'fullName': 'Lan'},
            'content': 'Đồng ý',
            'createdAt': '2026-10-14T02:20:00Z',
          },
        ],
      }).toEntity();
      expect(c.postId, '7');
      expect(c.isEdited, isTrue);
      expect(c.text, 'Ngon');
      expect(c.replyCount, 3);
      expect(c.replies.single.parentId, '1');
      expect(c.replies.single.isReply, isTrue);
      // Older builds sent `text` and a bare list.
      final page = CommentPageDto.fromJson([
        {
          'id': 5,
          'author': {'id': 3, 'fullName': 'A'},
          'text': 'Cũ',
          'createdAt': '2026-10-14T02:10:00Z'
        },
      ]);
      expect(page.items.single.text, 'Cũ');
      expect(page.nextCursor, isNull);
    });

    test('create sends one attachment and the restaurant id; no videoUrl', () {
      const request = CreatePostRequestDto(
        type: PostType.recipe,
        title: 'Bánh xèo chay',
        body: '',
        mediaType: PostMediaType.video,
        mediaUrl: 'https://res.cloudinary.com/v.mp4',
        restaurant: TaggedRestaurant(id: 'rs_an_lac', name: 'Quán Chay An Lạc'),
      );
      final body = request.toJson();
      expect(body, containsPair('mediaType', 'Video'));
      expect(body, containsPair('restaurantId', 'rs_an_lac'));
      expect(body.containsKey('videoUrl'), isFalse);
      expect(request.wantsAiRecipe, isTrue);
      const qa = CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Hỏi',
          body: 'Video này dùng nồi gì?',
          mediaType: PostMediaType.video,
          mediaUrl: 'https://res.cloudinary.com/q.mp4');
      expect(qa.wantsAiRecipe, isFalse, reason: 'AI only for Công thức');
      const text = CreatePostRequestDto(
          type: PostType.recipe, title: 'Gỏi cuốn', body: 'Cuốn.');
      expect(text.toJson(), containsPair('mediaType', 'Text'));
      expect(text.toJson()['restaurantId'], isNull);
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
    final repo = MockCommunityRepository(
      currentUserName: () => userId == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
      isSignedIn: () => signedIn,
      currentUserId: () => userId,
    );
    setUp(() {
      signedIn = true;
      userId = 'u_me';
    });

    Future<List<PostDto>> wholeFeed(
        {PostType? type, PostMediaType? media}) async {
      final posts = <PostDto>[];
      String? cursor;
      do {
        final page =
            await repo.getFeed(type: type, mediaType: media, cursor: cursor);
        posts.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      return posts;
    }

    test('feed filters: Công thức, Hỏi đáp, Có video', () async {
      final recipes = await wholeFeed(type: PostType.recipe);
      final qa = await wholeFeed(type: PostType.discussion);
      final videos = await wholeFeed(media: PostMediaType.video);
      expect(recipes, isNotEmpty);
      expect(recipes.every((p) => p.type == 'recipe'), isTrue);
      expect(qa.every((p) => p.type == 'discussion'), isTrue);
      expect(videos.every((p) => p.hasVideo), isTrue);
      expect(videos.map((p) => p.id),
          containsAll(['p_video_cha_lua', 'p_video_meal_prep']));
      final tagged = (await wholeFeed())
          .where((p) => p.restaurant != null)
          .map((p) => p.id);
      expect(tagged, containsAll(['p_video_cha_lua', 'p_checkin_hanh_tam']));
    });

    test('comments: Minh Anh starts with none, Tâm has his seeds and a reply',
        () async {
      expect(await repo.getMyComments(), isEmpty);
      userId = 'u_chef_tam';
      final tam = await repo.getMyComments();
      expect(tam, hasLength(3));
      expect(tam.every((c) => c.postTitle.isNotEmpty), isTrue);
      expect(tam.where((c) => c.parentId != null), hasLength(1));
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

    test('a tagged photo post keeps its restaurant; edit can change the tag',
        () async {
      final post = await repo.createPost(const CreatePostRequestDto(
        type: PostType.discussion,
        title: 'Ghé quán An Lạc trưa nay',
        body: 'Cơm chay ở đây đậm đà, giá mềm, phục vụ nhanh.',
        mediaType: PostMediaType.image,
        mediaUrl: 'https://res.cloudinary.com/veganlife/image/upload/a.jpg',
        restaurant: TaggedRestaurant(
            id: 'rs_an_lac',
            name: 'Quán Chay An Lạc',
            district: 'Q.1',
            isCertified: true),
      ));
      expect(post.mediaType, 'Image');
      expect(post.videoId, isNull);
      expect(post.restaurant?.id, 'rs_an_lac');
      expect(
          (await repo.getPost(post.id)).restaurant?.name, 'Quán Chay An Lạc');

      final untagged = await repo.updatePost(
          post.id,
          UpdatePostRequestDto(
              title: post.title,
              body: post.body,
              mediaType: PostMediaType.image,
              mediaUrl: post.mediaUrl));
      expect(untagged.restaurant, isNull);
      expect(untagged.mediaUrl, post.mediaUrl, reason: 'attachment kept');
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

      final clean =
          await repo.updatePost(post.id, edit('Canh bí đỏ hầm', post.body));
      expect(clean.status, 'Published');
      expect(clean.updatedAt, isNotNull);
      expect((await wholeFeed()).singleWhere((p) => p.id == post.id).title,
          'Canh bí đỏ hầm');

      final flagged = await repo.updatePost(
          post.id, edit('Canh bí đỏ hầm', 'Mua nguyên liệu inbox zalo nhé'));
      expect(flagged.status, 'Pending');
      expect((await wholeFeed()).map((p) => p.id), isNot(contains(post.id)));

      final still =
          await repo.updatePost(post.id, edit('Canh bí đỏ hầm', 'Nấu nhạt.'));
      expect(still.status, 'Pending');

      final resubmitted = await repo.updatePost('p_me_rejected_detox',
          edit('Trà thảo mộc mình hay uống', 'Ghi chú cá nhân, có nguồn.'));
      expect(resubmitted.status, 'Pending');
      expect(resubmitted.rejectionReason, isNull);

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

    test(
        'a Công thức video starts the AI pipeline; a Hỏi đáp video and a '
        'photo do not', () async {
      final upload = await MockMediaRepository(tick: Duration.zero)
          .uploadVideo(MockMediaPickerService.videoSamples.first);
      final recipe = await repo.createPost(CreatePostRequestDto(
        type: PostType.recipe,
        title: 'Bánh xèo chay nhân nấm',
        body: '',
        mediaType: PostMediaType.video,
        mediaUrl: upload.mediaUrl,
      ));
      expect(recipe.videoId, isNotNull);
      expect(recipe.videoDurationSeconds, 486);
      expect(recipe.videoAiStatus, 'queued');
      expect(recipe.mediaUrl, upload.mediaUrl);

      final qa = await repo.createPost(CreatePostRequestDto(
        type: PostType.discussion,
        title: 'Video này dùng chảo gì vậy?',
        body: 'Mình thấy chảo không dính mà đẹp quá.',
        mediaType: PostMediaType.video,
        mediaUrl: upload.mediaUrl,
      ));
      expect(qa.videoId, isNull);
      expect(qa.mediaType, 'Video');
    });
  });

  group('MockCommunityRepository: comments', () {
    var userId = 'u_me';
    final repo = MockCommunityRepository(
      currentUserName: () => userId == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
      isSignedIn: () => true,
      currentUserId: () => userId,
    );
    setUp(() => userId = 'u_me');

    test('pages of 10 top-level comments, newest first, 2-reply previews',
        () async {
      final first = await repo.getComments('p_b12');
      expect(first.items, hasLength(10));
      expect(first.nextCursor, isNotNull);
      for (var i = 1; i < first.items.length; i++) {
        expect(first.items[i - 1].createdAt.isAfter(first.items[i].createdAt),
            isTrue);
      }
      expect(first.items.every((c) => c.parentId == null), isTrue);

      final all = [...first.items];
      String? cursor = first.nextCursor;
      while (cursor != null) {
        final page = await repo.getComments('p_b12', cursor: cursor);
        all.addAll(page.items);
        cursor = page.nextCursor;
      }
      final thuHa = all.singleWhere((c) => c.id == 'c_p_b12_0');
      expect(thuHa.replyCount, 3);
      expect(thuHa.replies, hasLength(2));
      expect(
          thuHa.replies.first.createdAt.isBefore(thuHa.replies.last.createdAt),
          isTrue,
          reason: 'replies oldest first');
      final total = all.fold<int>(0, (sum, c) => sum + 1 + c.replyCount);
      expect(total, (await repo.getPost('p_b12')).commentCount);

      final replies = await repo.getReplies('p_b12', 'c_p_b12_0');
      expect(replies.items.map((r) => r.id),
          ['c_p_b12_1', 'c_p_b12_2', 'c_p_b12_3']);
      await expectLater(repo.getReplies('p_b12', 'c_khong_co'), _apiError(404));
    });

    test('a reply to a reply joins the top-level comment; count includes it',
        () async {
      final before = (await repo.getPost('p_dau_hu_sot_ca')).commentCount;
      final top = await repo.addComment('p_dau_hu_sot_ca', 'Ngon quá!');
      final reply = await repo.addComment('p_dau_hu_sot_ca', 'Cảm ơn bạn',
          parentId: top.id);
      final nested = await repo.addComment(
          'p_dau_hu_sot_ca', '@Minh Anh thêm ớt nữa',
          parentId: reply.id);
      expect(reply.parentId, top.id);
      expect(nested.parentId, top.id, reason: 'one level deep');
      expect((await repo.getPost('p_dau_hu_sot_ca')).commentCount, before + 3);

      final page = await repo.getComments('p_dau_hu_sot_ca');
      expect(page.items.first.id, top.id, reason: 'newest on top');
      expect(page.items.first.replyCount, 2);

      // Deleting the top-level comment takes its replies.
      await repo.deleteComment('p_dau_hu_sot_ca', top.id);
      expect((await repo.getPost('p_dau_hu_sot_ca')).commentCount, before);
      await expectLater(
          repo.addComment('p_dau_hu_sot_ca', 'x', parentId: top.id),
          _apiError(404));
      await expectLater(
          repo.addComment('p_dau_hu_sot_ca', '  '), _apiError(400));
      await expectLater(
          repo.addComment('p_dau_hu_sot_ca', 'lỗi #fail'), _apiError(503));
    });

    test('own comments only: edit marks them edited, others get 403', () async {
      final added =
          await repo.addComment('p_com_chien_hat_sen', 'Cho thêm nấm nhé!');
      final edited = await repo.updateComment(
          'p_com_chien_hat_sen', added.id, 'Cho thêm nấm đông cô nhé!');
      expect(edited.toEntity().isEdited, isTrue);
      final listed =
          (await repo.getMyComments()).firstWhere((c) => c.id == added.id);
      expect(listed.updatedAt, isNotNull);

      userId = 'u_chef_tam';
      await expectLater(
          repo.updateComment('p_com_chien_hat_sen', added.id, 'x'),
          _apiError(403));
      await expectLater(
          repo.deleteComment('p_com_chien_hat_sen', added.id), _apiError(403));
      userId = 'u_me';
      await expectLater(
          repo.updateComment('p_com_chien_hat_sen', added.id, '#fail'),
          _apiError(503));
      await repo.deleteComment('p_com_chien_hat_sen', added.id);
    });
  });

  group('CommentThreadController', () {
    final repo = MockCommunityRepository(
        currentUserName: () => 'Minh Anh',
        isSignedIn: () => true,
        currentUserId: () => 'u_me');

    CommentThreadController thread(
            String postId, int count, List<int> deltas) =>
        CommentThreadController(
          api: repo,
          postId: postId,
          initialCount: count,
          me: () => const AuthorSummary(id: 'u_me', name: 'Minh Anh'),
          onCountChanged: deltas.add,
        );

    test('pages on demand, inserts at the top, replies, deletes with replies',
        () async {
      final count = (await repo.getPost('p_quan_chay_q9')).commentCount;
      final deltas = <int>[];
      final c = thread('p_quan_chay_q9', count, deltas);
      expect(c.hasMore, isTrue);
      await Future.wait([c.loadMore(), c.loadMore()]);
      expect(c.threads, hasLength(10), reason: 'one page, not two');
      await c.loadMore();
      expect(c.threads.length, greaterThan(10));

      final top = await c.add('Q.9 có quán Thiện Duyên ngon lắm.');
      expect(c.threads.first.comment.id, top.id);
      final reply = await c.add('Cảm ơn bạn!', replyTo: top);
      final nested = await c.add('@Minh Anh không có gì', replyTo: reply);
      expect(nested.parentId, top.id);
      expect(
          c.threadOf(top.id)!.replies.map((r) => r.id), [reply.id, nested.id]);
      expect(c.total, count + 3);

      expect(c.repliesGoingWith(c.threadOf(top.id)!.comment), 2);
      await c.delete(c.threadOf(top.id)!.comment);
      expect(c.find(top.id), isNull);
      expect(c.find(nested.id), isNull);
      expect(c.total, count);
      expect(deltas, [1, 1, 1, -3]);
      c.dispose();
    });

    test('a failed send is removed again and rethrown', () async {
      final c = thread('p_quan_chay_q9', 0, []);
      await c.loadMore();
      final before = c.threads.length;
      await expectLater(c.add('gửi lỗi #fail'), _apiError(503));
      expect(c.threads, hasLength(before));
      expect(c.total, 0);
      c.dispose();
    });

    test('reveal loads pages and replies until the comment is there', () async {
      final c = thread('p_b12', 31, []);
      final found = await c.reveal('c_p_b12_3', parentId: 'c_p_b12_0');
      expect(found, isTrue);
      expect(c.find('c_p_b12_3'), isNotNull);
      expect(await c.reveal('c_khong_co'), isFalse);
      c.dispose();
    });
  });

  group('media upload', () {
    final media = MockMediaRepository(tick: const Duration(milliseconds: 1));
    final banhXeo = MockMediaPickerService.videoSamples[0];
    final matKetNoi = MockMediaPickerService.videoSamples[1];
    final quaLon = MockMediaPickerService.videoSamples[2];
    final dauHu = MockMediaPickerService.imageSamples[0];
    final anhQuaLon = MockMediaPickerService.imageSamples[1];

    test('client rules: photos 10 MB jpg/png/webp/heic, videos 200 MB', () {
      expect(MediaUploadRules.validate(banhXeo), isNull);
      expect(MediaUploadRules.validate(dauHu), isNull);
      expect(MediaUploadRules.validate(quaLon), 'Video vượt quá 200 MB');
      expect(MediaUploadRules.validate(anhQuaLon), 'Ảnh vượt quá 10 MB');
      expect(
          MediaUploadRules.validate(const PickedMedia.video(
              name: 'clip.avi', sizeBytes: 1000, durationSeconds: 10)),
          'Định dạng video chưa hỗ trợ');
      expect(
          MediaUploadRules.validate(
              const PickedMedia.image(name: 'anh.gif', sizeBytes: 1000)),
          'Định dạng ảnh chưa hỗ trợ');
      expect(banhXeo.summary, '48 MB · 8:06');
      expect(dauHu.summary, '2,1 MB');
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

      final image = await media.uploadImage(dauHu);
      expect(image.mediaUrl, contains('/image/upload/'));
      expect(image.sizeBytes, dauHu.sizeBytes);
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
      await expectLater(media.uploadImage(anhQuaLon), _apiError(413));
      await expectLater(
          media.uploadImage(
              const PickedMedia.image(name: 'a.gif', sizeBytes: 10)),
          _apiError(415));
    });
  });
}
