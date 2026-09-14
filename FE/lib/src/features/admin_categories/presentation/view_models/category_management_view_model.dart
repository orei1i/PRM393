import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/category_entities.dart';
import '../../domain/repositories/category_repository.dart';

class CategoryManagementViewModel extends ViewModel {
  CategoryManagementViewModel(this._repository, this._auth) {
    _subscription = _repository.changes.listen((_) => emit());
    _auth.addListener(clearError);
  }
  final CategoryRepository _repository;
  final AuthViewModel _auth;
  late final StreamSubscription<void> _subscription;
  List<FoodCategory> get categories =>
      _auth.isAdmin ? _repository.categories : [];
  List<RecipeTag> get tags => _auth.isAdmin ? _repository.tags : [];
  int usage(String name) => _repository.usage(name);
  bool save(String name, {String? id, bool tag = false}) =>
      _guard(() => _repository.save(name, id: id, tag: tag));
  bool delete(String id, {bool tag = false}) =>
      _guard(() => _repository.delete(id, tag: tag));
  bool _guard(void Function() action) {
    if (!_auth.isAdmin) {
      fail('Administrator access required.');
      return false;
    }
    try {
      action();
      clearError();
      return true;
    } on ArgumentError catch (error) {
      fail(error.message.toString());
      return false;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _auth.removeListener(clearError);
    super.dispose();
  }
}
