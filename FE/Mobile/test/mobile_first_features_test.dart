// test/mobile_first_features_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_envelope.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/core/utils/text_search.dart';
import 'package:veganlife_mobile/features/chef/data/models/chef_model.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/profile/data/models/user_profile_model.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';
import 'package:veganlife_mobile/features/video/data/models/video_model.dart';
import 'package:veganlife_mobile/features/video/domain/entities/video_recipe.dart';

void main() {
  group('ApiResponse envelope', () {
    test('unwraps data on success', () {
      final body = {
        'success': true,
        'message': null,
        'data': {'id': 'u_1'},
        'statusCode': 200
      };
      expect(unwrapEnvelope(body), {'id': 'u_1'});
    });

    test('throws ApiException with the server message on success:false', () {
      final body = {
        'success': false,
        'message': 'Email đã tồn tại.',
        'data': null,
        'statusCode': 409
      };
      expect(
        () => unwrapEnvelope(body),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Email đã tồn tại.')
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('passes through bodies that are not envelopes', () {
      expect(unwrapEnvelope({'items': <Object>[]}), {'items': <Object>[]});
      expect(unwrapEnvelope([1, 2]), [1, 2]);
    });
  });

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

    test('PostDto maps author, video block and AI status', () {
      final post = PostDto.fromJson(json).toEntity();
      expect(post.type, PostType.video);
      expect(post.author.isVerifiedChef, isTrue);
      expect(post.videoId, 'vid_1');
      expect(post.videoStatus, VideoAiStatus.extracting);
      expect(post.videoStatus!.isProcessing, isTrue);
      expect(
          PostDto.fromJson(PostDto.fromJson(json).toJson())
              .videoDurationSeconds,
          724);
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

  test('ChefDto parses packages and UTC slots to local time', () {
    final chef = ChefDto.fromJson({
      'id': 'u_chef',
      'fullName': 'Phạm Thu Hà',
      'specialties': ['Dinh dưỡng lâm sàng'],
      'rating': 4.8,
      'startingPriceVnd': 450000,
      'packages': [
        {
          'id': 'pk',
          'name': 'Tư vấn nhanh',
          'durationMinutes': 30,
          'priceVnd': 450000,
          'mode': 'online'
        },
      ],
      'availableSlots': ['2026-10-20T12:30:00Z'],
    }).toEntity();
    expect(chef.packages.single.priceVnd, 450000);
    expect(chef.availableSlots.single.isUtc, isFalse);
  });

  test('UserProfileDto accepts numeric enums from ASP.NET', () {
    final profile = UserProfileDto.fromJson({
      'id': 'u_me',
      'email': 'a@b.vn',
      'fullName': 'Minh Anh',
      'phone': '0912345678',
      'role': 'Member',
      'status': 2,
      'authType': 1,
      'createdAt': '2026-07-02T08:15:00Z',
      'chefApplication': {'status': 'pending'},
    }).toEntity();
    expect(profile.status, UserStatus.locked);
    expect(profile.signedInWithGoogle, isTrue);
    expect(profile.chefApplication, ChefApplicationStatus.pending);
  });

  group('formatting & search', () {
    test('durations and VND', () {
      expect(formatDuration(724), '12:04');
      expect(formatDuration(3725), '1:02:05');
      expect(formatVnd(350000), '350.000đ');
    });

    test('accent-insensitive Vietnamese search', () {
      expect(foldVietnamese('Ẩm thực chay Huế'), 'am thuc chay hue');
      expect(matchesQuery('Tôn Nữ Minh Châu · Ẩm thực chay Huế', 'chay hue'),
          isTrue);
      expect(matchesQuery('Lê Quang Tâm', 'thu ha'), isFalse);
    });
  });
}
