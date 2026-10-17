// test/community/int_leftovers_test.dart
// Split from test/int_leftovers_test.dart: the Reels strip data. (The
// post-detail sponsored-card tests are gone with the card: the post detail
// shows no "Được tài trợ", see post_detail_test.)
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/reels/data/reels_api_service.dart';

void main() {
  group('Reels strip', () {
    test('at least 7 clips for a guest, sample files kept per post', () async {
      final reels = await MockReelsRepository(MockCommunityRepository(
          currentUserName: () => 'Khách', isSignedIn: () => false)).getReels();
      expect(reels.length, greaterThanOrEqualTo(7));
      for (final r in reels) {
        expect(reelSampleVideos, contains(r.videoUrl));
        expect(r.durationSeconds, isNotNull);
        final post = r.post.toEntity();
        expect(post.hasVideo, isTrue);
        expect(PostType.values, contains(post.type));
      }
      final added =
          reels.where((r) => r.post.id.startsWith('p_reel_')).toList();
      expect(added, hasLength(4));
      for (final r in added) {
        expect(r.videoUrl, r.post.mediaUrl);
        expect(r.durationSeconds, lessThan(70));
        expect(r.toEntity().hasRecipe, isTrue);
      }
    });
  });
}
