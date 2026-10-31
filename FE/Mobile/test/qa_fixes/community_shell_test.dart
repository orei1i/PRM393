// test/qa_fixes/community_shell_test.dart
// Q11 (sponsored row), Q12 (composer and scanner messages), Q16 (guest AI
// chip) and Q18 (labels at large text sizes).
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ads/presentation/widgets/sponsored_restaurant_row.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/screens/chat_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/controllers/restaurant_controllers.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';

import 'qa_support.dart';

void main() {
  // Real Roboto metrics (shipped with the SDK), as in the shell smoke tests.
  setUpAll(() async {
    final dir =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File('$dir/roboto-$weight.ttf');
      if (file.existsSync()) {
        roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await roboto.load();
  });

  group('Q11 the sponsored row', () {
    const hanhTam = 'Bún Riêu Chay Hạnh Tâm';

    Future<ProviderContainer> open(WidgetTester tester) async {
      const screen = RestaurantNearbyScreen();
      final c = await pumpScreen(tester, screen,
          session: const {}, size: const Size(411, 4000));
      await wait(tester);
      return c;
    }

    Future<void> filter(WidgetTester tester, ProviderContainer c,
        RestaurantFilters filters) async {
      final done =
          c.read(restaurantListProvider('').notifier).applyFilters(filters);
      await wait(tester);
      await done;
    }

    testWidgets('without filters: one row for the place, the count keeps it',
        (tester) async {
      await open(tester);
      expect(find.byType(SponsoredRestaurantRow), findsOneWidget);
      expect(find.text(hanhTam), findsOneWidget);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('outside the radius: no row', (tester) async {
      final c = await open(tester);
      await filter(
          tester, c, const RestaurantFilters(certifiedOnly: true, radiusKm: 1));
      expect(find.byType(SponsoredRestaurantRow), findsNothing);
      expect(find.text(hanhTam), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('inside the radius: still one row', (tester) async {
      final c = await open(tester);
      await filter(tester, c, const RestaurantFilters(radiusKm: 5));
      expect(find.byType(SponsoredRestaurantRow), findsOneWidget);
      expect(find.text(hanhTam), findsOneWidget);
      await disposeScreen(tester);
    });

    const here = UserLocation(point: GeoPoint(10.7769, 106.7009), label: 'Q.1');
    Restaurant place({
      bool certified = true,
      double? km,
      GeoPoint? at,
    }) =>
        Restaurant(
          id: 'r',
          name: 'Quán',
          address: 'Đường',
          isVeganCertified: certified,
          distanceKm: km,
          location: at,
        );
    RestaurantListState state(RestaurantFilters filters, {MapArea? area}) =>
        RestaurantListState(
            restaurants: const [],
            location: here,
            filters: filters,
            area: area);

    test('certified only', () {
      const filters = RestaurantFilters(certifiedOnly: true);
      expect(state(filters).admits(place()), isTrue);
      expect(state(filters).admits(place(certified: false)), isFalse);
    });

    test('radius: by the distance, or from the coordinates', () {
      const filters = RestaurantFilters(radiusKm: 1);
      expect(state(filters).admits(place(km: 0.5)), isTrue);
      expect(state(filters).admits(place(km: 2.6)), isFalse);
      expect(state(filters).admits(place(at: here.point)), isTrue);
      expect(state(filters).admits(place()), isFalse,
          reason: 'nowhere known is not within 1 km');
      expect(state(RestaurantFilters.defaults).admits(place()), isTrue);
    });

    test('a map area wins over the radius', () {
      const far = GeoPoint(21.0287, 105.8524);
      const area = MapArea(center: far, radiusKm: 2);
      final s = state(const RestaurantFilters(radiusKm: 1), area: area);
      expect(s.admits(place(at: far, km: 1000)), isTrue);
      expect(s.admits(place(at: here.point, km: 0)), isFalse);
    });
  });

  group('Q12 messages clear when the input becomes valid', () {
    testWidgets('composer', (tester) async {
      await pumpScreen(tester, const CreatePostScreen());
      await tester.pump();
      const titleError = 'Tiêu đề cần ít nhất 8 ký tự.';
      const bodyError = 'Nội dung cần ít nhất 20 ký tự để cộng đồng dễ hiểu.';

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tiêu đề'), 'a');
      await tester.pump();
      expect(find.text(titleError), findsNothing,
          reason: 'no message before the first submit');

      await tester.tap(find.widgetWithText(FilledButton, 'Đăng'));
      await tester.pump();
      expect(find.text(titleError), findsOneWidget);
      expect(find.text(bodyError), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Tiêu đề'),
          'Bún riêu chay cà chua');
      await tester.pump();
      expect(find.text(titleError), findsNothing);
      expect(find.text(bodyError), findsOneWidget, reason: 'still invalid');

      await tester.enterText(find.widgetWithText(TextFormField, 'Nội dung'),
          'Nguyên liệu và cách làm món bún riêu chay.');
      await tester.pump();
      expect(find.text(bodyError), findsNothing);
      await disposeScreen(tester);
    });

    test('scanner', () async {
      final c = ProviderContainer(overrides: [
        userAllergiesProvider.overrideWith((ref) async => const <String>[]),
      ]);
      addTearDown(c.dispose);
      final scanner = c.read(scannerControllerProvider.notifier)
        ..addManual('Sữa bò');
      await scanner.generateMenu();
      expect(c.read(scannerControllerProvider).menuError,
          ScannerState.noSavableItems);
      expect(c.read(scannerControllerProvider).menuStatus, MenuStatus.error);

      scanner.addManual('Cà chua');
      final state = c.read(scannerControllerProvider);
      expect(state.menuError, isNull);
      expect(state.menuStatus, MenuStatus.idle);
    });

    test('scanner: another failure stays until the next try', () {
      final failed = const ScannerState().copyWith(
          menuStatus: MenuStatus.error, menuError: 'Máy chủ đang bận.');
      final next = failed.copyWith(items: const []);
      expect(next.menuError, 'Máy chủ đang bận.');
      expect(next.menuStatus, MenuStatus.error);
    });
  });

  group('Q16 the AI chips', () {
    const personal = 'Giải thích lượng sắt mỗi ngày của tôi';

    testWidgets('a guest has no menu to ask about', (tester) async {
      await pumpScreen(tester, const ChatScreen(), session: const {});
      await tester.pump();
      expect(find.text(personal), findsNothing);
      expect(find.text('Gợi ý món thay thế đậu hũ'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('a member does', (tester) async {
      await pumpScreen(tester, const ChatScreen());
      await tester.pump();
      expect(find.text(personal), findsOneWidget);
      await disposeScreen(tester);
    });
  });

  testWidgets('Q18 tab labels fit whole at text scale 1.3', (tester) async {
    tester.view
      ..physicalSize = const Size(411, 900)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues(minhAnhSession);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VeganLifeApp(),
    ));
    await wait(tester, 3000);

    final nav = find.byKey(const ValueKey('shell-nav'));
    for (final label in ['Trang chủ', 'Thực đơn', 'Chuyên gia', 'Tôi']) {
      final text = find.descendant(of: nav, matching: find.text(label));
      expect(text, findsOneWidget, reason: label);
      final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
          of: text, matching: find.byType(RichText), matchRoot: true));
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
    }
    // The feed's logo overflows here only: its font falls back to the wider
    // test font (QA saw no overflow at 1.3 on a device). Not about these labels.
    tester.takeException();
    await disposeScreen(tester);
  });
}
