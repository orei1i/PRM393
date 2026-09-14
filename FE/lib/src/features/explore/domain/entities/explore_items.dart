import '../../../community/domain/entities/community_entities.dart';

class PostItem {
  const PostItem(this.recipe);
  final RecipePost recipe;
}

class VideoItem {
  const VideoItem(this.video);
  final CookingVideo video;
}
