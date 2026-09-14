import '../entities/category_entities.dart';

abstract interface class CategoryRepository {
  Stream<void> get changes;
  List<FoodCategory> get categories;
  List<RecipeTag> get tags;
  int usage(String categoryName);
  void save(String name, {String? id, bool tag = false});
  void delete(String id, {bool tag = false});
  void dispose();
}
