import 'dart:async';
import '../../../community/domain/repositories/community_repository.dart';
import '../../domain/entities/category_entities.dart';
import '../../domain/repositories/category_repository.dart';

class MockCategoryRepository implements CategoryRepository {
  MockCategoryRepository(this._community);
  final CommunityRepository _community;
  final _events = StreamController<void>.broadcast(sync: true);
  final _categories = [
    const FoodCategory(id: 'k1', name: 'Quick & easy'),
    const FoodCategory(id: 'k2', name: 'High protein'),
    const FoodCategory(id: 'k3', name: 'Breakfast'),
    const FoodCategory(id: 'k4', name: 'Comfort food'),
  ];
  final _tags = [
    const RecipeTag(id: 't1', name: 'Meal prep'),
    const RecipeTag(id: 't2', name: 'One pot'),
    const RecipeTag(id: 't3', name: 'Budget-friendly'),
  ];
  int _sequence = 10;
  @override
  Stream<void> get changes => _events.stream;
  @override
  List<FoodCategory> get categories => List.unmodifiable(_categories);
  @override
  List<RecipeTag> get tags => List.unmodifiable(_tags);
  @override
  int usage(String categoryName) =>
      _community.posts.where((p) => p.category == categoryName).length;
  @override
  void save(String name, {String? id, bool tag = false}) {
    final text = name.trim();
    if (text.length < 2 || text.length > 36) {
      throw ArgumentError('Use a name of 2–36 characters.');
    }
    if (tag) {
      if (_tags.any(
        (t) => t.id != id && t.name.toLowerCase() == text.toLowerCase(),
      )) {
        throw ArgumentError('That tag already exists.');
      }
      final index = _tags.indexWhere((t) => t.id == id);
      if (id != null && index < 0) throw ArgumentError('This tag was removed.');
      if (index < 0) {
        _tags.add(RecipeTag(id: 't${_sequence++}', name: text));
      } else {
        _tags[index] = RecipeTag(id: id!, name: text);
      }
    } else {
      if ([
        'for you',
        'quick recipes',
        'videos',
        'saved',
      ].contains(text.toLowerCase())) {
        throw ArgumentError('This name is reserved for a feed filter.');
      }
      if (_categories.any(
        (c) => c.id != id && c.name.toLowerCase() == text.toLowerCase(),
      )) {
        throw ArgumentError('That category already exists.');
      }
      final index = _categories.indexWhere((c) => c.id == id);
      if (id != null && index < 0) {
        throw ArgumentError('This category was removed.');
      }
      if (index < 0) {
        _categories.add(FoodCategory(id: 'k${_sequence++}', name: text));
      } else {
        final oldName = _categories[index].name;
        _categories[index] = FoodCategory(id: id!, name: text);
        for (final post in _community.posts.where(
          (p) => p.category == oldName,
        )) {
          _community.savePost(post.copyWith(category: text));
        }
      }
    }
    _events.add(null);
  }

  @override
  void delete(String id, {bool tag = false}) {
    if (tag) {
      _tags.removeWhere((t) => t.id == id);
    } else {
      final index = _categories.indexWhere((c) => c.id == id);
      if (index < 0) return;
      if (usage(_categories[index].name) > 0) {
        throw ArgumentError(
          'This category is in use. Move or delete its recipes first.',
        );
      }
      if (_categories.length == 1) {
        throw ArgumentError('Keep at least one category.');
      }
      _categories.removeAt(index);
    }
    _events.add(null);
  }

  @override
  void dispose() => _events.close();
}
