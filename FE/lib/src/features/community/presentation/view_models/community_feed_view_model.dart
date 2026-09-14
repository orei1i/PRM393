import 'dart:async';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../../admin_categories/domain/repositories/category_repository.dart';
import '../../domain/entities/community_entities.dart';
import '../../domain/repositories/community_repository.dart';

class CommunityFeedViewModel extends ViewModel {
  CommunityFeedViewModel(this.repository, this.auth, this._catalog) {
    _subscription = repository.changes.listen((_) => emit());
    _catalogSubscription = _catalog.changes.listen((_) {
      if (!filters.contains(_filter)) _filter = 'For you';
      _limit = AppConstants.pageSize;
      emit();
    });
    auth.addListener(_onRoleChange);
  }
  final CommunityRepository repository;
  final AuthViewModel auth;
  final CategoryRepository _catalog;
  late final StreamSubscription<void> _subscription, _catalogSubscription;
  String _query = '';
  String _filter = 'For you';
  int _limit = AppConstants.pageSize;
  List<String> get filters => List.unmodifiable([
    'For you',
    ..._catalog.categories.map((c) => c.name),
    'Quick recipes',
    'Videos',
    'Saved',
  ]);

  String get query => _query;
  String get filter => _filter;
  bool get canWrite => auth.canParticipate;
  List<RecipePost> get sourcePosts => repository.posts;
  List<RecipePost> get _filtered => sourcePosts
      .where(
        (post) =>
            !post.hidden &&
            ('${post.title} ${post.description} ${post.ingredients.join(' ')}')
                .toLowerCase()
                .contains(_query.toLowerCase()) &&
            switch (_filter) {
              'For you' => true,
              'Quick recipes' => post.minutes <= 20,
              'Videos' => post.isVideo,
              'Saved' => repository.isSaved(post.id, auth.userId),
              _ => post.category == _filter,
            },
      )
      .toList();
  List<RecipePost> get posts => List.unmodifiable(_filtered.take(_limit));
  bool get hasMore => _filtered.length > _limit;
  int votes(RecipePost post) => repository.votes(post.id);
  bool saved(RecipePost post) => repository.isSaved(post.id, auth.userId);

  void setQuery(String query) {
    _query = query.trim();
    _limit = AppConstants.pageSize;
    emit();
  }

  void setFilter(String filter) {
    _filter = filter;
    _limit = AppConstants.pageSize;
    emit();
  }

  void loadMore() {
    _limit += AppConstants.pageSize;
    emit();
  }

  void refresh() {
    _limit = AppConstants.pageSize;
    clearError();
  }

  bool toggleSave(RecipePost post) {
    if (!canWrite) return false;
    repository.toggleSaved(post.id, auth.userId!);
    return true;
  }

  void _onRoleChange() {
    _filter = 'For you';
    _limit = AppConstants.pageSize;
    emit();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _catalogSubscription.cancel();
    auth.removeListener(_onRoleChange);
    super.dispose();
  }
}
