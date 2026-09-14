import '../../../community/domain/entities/community_entities.dart';
import '../../../community/domain/repositories/community_repository.dart';
import '../../domain/entities/explore_items.dart';
import '../../domain/repositories/explore_repository.dart';

class MockExploreRepository implements ExploreRepository {
  MockExploreRepository(this._community);
  final CommunityRepository _community;
  @override
  List<PostItem> get recipes => _community.posts
      .where((p) => !p.hidden && !p.isVideo)
      .map(PostItem.new)
      .toList(growable: false);
  @override
  List<VideoItem> get videos => _community.posts
      .where((p) => !p.hidden && p.isVideo)
      .map((p) => VideoItem(CookingVideo(post: p)))
      .toList(growable: false);
}
