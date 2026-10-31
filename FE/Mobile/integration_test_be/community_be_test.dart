// integration_test_be/community_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('community', skip: be.skipReason, () {
    late BeUser a;
    late BeUser b;
    late CommunityApiService asA;
    late CommunityApiService asB;
    final created = <String>[];

    Future<PostDto> post(
      CommunityApiService as, {
      String title = 'Bài thử tích hợp',
      String body = 'Nội dung dùng để thử tích hợp bảng tin.',
      PostType type = PostType.discussion,
    }) async {
      final dto = await as.createPost(
          CreatePostRequestDto(type: type, title: title, body: body));
      created.add(dto.id);
      return dto;
    }

    setUpAll(() async {
      a = await be.newUser(name: 'FE IT Community');
      b = await be.newUser(name: 'FE IT Community 2');
      asA = RemoteCommunityApiService(a.dio, currentUserId: () => a.id);
      asB = RemoteCommunityApiService(b.dio, currentUserId: () => b.id);
    });

    tearDownAll(() async {
      for (final id in created) {
        // Some were already deleted, or belong to the other account.
        await a.raw('DELETE', '/posts/$id');
        await b.raw('DELETE', '/posts/$id');
      }
    });

    beTest('create and read back', () async {
      final dto = await post(asA,
          title: 'Đậu hũ sốt cà tại nhà',
          body: 'Nguyên liệu đơn giản, nấu trong 15 phút là xong.',
          type: PostType.recipe);
      expect(dto.status, 'Published');
      expect(dto.type, PostType.recipe.apiValue);
      expect(dto.mediaType, PostMediaType.text.apiValue);
      expect(dto.author.id, a.id);

      final read = await asB.getPost(dto.id);
      expect(read.title, 'Đậu hũ sốt cà tại nhà');
      expect(read.likedByMe, isFalse);
    });

    beTest('feed pages never repeat, and the last one has no cursor', () async {
      for (var i = 0; i < 12; i++) {
        await post(asA, title: 'Bài thử phân trang số ${i + 1}');
      }
      final seen = <String>{};
      String? cursor;
      var pages = 0;
      do {
        final page = await asA.getFeed(cursor: cursor, limit: 10);
        for (final item in page.items) {
          expect(seen.add(item.id), isTrue, reason: 'repeated: ${item.id}');
        }
        cursor = page.nextCursor;
        pages++;
        expect(pages, lessThan(200), reason: 'the cursor never ends');
      } while (cursor != null);
      expect(pages, greaterThan(1));
      expect(seen, containsAll(created));
    });

    beTest('the feed filters by type and by media', () async {
      final questions = await asA.getFeed(type: PostType.discussion, limit: 10);
      expect(questions.items, isNotEmpty);
      expect(questions.items.map((p) => p.type).toSet(),
          {PostType.discussion.apiValue});
      final videos = await asA.getFeed(mediaType: PostMediaType.video);
      expect(
        videos.items.where((p) => p.mediaType != PostMediaType.video.apiValue),
        isEmpty,
      );
    });

    beTest('a guest reads the feed but cannot act on it', () async {
      final guest = RemoteCommunityApiService(be.guestDio());
      final feed = await guest.getFeed(limit: 3);
      expect(feed.items, isNotEmpty);
      final id = feed.items.first.id;
      expect((await guest.getPost(id)).id, id);
      await expectApiError(guest.setLiked(id, liked: true), status: 401);
      await expectApiError(guest.addComment(id, 'Khách'), status: 401);
    });

    beTest('"Bài của tôi" scans the feed for the member', () async {
      final mine = await asA.getMyPosts();
      expect(mine, isNotEmpty);
      expect(mine.map((p) => p.author.id).toSet(), {a.id});
      expect(await asB.getMyPosts(), isEmpty);
    });

    beTest('like then unlike survive a re-read', () async {
      final id = (await post(asA)).id;
      await asB.setLiked(id, liked: true);
      var read = await asB.getPost(id);
      expect(read.likedByMe, isTrue);
      expect(read.likeCount, 1);

      await asB.setLiked(id, liked: false);
      read = await asB.getPost(id);
      expect(read.likedByMe, isFalse);
      expect(read.likeCount, 0);
    });

    beTest('comments: page 2 is reached and does not repeat page 1', () async {
      final id = (await post(asB)).id;
      for (var i = 0; i < 11; i++) {
        await (i.isEven ? asA : asB).addComment(id, 'Bình luận số ${i + 1}');
      }
      final page1 = await asA.getComments(id);
      expect(page1.items, hasLength(10));
      expect(page1.nextCursor, isNotNull);
      expect(page1.items.first.text, 'Bình luận số 11', reason: 'newest first');

      final page2 = await asA.getComments(id, cursor: page1.nextCursor);
      expect(page2.items, hasLength(1));
      expect(page2.nextCursor, isNull);
      expect(page2.items.first.text, 'Bình luận số 1');
      expect((await asA.getPost(id)).commentCount, 11);
    });

    beTest('replies: 2 previewed, the count says 3, no "(đã sửa)" (B16, B17)',
        () async {
      final id = (await post(asB)).id;
      final root = await asA.addComment(id, 'Bình luận gốc');
      for (var i = 0; i < 3; i++) {
        final reply =
            await asB.addComment(id, 'Phản hồi ${i + 1}', parentId: root.id);
        expect(reply.parentId, root.id);
      }
      final first = (await asA.getComments(id)).items.single;
      expect(first.replyCount, 3);
      expect(first.replies, hasLength(2));
      expect(first.updatedAt, isNull);
      expect(first.replies.first.updatedAt, isNull);
      expect((await asA.getReplies(id, root.id)).items, isEmpty,
          reason: 'no route on the BE: the thread shows the static label');
    });

    beTest('delete a comment: own only', () async {
      final id = (await post(asA)).id;
      final comment = await asA.addComment(id, 'Sẽ xoá');
      await expectApiError(asB.deleteComment(id, comment.id), status: 403);
      await asA.deleteComment(id, comment.id);
      expect((await asA.getComments(id)).items, isEmpty);
    });

    beTest('reporting twice gets the Vietnamese 409', () async {
      final id = (await post(asA)).id;
      await asB.reportPost(id,
          reason: ReportReason.spamPromo, note: 'quảng cáo');
      await expectApiError(
        asB.reportPost(id, reason: ReportReason.spamPromo),
        status: 409,
      );
    });

    beTest('delete a post: own only, then a Vietnamese 404', () async {
      final id = (await post(asA)).id;
      await expectApiError(asB.deletePost(id), status: 403);
      await asA.deletePost(id);
      await expectApiError(asB.getPost(id), status: 404);
    });

    beTest('"Đã lưu" is on the device and skips a post that is gone', () async {
      final keep = (await post(asA, title: 'Bài sẽ lưu')).id;
      final gone = (await post(asA, title: 'Bài sẽ xoá')).id;
      await asB.setSaved(keep, saved: true);
      await asB.setSaved(gone, saved: true);
      expect((await asB.getPost(keep)).savedByMe, isTrue);
      expect((await asA.getPost(keep)).savedByMe, isFalse);

      await asA.deletePost(gone);
      final saved = await asB.getSavedPosts();
      expect(saved.map((p) => p.id), [keep]);

      await asB.setSaved(keep, saved: false);
      expect(await asB.getSavedPosts(), isEmpty);
    });

    beTest('a post with no body is refused in Vietnamese', () async {
      await expectApiError(
        asA.createPost(const CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Không có nội dung',
          body: '',
        )),
        status: 400,
      );
    });
  });
}
