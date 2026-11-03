// test/resilience/screen_faults_test.dart
// The main screens on the real modules with a bad server behind them: whatever
// comes back, no exception, no error box, no endless spinner and no technical
// text. Faults are in fault_support.dart; a healthy run proves each screen shows
// data here, so the faulted runs test something.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/build_error_fallback.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/body_metrics_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_recipes_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/scanner/data/scan_image_source.dart';
import 'package:veganlife_mobile/features/scanner/domain/scan_mode.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

import 'fault_support.dart';

const _id = '6ae595c796695f5c139fa99b';

/// A post as a feed row would open it.
final _post = PostDto.fromJson({
  'id': '6ae5a8876c01fc07a925777c',
  'type': 'recipe',
  'author': {'id': 'u1', 'fullName': 'Ai đó'},
  'title': 'Bún riêu chay',
  'body': 'Nội dung bài viết.',
  'createdAt': '2026-10-31T07:19:11.908Z',
  'status': 'Published',
  'mediaType': 'Text',
  'likeCount': 3,
}).toEntity();

class _Gallery implements ScanImageSource {
  @override
  Future<Uint8List?> pickFromGallery() async => Uint8List(16);
}

class _Screen {
  const _Screen(this.name, this.build,
      {this.healthy, this.after, this.modules});

  final String name;
  final Widget Function() build;

  /// What only a healthy server shows.
  final String? healthy;

  /// Instead of every module the BE supports.
  final Set<BackendModule> Function()? modules;

  /// Steps once the screen is up, such as picking a photo.
  final Future<void> Function(WidgetTester tester)? after;
}

final _screens = [
  _Screen('Trang chủ', () => const FeedScreen(),
      healthy: 'Bài thử phân trang số 9'),
  _Screen('post detail', () => PostDetailScreen(post: _post),
      healthy: 'Bún riêu chay'),
  _Screen('Thực đơn', () => const MealPlannerScreen(), healthy: 'kcal'),
  _Screen('recipe detail',
      () => const RecipeDetailScreen(recipeId: _id, name: 'Cơm gạo lứt'),
      healthy: 'Cơm gạo lứt đậu hũ kho'),
  _Screen('tủ lạnh', () => const PantryScreen(), healthy: 'Đậu phộng'),
  _Screen('quét', () => const IngredientScannerScreen(mode: ScanMode.gallery),
      after: (tester) async {
    final pick = find.text('Chọn ảnh');
    if (pick.evaluate().isNotEmpty) {
      await tester.tap(pick.first, warnIfMissed: false);
    }
  }, healthy: 'Bông cải xanh'),
  _Screen('theo dõi cân nặng', () => const BodyMetricsScreen(),
      healthy: 'Mục tiêu'),
  _Screen('Tôi', () => const ProfileScreen(), healthy: 'FE M1'),
  _Screen('tìm kiếm', () => const SearchScreen(initialQuery: 'đậu hũ'),
      healthy: 'Đậu hũ'),
  _Screen('tìm kiếm trên máy (BACKEND_MOCK_MODULES=search)',
      () => const SearchScreen(initialQuery: 'dau hu'),
      healthy: 'Đậu hũ',
      modules: () => {...BackendModules.supportedByBackend}
        ..remove(BackendModule.search)),
  _Screen('hồ sơ sức khoẻ', () => const HealthProfileEditScreen(),
      healthy: 'BMI 22,3'),
  _Screen('công thức của tôi', () => const MyRecipesScreen(),
      healthy: 'Cơm gạo lứt đậu hũ'),
  _Screen('nguyên liệu',
      () => const IngredientDetailScreen(ingredientId: _id, name: 'Đậu hũ'),
      healthy: '76 kcal'),
];

final _technical = RegExp(
    r'Exception|TypeError|subtype|Null check|<html|<!DOCTYPE|Bad Gateway|'
    r'DioE|Internal Server|Instance of|\bnull\b|\bNaN\b|Infinity|Ã|á»|Ä‘');

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  Future<void> run(WidgetTester tester, _Screen screen, Fault? fault) async {
    final modules = screen.modules;
    if (modules != null) BackendModules.debugOverride(modules());
    tester.view
      ..physicalSize = const Size(411, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      SessionController.accessTokenKey: 'test-token',
      'vl.user_id': '6ae5962396695f5c139fa9b0',
      'vl.display_name': 'FE Test',
      'vl.role': 'User',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      scanImageSourceProvider.overrideWithValue(_Gallery()),
    ]);
    addTearDown(container.dispose);
    container.read(dioProvider).httpClientAdapter = FaultBackend(fault);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey, home: screen.build()),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await screen.after?.call(tester);
    // The mock modules wait like a network, and retries take their time too.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    final shown = [
      for (final e in find.byType(RichText).evaluate())
        (e.widget as RichText).text.toPlainText(),
    ];
    final leaked = shown.where(_technical.hasMatch).toList();
    expect(leaked, isEmpty, reason: 'technical text on the screen');
    if (fault == null && screen.healthy != null) {
      expect(shown.where((t) => t.contains(screen.healthy!)), isNotEmpty,
          reason: 'on a healthy server this screen shows its data: $shown');
    }
    if (fault != null) {
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'still spinning after 17 s');
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  for (final screen in _screens) {
    group(screen.name, () {
      testWidgets('healthy server', (tester) async {
        await run(tester, screen, null);
      });
      for (final fault in Fault.values) {
        testWidgets(fault.name, (tester) async {
          await run(tester, screen, fault);
        });
      }
    });
  }

  testWidgets('a build error shows the fallback, not an error box',
      (tester) async {
    final before = ErrorWidget.builder;
    ErrorWidget.builder = buildErrorFallback;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (_) => throw StateError('boom'))),
    ));
    expect(tester.takeException(), isStateError);
    final fallback = find.textContaining('Không hiển thị được phần này');
    final shown = fallback.evaluate().length;
    await tester.pumpWidget(const SizedBox());
    ErrorWidget.builder = before;
    expect(shown, 1);
  });
}
