// integration_test_be/community_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/community/data/backend_posts.dart';
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

    beTest('B15: the feed walks by cursor, in the same order as by page',
        () async {
      for (var i = 0; i < 4; i++) {
        await post(asA, title: 'Bài thử con trỏ số ${i + 1}');
      }
      final byCursor = <String>[];
      String? cursor;
      do {
        final page = await asA.getFeed(cursor: cursor, limit: 3);
        expect(page.items.length, lessThanOrEqualTo(3));
        byCursor.addAll(page.items.map((p) => p.id));
        cursor = page.nextCursor;
      } while (cursor != null);

      final byPage = <String>[];
      for (var page = 1;; page++) {
        final res =
            await a.raw('GET', '/posts', query: {'page': page, 'pageSize': 3});
        byPage.addAll(res.dataMap['items'] is List
            ? (res.dataMap['items'] as List)
                .map((p) => (p as Map)['id'] as String)
            : const <String>[]);
        if (page >= (res.dataMap['totalPages'] as num)) break;
      }
      expect(byCursor, byPage);
      expect(byCursor.toSet(), hasLength(byCursor.length));

      final typed = await asA.getFeed(type: PostType.discussion, limit: 2);
      final next = await asA.getFeed(
          type: PostType.discussion, limit: 2, cursor: typed.nextCursor);
      expect(next.items.map((p) => p.type).toSet(),
          {PostType.discussion.apiValue});
    });

    beTest('B15: a bad cursor is a Vietnamese 400', () async {
      await expectApiError(asA.getFeed(cursor: 'khong-phai-id'), status: 400);
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

    beTest('B28: like, unlike, like again', () async {
      final id = (await post(asA)).id;
      for (final liked in [true, false, true]) {
        await asB.setLiked(id, liked: liked);
        final read = await asB.getPost(id);
        expect(read.likedByMe, liked);
        expect(read.likeCount, liked ? 1 : 0);
        final feed = await asB.getFeed(limit: 50);
        final row = feed.items.firstWhere((p) => p.id == id);
        expect(row.likedByMe, liked);
      }
      await asA.setLiked(id, liked: true);
      expect((await asA.getPost(id)).likeCount, 2);
    });

    beTest('a post moved to Pending: only its author finds it', () async {
      final store = MyPostIdsStore(currentUserId: () => a.id);
      final asAuthor = RemoteCommunityApiService(a.dio,
          currentUserId: () => a.id, myPostIds: store);
      final dto = await asAuthor.createPost(const CreatePostRequestDto(
          type: PostType.discussion,
          title: 'FE IT bài bị đưa về chờ duyệt',
          body: 'Nội dung đủ dài để máy chủ nhận bài viết này.'));
      created.add(dto.id);
      expect(dto.status, 'Published');

      final admin = await be.adminToken();
      final hidden = await rawRequest('POST', '/admin/posts/${dto.id}/actions',
          token: admin, data: {'action': 'hide'});
      expect(hidden.status, 200);
      expect(hidden.dataMap['status'], 'Pending');

      // Off the feed for everyone, the author included.
      final feed = await asAuthor.getFeed(limit: 50);
      expect(feed.items.map((p) => p.id), isNot(contains(dto.id)));
      await expectApiError(
          RemoteCommunityApiService(be.guestDio()).getPost(dto.id),
          status: 404);
      await expectApiError(asB.getPost(dto.id), status: 404);

      // The owner still reads it, and "Bài của tôi" finds it by its id.
      final own = (await asAuthor.getPost(dto.id)).toEntity();
      expect(own.isPending, isTrue);
      final mine = await asAuthor.getMyPosts();
      expect(mine.singleWhere((p) => p.id == dto.id).status, 'Pending');

      // A device that doesn't know the id can't see it: the limit we report.
      final elsewhere = RemoteCommunityApiService(a.dio,
          currentUserId: () => a.id,
          myPostIds: MyPostIdsStore(currentUserId: () => a.id));
      expect((await elsewhere.getMyPosts()).map((p) => p.id),
          isNot(contains(dto.id)));

      // Rejected: still the author's, and back on the feed once approved.
      final rejected = await rawRequest('POST', '/admin/posts/${dto.id}/review',
          token: admin, data: {'decision': 'Reject', 'reason': 'Thiếu nguồn'});
      expect(rejected.dataMap['status'], 'Rejected');
      final refused = (await asAuthor.getPost(dto.id)).toEntity();
      expect(refused.isRejected, isTrue);
      expect(refused.rejectionReason, isNull,
          reason: 'PostResponse has no rejectionReason yet. Once it does, the '
              'banner shows the reason by itself: check this and drop it.');

      await rawRequest('POST', '/admin/posts/${dto.id}/review',
          token: admin, data: {'decision': 'Approve'});
      expect((await asAuthor.getFeed(limit: 50)).items.map((p) => p.id),
          contains(dto.id));
    });

    beTest('PUT /posts/{id} is a 405, so nothing pretends it saved', () async {
      final dto = await post(asA);
      await expectApiError(
          asA.updatePost(
              dto.id,
              const UpdatePostRequestDto(
                  title: 'FE IT tiêu đề đã sửa',
                  body: 'Nội dung đã sửa của bài này.',
                  mediaType: PostMediaType.text)),
          status: 405);
      // Once this fails the BE has the route: turn on BackendModules.postEdit.
      expect((await asA.getPost(dto.id)).title, dto.title);
    });

    beTest('B27: three reports hide a post, an admin brings it back', () async {
      final id = (await post(asA)).id;
      for (var i = 0; i < 3; i++) {
        final reporter = await be.newUser(name: 'FE IT Reporter');
        await RemoteCommunityApiService(reporter.dio)
            .reportPost(id, reason: ReportReason.spamPromo);
      }
      await expectApiError(RemoteCommunityApiService(be.guestDio()).getPost(id),
          status: 404);
      expect((await asA.getPost(id)).status, 'Pending');

      final admin = await be.adminToken();
      final queue = await rawRequest('GET', '/admin/posts',
          token: admin, query: {'status': 'Pending', 'pageSize': 50});
      expect((queue.dataMap['items'] as List).map((p) => (p as Map)['id']),
          contains(id));
      expect(
          (await a.raw('POST', '/admin/posts/$id/review',
                  data: {'decision': 'Approve'}))
              .status,
          403);
      final approved = await rawRequest('POST', '/admin/posts/$id/review',
          token: admin, data: {'decision': 'Approve'});
      expect(approved.dataMap['status'], 'Published');
      expect(
          (await RemoteCommunityApiService(be.guestDio()).getPost(id)).id, id);

      final late = await be.newUser(name: 'FE IT Reporter');
      await RemoteCommunityApiService(late.dio)
          .reportPost(id, reason: ReportReason.spamPromo);
      expect(
          (await RemoteCommunityApiService(be.guestDio()).getPost(id)).id, id,
          reason: 'the count started over');
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

    beTest('B16: 2 previewed, the route reads them all, oldest first',
        () async {
      final id = (await post(asB)).id;
      final root = await asA.addComment(id, 'Bình luận gốc');
      for (var i = 0; i < 4; i++) {
        final reply =
            await asB.addComment(id, 'Phản hồi ${i + 1}', parentId: root.id);
        expect(reply.parentId, root.id);
      }
      final first = (await asA.getComments(id)).items.single;
      expect(first.replyCount, 4);
      expect(first.replies, hasLength(2));
      expect(first.updatedAt, isNull, reason: 'B17');
      expect(first.replies.first.updatedAt, isNull);

      final all = await asA.getReplies(id, root.id);
      expect(all.items.map((r) => r.text),
          ['Phản hồi 1', 'Phản hồi 2', 'Phản hồi 3', 'Phản hồi 4']);
      expect(all.nextCursor, isNull);
      final guest = RemoteCommunityApiService(be.guestDio());
      expect((await guest.getReplies(id, root.id)).items, hasLength(4));
    });

    beTest('B16: deleting a reply or a root keeps the counts right', () async {
      final id = (await post(asB)).id;
      final root = await asA.addComment(id, 'Bình luận gốc');
      final replies = [
        for (var i = 0; i < 3; i++)
          await asB.addComment(id, 'Phản hồi ${i + 1}', parentId: root.id),
      ];
      expect((await asA.getPost(id)).commentCount, 4);

      await asB.deleteComment(id, replies.first.id);
      expect((await asA.getPost(id)).commentCount, 3);
      expect((await asA.getComments(id)).items.single.replyCount, 2);

      await asA.deleteComment(id, root.id);
      expect((await asA.getPost(id)).commentCount, 0);
      expect((await asA.getComments(id)).items, isEmpty);
      await expectApiError(asA.getReplies(id, root.id), status: 404);
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
