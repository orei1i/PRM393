// test/resilience/field_faults_test.dart
// One bad field at a time: a whole-body fault mostly stops at the first field a
// parser refuses, so the rest of the parser and the screen are never reached.
// Here each field of a route's healthy body, in turn, goes missing, null, empty
// or the wrong type, and the screen still has to cope.
@Timeout(Duration(minutes: 8))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/body_metrics_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_recipes_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

import 'fault_support.dart';

const _id = '6ae595c796695f5c139fa99b';
const _postId = '6ae5a8876c01fc07a925777c';

final _post = PostDto.fromJson({
  'id': _postId,
  'type': 'recipe',
  'author': {'id': 'u1', 'fullName': 'Ai đó'},
  'title': 'Bún riêu chay',
  'body': 'Nội dung bài viết.',
  'createdAt': '2026-10-31T07:19:11.908Z',
  'status': 'Published',
  'mediaType': 'Text',
  'likeCount': 3,
}).toEntity();

/// A screen and the routes whose fields are damaged while it is up.
final _cases = <(String, Widget Function(), List<String>)>[
  ('Trang chủ', () => const FeedScreen(), ['GET /posts']),
  (
    'post detail',
    () => PostDetailScreen(post: _post),
    ['GET /posts/$_postId', 'GET /posts/$_postId/comments']
  ),
  (
    'Thực đơn',
    () => const MealPlannerScreen(),
    ['GET /meal-plans/current', 'GET /health-profile/me']
  ),
  (
    'recipe detail',
    () => const RecipeDetailScreen(recipeId: _id, name: 'Món'),
    ['GET /recipes/$_id', 'GET /health-profile/me']
  ),
  ('tủ lạnh', () => const PantryScreen(), ['GET /users/me/ingredients']),
  (
    'theo dõi cân nặng',
    () => const BodyMetricsScreen(),
    ['GET /health-profile/me/metrics', 'GET /health-profile/me']
  ),
  ('Tôi', () => const ProfileScreen(), ['GET /users/me']),
  (
    'tìm kiếm',
    () => const SearchScreen(initialQuery: 'dau hu'),
    ['GET /posts', 'GET /ingredients']
  ),
  (
    'hồ sơ sức khoẻ',
    () => const HealthProfileEditScreen(),
    ['GET /health-profile/me']
  ),
  (
    'công thức của tôi',
    () => const MyRecipesScreen(),
    ['GET /users/me/recipes']
  ),
  (
    'nguyên liệu',
    () => const IngredientDetailScreen(ingredientId: _id, name: 'Đậu hũ'),
    ['GET /ingredients/$_id']
  ),
];

/// `days[].meals.lunch.calories` for every field under [value], lists folded.
Set<String> _paths(Object? value, [String at = '']) => switch (value) {
      final Map<String, dynamic> m => {
          for (final e in m.entries) ...{
            '$at${e.key}',
            ..._paths(e.value, '$at${e.key}.'),
          },
        },
      final List<Object?> l => {
          for (final e in l)
            ..._paths(
                e, at.isEmpty ? '[].' : '${at.substring(0, at.length - 1)}[].'),
        },
      _ => {},
    };

const _remove = Object();

/// [value] with every field at [path] replaced by [by] ([_remove]: left out).
Object? _set(Object? value, String path, Object? by, [String at = '']) =>
    switch (value) {
      final Map<String, dynamic> m => {
          for (final e in m.entries)
            if ('$at${e.key}' == path)
              if (identical(by, _remove)) ...{} else e.key: by
            else
              e.key: _set(e.value, path, by, '$at${e.key}.'),
        },
      final List<Object?> l => [
          for (final e in l)
            _set(e, path, by,
                at.isEmpty ? '[].' : '${at.substring(0, at.length - 1)}[].'),
        ],
      _ => value,
    };

/// The wrong things for a field holding [sample].
List<Object?> _wrong(Object? sample) => switch (sample) {
      num() => [_remove, null, 'mười hai', -1, 0, 99999],
      String() => [_remove, null, '', 12345, <Object?>[], '   '],
      bool() => [_remove, null, 'có'],
      List<Object?>() => [
          _remove,
          null,
          <String, dynamic>{},
          'x',
          <Object?>[],
          [null, 1]
        ],
      Map<String, dynamic>() => [
          _remove,
          null,
          <Object?>[],
          'x',
          <String, dynamic>{}
        ],
      _ => [_remove, 'x', 12345, <Object?>[]],
    };

Object? _first(Object? value, String path, [String at = '']) {
  if (value is Map<String, dynamic>) {
    for (final e in value.entries) {
      if ('$at${e.key}' == path) return e.value;
      final deep = _first(e.value, path, '$at${e.key}.');
      if (deep != null) return deep;
    }
  } else if (value is List<Object?>) {
    final next = at.isEmpty ? '[].' : '${at.substring(0, at.length - 1)}[].';
    for (final e in value) {
      final deep = _first(e, path, next);
      if (deep != null) return deep;
    }
  }
  return null;
}

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  for (final (name, build, routes) in _cases) {
    testWidgets('$name: one bad field at a time', (tester) async {
      tester.view
        ..physicalSize = const Size(411, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final failures = <String>[];

      Future<void> once(String route, String path, Object? by) async {
        SharedPreferences.setMockInitialValues({
          SessionController.accessTokenKey: 'test-token',
          'vl.user_id': '6ae5962396695f5c139fa9b0',
          'vl.display_name': 'FE Test',
          'vl.role': 'User',
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          plannerClockProvider
              .overrideWithValue(() => DateTime(2026, 10, 31, 9)),
        ]);
        container.read(dioProvider).httpClientAdapter = FaultBackend(null,
            damage: (r, body) => r == route && body is Map<String, dynamic>
                ? {...body, 'data': _set(body['data'], path, by)}
                : body);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              scaffoldMessengerKey: rootScaffoldMessengerKey, home: build()),
        ));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        final error = tester.takeException();
        final box = find.byType(ErrorWidget).evaluate().isNotEmpty;
        // Absurd numbers can push a row past its width: ugly, not a crash.
        final cosmetic = '$error'.contains('overflowed');
        if ((error != null && !cosmetic) || box) {
          failures
              .add('$route $path = ${identical(by, _remove) ? '(gone)' : by}: '
                  '${error ?? 'error box'}');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        tester.takeException();
        container.dispose();
      }

      for (final route in routes) {
        final body = healthyBody(route);
        final data = body is Map<String, dynamic> ? body['data'] : null;
        for (final path in _paths(data)) {
          for (final by in _wrong(_first(data, path))) {
            await once(route, path, by);
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
