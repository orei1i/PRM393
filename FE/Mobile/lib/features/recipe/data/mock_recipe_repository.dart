// lib/features/recipe/data/mock_recipe_repository.dart
import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import 'mock/recipe_mock_data.dart';
import 'models/recipe_detail_model.dart';
import 'recipe_api_service.dart';

/// Recipe details from [mockRecipeDetail]. An unknown id → 404; an id
/// containing `#fail` → 503 (exercises the error state in tests).
class MockRecipeRepository implements RecipeApiService {
  @override
  Future<RecipeDetailDto> getRecipe(String id) async {
    await mockDelay(500);
    if (id.contains('#fail')) {
      throw const ApiException(
          message: 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
          statusCode: 503);
    }
    final json = mockRecipeDetail(id);
    if (json == null) {
      throw const ApiException(
          message: 'Không tìm thấy công thức.',
          statusCode: 404,
          code: 'not_found');
    }
    return RecipeDetailDto.fromJson(Map<String, dynamic>.from(json));
  }
}
