// test/community/mobile_first_features_test.dart
// Split from test/mobile_first_features_test.dart: PostDto (community) and
// VideoRecipeDto.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/video/data/models/video_model.dart';
import 'package:veganlife_mobile/features/video/domain/entities/video_recipe.dart';

void main() {
  group('community', () {
    final json = {
      'id': 'p_1',
      'type': 'video',
      'author': {
        'id': 'u_1',
        'fullName': 'Lê Quang Tâm',
        'isVerifiedChef': true
      },
      'title': 'Chả lụa chay',
      'body': '…',
      'tags': ['high_protein'],
      'likeCount': 10,
      'commentCount': 2,
      'likedByMe': false,
      'createdAt': '2026-10-14T02:10:00Z',
      'video': {
        'id': 'vid_1',
        'durationSeconds': 724,
        'aiStatus': 'extracting'
      },
    };

    test('a legacy video post is a recipe with a video attachment', () {
      final post = PostDto.fromJson(json).toEntity();
      expect(post.type, PostType.recipe);
      expect(post.type.label, 'Công thức');
      expect(post.mediaType, PostMediaType.video);
      expect(post.author.isVerifiedChef, isTrue);
      expect(post.videoId, 'vid_1');
      expect(post.videoStatus, VideoAiStatus.extracting);
      expect(post.videoStatus!.isProcessing, isTrue);
      expect(post.hasAiRecipe, isFalse, reason: 'still extracting');
      final again = PostDto.fromJson(PostDto.fromJson(json).toJson());
      expect(again.videoDurationSeconds, 724);
      expect(again.type, 'recipe');
      expect(again.mediaType, 'Video');
    });

    test('"Hỏi đáp" is the discussion label', () {
      expect(PostType.discussion.label, 'Hỏi đáp');
      expect(PostType.fromApi('discussion'), PostType.discussion);
    });

    test('toggledLike adjusts the counter both ways', () {
      final post = PostDto.fromJson(json).toEntity();
      final liked = post.toggledLike();
      expect(liked.likedByMe, isTrue);
      expect(liked.likeCount, 11);
      expect(liked.toggledLike().likeCount, 10);
    });
  });

  test('VideoRecipeDto keeps low-confidence ingredients flagged', () {
    final video = VideoRecipeDto.fromJson({
      'id': 'vid_1',
      'title': 'Chả lụa chay',
      'author': {'id': 'u_1', 'fullName': 'Tâm'},
      'durationSeconds': 724,
      'aiStatus': 'ready',
      'ingredients': [
        {'name': 'Bột năng', 'quantity': '3 muỗng canh', 'atSecond': 58},
        {
          'name': 'Hạt nêm nấm',
          'quantity': '1 muỗng cà phê',
          'atSecond': 99,
          'uncertain': true
        },
      ],
      'steps': [
        {'index': 1, 'text': 'Ngâm đậu hũ ky', 'atSecond': 40},
      ],
    }).toEntity();
    expect(video.status, VideoAiStatus.ready);
    expect(video.ingredients.where((i) => i.uncertain).map((i) => i.name),
        ['Hạt nêm nấm']);
    expect(video.steps.single.atSecond, 40);
  });
}
