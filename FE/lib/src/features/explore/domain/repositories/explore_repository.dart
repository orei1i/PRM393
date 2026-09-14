import '../entities/explore_items.dart';

abstract interface class ExploreRepository {
  List<PostItem> get recipes;
  List<VideoItem> get videos;
}
