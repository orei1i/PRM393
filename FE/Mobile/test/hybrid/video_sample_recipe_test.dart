// test/hybrid/video_sample_recipe_test.dart
// Module `video` is mock on a real BE for now: a recipe video opens a labelled
// sample recipe, and nothing else changes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/video/data/video_api_service.dart';
import 'package:veganlife_mobile/features/video/presentation/widgets/video_recipe_sheet.dart';

Map<String, dynamic> _post({
  String type = 'recipe',
  String mediaType = 'Video',
  Object? video,
}) =>
    {
      'id': 'p_real',
      'type': type,
      'title': 'Bài',
      'body': 'Nội dung',
      'status': 'Published',
      'mediaType': mediaType,
      'mediaUrl': 'https://cdn.test/a.mp4',
      'author': {'id': 'u1', 'fullName': 'A'},
      'createdAt': '2026-11-01T00:00:00Z',
      if (video != null) 'video': video,
    };

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('on a real BE, with the video module mock', () {
    setUp(() => BackendModules.debugOverride({BackendModule.community}));

    test('a recipe video points at the sample recipe', () {
      final dto = PostDto.fromJson(_post());
      expect(dto.videoId, 'p_real');
      expect(dto.videoAiStatus, 'ready');
    });

    test('a Q&A video or a photo recipe has no recipe', () {
      expect(PostDto.fromJson(_post(type: 'discussion')).videoId, isNull);
      expect(PostDto.fromJson(_post(mediaType: 'Image')).videoId, isNull);
    });

    test('what the server says about the video wins', () {
      final dto = PostDto.fromJson(_post(video: {'id': 'v9', 'aiStatus': 'failed'}));
      expect(dto.videoId, 'v9');
      expect(dto.videoAiStatus, 'failed');
    });

    test('the sample opens under the real post id, with no video of its own',
        () async {
      final video = await MockVideoRepository().getVideo('p_real');
      expect(video.id, 'p_real');
      expect(video.aiStatus, 'ready');
      expect(video.videoUrl, isNull);
      expect(video.ingredients, isNotEmpty);
    });
  });

  testWidgets('the sheet says the recipe is a sample', (tester) async {
    BackendModules.debugOverride({BackendModule.community});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: VideoRecipeSheet(videoId: 'p_real')),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(DemoDataBanner.label), findsOneWidget);
    expect(find.text(sampleRecipeNote), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  group('fully mock', () {
    setUp(() => BackendModules.debugOverride(const {}));

    test('a post without a video object stays without a recipe', () {
      expect(PostDto.fromJson(_post()).videoId, isNull);
    });

    test('an unknown video is still 404', () async {
      await expectLater(
          MockVideoRepository().getVideo('khong_co'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)));
    });
  });

  group('with the video module real', () {
    setUp(() => BackendModules.debugOverride(
        {BackendModule.community, BackendModule.video}));

    test('no sample: the post has no recipe until the server says so', () {
      expect(PostDto.fromJson(_post()).videoId, isNull);
    });
  });
}
