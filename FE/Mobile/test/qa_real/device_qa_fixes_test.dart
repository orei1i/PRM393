// test/qa_real/device_qa_fixes_test.dart
// Regressions found running the app on the emulator against the real BE.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/labels.dart';
import 'package:veganlife_mobile/core/widgets/app_logo.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/report_post_sheet.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/macro_progress_bar.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_repository.dart';

class _RefusingCommunity implements CommunityApiService {
  _RefusingCommunity(this.error);

  final ApiException error;

  @override
  Future<void> reportPost(String postId,
          {required ReportReason reason, String? note}) async =>
      throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCatalog implements RecipeCatalog {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'catalogue must not be read for ${invocation.memberName}');
}

Recipe _dish(String id, {List<String> allergens = const []}) => Recipe(
      id: id,
      name: 'Món $id',
      nutrition: const Nutrition(calories: 400),
      allergens: allergens,
    );

void main() {
  group('BE diet tags', () {
    // db.Recipes.distinct('DietTags') on the seeded BE.
    const seeded = [
      'baked',
      'balanced',
      'calm',
      'classic',
      'colorful',
      'comfort',
      'creamy',
      'crispy',
      'crunchy',
      'delicate',
      'detox',
      'drink',
      'easy_digest',
      'fresh',
      'high_fiber',
      'high_protein',
      'light',
      'no_cook',
      'quick',
      'refreshing',
      'rich',
      'savory',
      'spicy',
      'sweet',
      'traditional',
      'warm',
      'whole_food',
    ];

    test('every seeded tag has a Vietnamese label', () {
      for (final tag in seeded) {
        expect(dietTagLabel(tag), isNot(tag), reason: tag);
      }
    });

    test('an unknown tag does not show a raw id', () {
      expect(dietTagLabel('low_fat'), 'low fat');
    });
  });

  group('swap choices', () {
    test('leaves out the dish already in the slot, keeps three', () {
      final choices = MealPlanController.swapChoices(
        [_dish('a'), _dish('b'), _dish('c'), _dish('d')],
        current: _dish('a'),
        allergies: const [],
      );
      expect(choices.map((r) => r.id), ['b', 'c', 'd']);
    });

    test('an empty slot keeps all, an allergen is still left out', () {
      final choices = MealPlanController.swapChoices(
        [
          _dish('a'),
          _dish('b', allergens: const ['peanut'])
        ],
        current: null,
        allergies: const ['peanut'],
      );
      expect(choices.map((r) => r.id), ['a']);
    });
  });

  group('recipe page of a sample chef plan dish', () {
    RemoteRecipeApiService service(PlanItemSnapshots snapshots) =>
        RemoteRecipeApiService(
          catalog: () => _NoCatalog(),
          snapshots: () => snapshots,
          mock: MockRecipeRepository(),
        );

    Map<String, dynamic> plan() => {
          'id': 'p1',
          'days': [
            {
              'date': '2026-10-31',
              'meals': {
                'lunch': {
                  'id': '4a5add6da15c4fad8bedb4f36b5cd4d1',
                  'recipeId': 'rc_com_tam_chay',
                  'name': 'Cơm tấm chay sườn đậu',
                  'calories': 650,
                  'source': 'chef',
                },
              },
            },
          ],
        };

    test('falls back to the plan instead of a dead end', () async {
      final snapshots = PlanItemSnapshots()..registerPlan(plan());
      final RecipeDetailDto recipe =
          await service(snapshots).getRecipe('rc_com_tam_chay');
      expect(recipe.name, 'Cơm tấm chay sườn đậu');
      expect(recipe.isSnapshot, isTrue);
      expect(recipe.isVegan, isTrue);
    });

    test('a mock id in neither place is still a 404', () async {
      await expectLater(
        service(PlanItemSnapshots()).getRecipe('rc_unknown'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  testWidgets('reporting twice says why inside the sheet', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        communityApiProvider.overrideWithValue(_RefusingCommunity(
            const ApiException(
                message: 'Bạn đã báo cáo bài viết này rồi.', statusCode: 409))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ReportPostSheet(
            post: Post(
              id: 'p',
              type: PostType.discussion,
              author: const AuthorSummary(id: 'u', name: 'A'),
              title: 'T',
              body: 'B',
              createdAt: DateTime(2026, 10, 31),
              coverSeed: 'c',
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text(ReportReason.values.first.label));
    await tester.pump();
    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.pump();
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ReportPostSheet),
        matching: find.text('Bạn đã báo cáo bài viết này rồi.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Gửi báo cáo'), findsOneWidget);
  });

  group('feed logo', () {
    Future<void> pump(WidgetTester tester, {required double width}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: const VeganLifeLogo(),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.store)),
            ],
          ),
        ),
      ));
    }

    testWidgets('fits a narrow phone at large text', (tester) async {
      await pump(tester, width: 274);
      expect(tester.takeException(), isNull);
      expect(find.text('VeganLife'), findsOneWidget);
    });

    testWidgets('keeps its size where there is room', (tester) async {
      await pump(tester, width: 411);
      expect(tester.takeException(), isNull);
      final box = tester.renderObject<RenderBox>(find.text('VeganLife'));
      expect(box.localToGlobal(Offset.zero).dx, closeTo(48, 1));
    });
  });

  testWidgets('an over-target macro fits a narrow cell at large text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 97,
            child: MacroProgressBar(
              label: 'Tinh bột',
              value: 248,
              target: 100,
              unit: 'g',
              color: Colors.green,
              estimated: true,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('Tinh bột'), findsOneWidget);
  });

  group('"Tự lên thực đơn" on a week that has meals (B29)', () {
    Future<void> openMenu(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(411, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'vl.access_token': 'mock.jwt',
        'vl.display_name': 'Minh Anh',
        'vl.user_id': 'u_me',
        'vl.role': 'User',
      });
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 10, 29, 9);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          plannerClockProvider.overrideWithValue(() => now),
          mealPlannerApiProvider.overrideWithValue(
              MockMealPlannerRepository(userId: 'u_me', clock: () => now)),
        ],
        child: const MaterialApp(home: Scaffold(body: MealPlannerScreen())),
      ));
      for (var t = 0; t < 3000; t += 250) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.tap(find.byTooltip('Tuỳ chọn thực đơn'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the real BE cannot empty it: not offered', (tester) async {
      BackendModules.debugOverride({BackendModule.planner});
      addTearDown(() => BackendModules.debugOverride(null));
      await openMenu(tester);
      expect(find.text('Tạo lại bằng AI'), findsOneWidget);
      expect(find.text('Tự lên thực đơn'), findsNothing);
    });

    testWidgets('mock mode keeps it', (tester) async {
      await openMenu(tester);
      expect(find.text('Tự lên thực đơn'), findsOneWidget);
    });
  });
}
