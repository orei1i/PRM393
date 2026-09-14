import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../../admin_categories/domain/repositories/category_repository.dart';
import '../../domain/entities/community_entities.dart';
import '../../domain/repositories/community_repository.dart';

class CreatePostViewModel extends ViewModel {
  CreatePostViewModel(
    this._repository,
    this._auth,
    this._catalog, {
    String? postId,
  }) : _original = postId == null ? null : _repository.find(postId),
       _requestedId = postId,
       _actorId = _auth.userId {
    final post = _original;
    _title = post?.title ?? '';
    _description = post?.description ?? '';
    _ingredients = post?.ingredients.join(', ') ?? '';
    _steps = post?.steps.join('\n') ?? '';
    setCategory(post?.category ?? categories.first);
    _isVideo = post?.isVideo ?? false;
    _subscription = _catalog.changes.listen((_) => emit());
  }
  final CommunityRepository _repository;
  final AuthViewModel _auth;
  final CategoryRepository _catalog;
  final RecipePost? _original;
  final String? _requestedId, _actorId;
  late final StreamSubscription<void> _subscription;
  late String _title, _description, _ingredients, _steps;
  String? _categoryId;
  late bool _isVideo;

  String get title => _title;
  String get description => _description;
  String get ingredients => _ingredients;
  String get steps => _steps;
  bool get isVideo => _isVideo;
  bool get editing => _requestedId != null;
  List<String> get categories =>
      List.unmodifiable(_catalog.categories.map((c) => c.name));
  String get category =>
      _catalog.categories.where((c) => c.id == _categoryId).firstOrNull?.name ??
      categories.first;

  void setTitle(String value) {
    _title = value;
    emit();
  }

  void setDescription(String value) {
    _description = value;
    emit();
  }

  void setIngredients(String value) {
    _ingredients = value;
    emit();
  }

  void setSteps(String value) {
    _steps = value;
    emit();
  }

  void setCategory(String value) {
    _categoryId = _catalog.categories
        .where((c) => c.name == value)
        .firstOrNull
        ?.id;
    emit();
  }

  void setVideo(bool value) {
    if (!editing) {
      _isVideo = value;
      emit();
    }
  }

  String? save() {
    if (disposed) return null;
    if (!_auth.canParticipate || _auth.userId != _actorId) {
      fail('Sign in before publishing.');
      return null;
    }
    if (editing &&
        (_original == null || _repository.find(_requestedId!) == null)) {
      fail('This content is no longer available.');
      return null;
    }
    if (_original != null && _original.authorId != _auth.userId) {
      fail('You can only edit your own content.');
      return null;
    }
    if (title.trim().length < 5 ||
        title.trim().length > 100 ||
        description.trim().length < 10 ||
        description.trim().length > 2000) {
      fail('Use a 5–100 character title and a 10–2,000 character description.');
      return null;
    }
    final ingredientList = ingredients
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final stepList = steps
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (ingredientList.isEmpty || stepList.isEmpty) {
      fail('Add ingredients and at least one cooking step.');
      return null;
    }
    final post =
        _original?.copyWith(
          title: title.trim(),
          description: description.trim(),
          category: category,
          ingredients: List.unmodifiable(ingredientList),
          steps: List.unmodifiable(stepList),
        ) ??
        RecipePost(
          id: _repository.newId(),
          authorId: _auth.userId!,
          author: _auth.name,
          title: title.trim(),
          description: description.trim(),
          category: category,
          ingredients: List.unmodifiable(ingredientList),
          steps: List.unmodifiable(stepList),
          isVideo: isVideo,
        );
    _repository.savePost(post);
    clearError();
    return post.id;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
