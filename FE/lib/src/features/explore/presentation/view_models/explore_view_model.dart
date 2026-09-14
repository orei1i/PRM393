import '../../../admin_categories/domain/repositories/category_repository.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../../community/domain/entities/community_entities.dart';
import '../../../community/domain/repositories/community_repository.dart';
import '../../../community/presentation/view_models/community_feed_view_model.dart';
import '../../domain/repositories/explore_repository.dart';

class ExploreViewModel extends CommunityFeedViewModel {
  ExploreViewModel(
    CommunityRepository repository,
    AuthViewModel auth,
    this._explore,
    CategoryRepository catalog,
  ) : super(repository, auth, catalog);
  final ExploreRepository _explore;
  List<String> get guestFilters =>
      List.unmodifiable(filters.where((f) => f != 'Saved'));
  bool get needsAuthentication => !auth.canParticipate;
  @override
  List<RecipePost> get sourcePosts => [
    ..._explore.recipes.map((p) => p.recipe),
    ..._explore.videos.map((p) => p.video.post),
  ];
}
