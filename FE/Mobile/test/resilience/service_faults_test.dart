// test/resilience/service_faults_test.dart
// Every real endpoint family under every fault: a call either returns something
// safe or throws an [ApiException] with a message for people. No TypeError, no
// raw English, and no garbled Vietnamese reaches the caller.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/allergen_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/scanner/data/scanner_api_service.dart';

import 'fault_support.dart';

const _id = '6ae595c796695f5c139fa99b';

typedef _Call = Future<Object?> Function(ProviderContainer c);

final _plan = DateTime(2026, 10, 26);

/// `uploadImage` reads a real file.
final _upload = () {
  final dir = Directory.systemTemp.createTempSync('resilience');
  return File('${dir.path}/a.jpg')..writeAsBytesSync(Uint8List(12));
}();

final Map<String, _Call> _calls = {
  'auth: login': (c) =>
      c.read(authApiProvider).login(email: 'a@example.com', password: 'x'),
  'auth: refresh': (c) => c.read(authApiProvider).refresh('r'),
  'users/me': (c) => c.read(profileApiProvider).getMe(),
  'health-profile': (c) => c.read(mealPlannerApiProvider).getHealthProfile(),
  'metrics: list': (c) => c.read(mealPlannerApiProvider).getBodyMeasurements(),
  'meal-plans: current': (c) =>
      c.read(mealPlannerApiProvider).getCurrentMealPlan(),
  'meal-plans: generate': (c) =>
      c.read(mealPlannerApiProvider).generateMealPlan(startDate: _plan),
  'meal-plans: swap suggestions': (c) => c
      .read(mealPlannerApiProvider)
      .getSwapSuggestions(planId: 'p', date: _plan, slot: MealSlot.lunch),
  'meal-plans: swap': (c) => c.read(mealPlannerApiProvider).swapMeal(
      planId: 'p',
      request:
          SwapMealRequestDto(date: _plan, slot: MealSlot.lunch, recipeId: 'r')),
  'recipes: mine': (c) => c.read(mealPlannerApiProvider).getMyRecipes(),
  'recipes: by id': (c) => c.read(recipeApiProvider).getRecipe(_id),
  'pantry': (c) => c.read(pantryApiProvider).getPantry(),
  'ingredients: search': (c) => c.read(ingredientApiProvider).search('dau'),
  'ingredients: detail': (c) => c.read(ingredientApiProvider).detail(_id),
  'allergens': (c) => c.read(allergenApiProvider).search('dau'),
  'posts: feed': (c) => c.read(communityApiProvider).getFeed(),
  'posts: detail': (c) => c.read(communityApiProvider).getPost('p'),
  'posts: comments': (c) => c.read(communityApiProvider).getComments('p'),
  'posts: replies': (c) => c.read(communityApiProvider).getReplies('p', 'c'),
  'media: image': (c) => c.read(mediaApiProvider).uploadImage(
      PickedMedia.image(name: 'a.jpg', sizeBytes: 12, path: _upload.path)),
  'vision': (c) => c.read(scannerApiProvider).scanImage(Uint8List(8)),
};

final _technical = RegExp(
    r'Exception|TypeError|subtype|Null check|<html|Bad Gateway|Connection|'
    r'DioE|Internal Server|\bnull\b|Ã|á»');

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  Future<ProviderContainer> container(Fault? fault) async {
    SharedPreferences.setMockInitialValues({
      SessionController.accessTokenKey: 'test-token',
      'vl.user_id': '6ae5962396695f5c139fa9b0',
      'vl.display_name': 'FE Test',
      'vl.role': 'User',
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    c.read(dioProvider).httpClientAdapter = FaultBackend(fault);
    return c;
  }

  for (final MapEntry(key: name, value: call) in _calls.entries) {
    group(name, () {
      test('a healthy body works', () async {
        final c = await container(null);
        await call(c);
      });

      for (final fault in Fault.values) {
        test(fault.name, () async {
          final c = await container(fault);
          try {
            await call(c);
          } on ApiException catch (e) {
            expect(e.message, isNot(matches(_technical)));
            expect(e.message.trim(), isNotEmpty);
          }
        });
      }
    });
  }
}
