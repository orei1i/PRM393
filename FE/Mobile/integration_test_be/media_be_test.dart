// integration_test_be/media_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/reels/data/reels_api_service.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('media', skip: be.skipReason, () {
    late BeUser me;
    late MediaApiService media;
    late CommunityApiService community;
    final created = <String>[];

    Future<PickedMedia> image() async {
      final bytes = pngBytes();
      return PickedMedia.image(
        name: 'dau_hu.png',
        sizeBytes: bytes.length,
        path: await tempFile('dau_hu.png', bytes),
      );
    }

    Future<PickedMedia> video() async {
      final bytes = mp4Bytes();
      return PickedMedia.video(
        name: 'banh_xeo.mp4',
        sizeBytes: bytes.length,
        durationSeconds: 0,
        path: await tempFile('banh_xeo.mp4', bytes),
      );
    }

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Media');
      media = RemoteMediaApiService(me.dio);
      community = RemoteCommunityApiService(me.dio, currentUserId: () => me.id);
    });

    tearDownAll(() async {
      for (final id in created) {
        await me.raw('DELETE', '/posts/$id');
      }
    });

    beTest('image: upload, POST the raw url, display the absolute one',
        () async {
      var progress = 0.0;
      final upload = await media.uploadImage(await image(),
          onProgress: (p) => progress = p);
      expect(progress, 1);
      expect(upload.sizeBytes, greaterThan(0));
      expect(upload.absoluteUrl, startsWith(Env.apiOrigin));

      final post = await community.createPost(CreatePostRequestDto(
        type: PostType.recipe,
        title: 'Bài có ảnh thật',
        body: 'Ảnh tải lên từ bộ kiểm thử tích hợp.',
        mediaType: PostMediaType.image,
        mediaUrl: upload.mediaUrl,
      ));
      created.add(post.id);
      expect(post.mediaType, PostMediaType.image.apiValue);
      expect(post.mediaUrl, upload.absoluteUrl);

      final read = await community.getPost(post.id);
      expect(read.mediaUrl, upload.absoluteUrl);

      final file = await rawRequest('GET', upload.absoluteUrl);
      expect(file.status, 200,
          reason: 'B12: the static file is 404 when wwwroot was missing as the '
              'BE started. Create BE/ControllerLayer/wwwroot and restart it.');
    });

    beTest('POST with the absolute url is refused, so only the raw one is sent',
        () async {
      final upload = await media.uploadImage(await image());
      await expectApiError(
        community.createPost(CreatePostRequestDto(
          type: PostType.recipe,
          title: 'Bài có ảnh sai đường dẫn',
          body: 'Đường dẫn tuyệt đối không được nhận.',
          mediaType: PostMediaType.image,
          mediaUrl: upload.absoluteUrl,
        )),
        status: 400,
      );
    });

    beTest('video: upload, post, it plays from Reels', () async {
      final upload = await media.uploadVideo(await video());
      final post = await community.createPost(CreatePostRequestDto(
        type: PostType.recipe,
        title: 'Bài có video thật',
        body: 'Video tải lên từ bộ kiểm thử tích hợp.',
        mediaType: PostMediaType.video,
        mediaUrl: upload.mediaUrl,
      ));
      created.add(post.id);
      expect(post.mediaUrl, upload.absoluteUrl);
      expect(post.videoId, isNull,
          reason: 'B21 workaround: the placeholder `video` is dropped');

      final file = await rawRequest('GET', upload.absoluteUrl);
      expect(file.status, 200, reason: 'B12, see the image test');

      final reels = await RemoteReelsApiService(me.dio).getReels(limit: 50);
      final reel = reels.firstWhere((r) => r.post.id == post.id);
      expect(reel.videoUrl, upload.absoluteUrl);
    });

    beTest('another file type is refused in Vietnamese', () async {
      await expectApiError(
        media.uploadImage(PickedMedia.image(
          name: 'ghi_chu.txt',
          sizeBytes: 5,
          path: await tempFile('ghi_chu.txt', [104, 101, 108, 108, 111]),
        )),
      );
    });

    beTest('a guest cannot upload', () async {
      await expectApiError(
        RemoteMediaApiService(be.guestDio()).uploadImage(await image()),
        status: 401,
      );
    });
  });
}
