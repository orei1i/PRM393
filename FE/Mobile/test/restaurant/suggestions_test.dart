// test/restaurant/suggestions_test.dart
// "Gợi ý quán mới": a suggestion waits for an admin and stays private; "Quán tôi
// đã gợi ý" follows it; the single location control of the form. And the search
// box of "Quán chay gần bạn".
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/network/api_endpoints.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/core/widgets/vl_card.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/restaurant/data/models/restaurant_model.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/location_picker_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/my_restaurant_suggestions_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/submit_restaurant_screen.dart';

const _q1 = MockLocationService.point;

const _request = CreateRestaurantRequestDto(
    name: 'Cơm chay Hoa Sen', address: '9 Lý Tự Trọng, P. Bến Nghé, Q.1');

MockRestaurantRepository _repo({String me = 'u_me', bool signedIn = true}) =>
    MockRestaurantRepository(
      isSignedIn: () => signedIn,
      currentUserId: () => me,
      currentUserName: () => 'Minh Anh',
    );

Matcher _apiError(int status) => throwsA(
    isA<ApiException>().having((e) => e.statusCode, 'statusCode', status));

Future<void> _pump(WidgetTester tester, Widget home,
    {bool signedIn = true,
    Size size = const Size(411, 900),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...{
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Minh Anh',
      'vl.user_id': 'u_me',
      'vl.role': 'User',
    },
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    ),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(MockRestaurantRepository.reset);
  tearDown(() => BackendModules.debugOverride(null));

  group('status flow (mock)', () {
    test('a suggestion is Pending and private to its author', () async {
      final repo = _repo();
      final created = await repo.createRestaurant(_request);
      expect(created.status, RestaurantSuggestionStatus.pending);
      expect(created.submittedAt, isNotNull);

      expect((await repo.listRestaurants(near: _q1)).map((r) => r.id),
          isNot(contains(created.id)));
      expect((await repo.listRestaurants(query: 'hoa sen')).map((r) => r.id),
          isNot(contains(created.id)));
      expect((await repo.suggestedForFood('hoa sen')).map((r) => r.id),
          isNot(contains(created.id)));

      // The author can read it, nobody else.
      expect((await repo.getRestaurant(created.id)).name, 'Cơm chay Hoa Sen');
      await expectLater(
          _repo(me: 'u_thao_vy').getRestaurant(created.id), _apiError(404));
      await expectLater(
          _repo(signedIn: false).getRestaurant(created.id), _apiError(404));
      await expectLater(
          _repo(me: 'u_thao_vy').getReviews(created.id), _apiError(404));

      await expectLater(
          repo.upsertReview(created.id,
              rating: 5, comment: 'Quán rất ngon nhé'),
          _apiError(409));
    });

    test('approved goes public, as a normal restaurant', () async {
      final repo = _repo();
      final created = await repo.createRestaurant(_request);
      final decided = await repo.demoDecide(created.id, approve: true);
      expect(decided.status, RestaurantSuggestionStatus.approved);
      expect(decided.reviewedAt, isNotNull);
      expect(decided.isVeganCertified, isFalse, reason: 'certified separately');

      final other = _repo(me: 'u_thao_vy');
      expect((await other.listRestaurants(query: 'hoa sen')).map((r) => r.id),
          contains(created.id));
      expect((await other.getRestaurant(created.id)).id, created.id);
      await repo.upsertReview(created.id,
          rating: 5, comment: 'Quán rất ngon nhé');
    });

    test('rejected stays private, with the reason; it can be sent again',
        () async {
      final repo = _repo();
      final created = await repo.createRestaurant(_request);
      final decided = await repo.demoDecide(created.id, approve: false);
      expect(decided.status, RestaurantSuggestionStatus.rejected);
      expect(decided.rejectionReason,
          MockRestaurantRepository.demoRejectionReason);
      expect((await repo.listRestaurants(query: 'hoa sen')).map((r) => r.id),
          isNot(contains(created.id)));

      final again = await repo.createRestaurant(_request);
      expect(again.status, RestaurantSuggestionStatus.pending);
      await expectLater(repo.createRestaurant(_request), _apiError(409),
          reason: 'one already waits');
    });

    test('"my suggestions": mine only, newest first, members only', () async {
      final repo = _repo();
      final first = await repo.createRestaurant(_request);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await repo.createRestaurant(
          const CreateRestaurantRequestDto(
              name: 'Bếp chay Góc Phố',
              address: '20 Pasteur, P. Bến Nghé, Q.1'));

      final mine = await repo.getMySuggestions();
      expect(mine.take(2).map((s) => s.id), [second.id, first.id]);
      expect(mine.map((s) => s.id), contains('rs_u_rejected_demo'));

      final other = await _repo(me: 'u_thao_vy').getMySuggestions();
      expect(other.map((s) => s.id), isNot(contains(first.id)));
      await expectLater(
          _repo(signedIn: false).getMySuggestions(), _apiError(401));
    });

    test('the wire: status fields; unknown means already public', () {
      final dto = RestaurantSuggestionDto.fromJson({
        'id': 'r1',
        'name': 'Quán',
        'address': 'Địa chỉ',
        'status': 'rejected',
        'rejectionReason': 'Trùng quán',
        'createdAt': '2026-10-01T00:00:00Z',
        'reviewedAt': '2026-10-02T00:00:00Z',
      }).toSuggestion();
      expect(dto.isRejected, isTrue);
      expect(dto.rejectionReason, 'Trùng quán');
      expect(dto.submittedAt, isNotNull);
      expect(dto.reviewedAt, isNotNull);
      expect(RestaurantSuggestionStatus.fromApi(null),
          RestaurantSuggestionStatus.approved);
      expect(ApiEndpoints.myRestaurantSuggestions,
          '/users/me/restaurant-suggestions');
    });
  });

  group('"Quán tôi đã gợi ý"', () {
    testWidgets('reachable from the restaurants screen; shows the refusal',
        (tester) async {
      await _pump(tester, const RestaurantNearbyScreen());
      await _wait(tester);
      await tester.tap(find.byTooltip('Quán tôi đã gợi ý'));
      await _wait(tester, 1200);
      expect(find.byType(MyRestaurantSuggestionsScreen), findsOneWidget);
      expect(find.text('Cơm Chay Góc Phố Cũ'), findsOneWidget);
      expect(find.text('Bị từ chối'), findsOneWidget);
      expect(find.textContaining('Lý do: Không xác minh được địa chỉ'),
          findsOneWidget);
      expect(find.text('Duyệt thử'), findsNothing,
          reason: 'only what still waits');
      await _dispose(tester);
    });

    testWidgets('a guest is asked to sign in', (tester) async {
      await _pump(tester, const RestaurantNearbyScreen(), signedIn: false);
      await _wait(tester);
      await tester.tap(find.byTooltip('Quán tôi đã gợi ý'));
      await _wait(tester, 800);
      expect(find.byType(MyRestaurantSuggestionsScreen), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets(
        'the whole flow: submit → waits, not in the list → "Duyệt thử" → '
        'public and opens', (tester) async {
      await _pump(tester, const RestaurantNearbyScreen(),
          size: const Size(411, 1600));
      await _wait(tester);
      await tester.tap(find.text('Gợi ý quán mới'));
      await _wait(tester, 500);
      expect(find.byType(SubmitRestaurantScreen), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên quán'), 'Cơm chay Hoa Sen');
      await tester.enterText(find.widgetWithText(TextFormField, 'Địa chỉ'),
          '9 Lý Tự Trọng, P. Bến Nghé, Q.1');
      await tester.tap(find.text('Gửi gợi ý'));
      await _wait(tester, 2500);

      expect(find.byType(MyRestaurantSuggestionsScreen), findsOneWidget);
      expect(find.text('Chờ duyệt'), findsOneWidget);
      expect(
          find.text(
              'Đang chờ Ban quản trị duyệt. Quán sẽ hiển thị công khai sau khi được duyệt.'),
          findsOneWidget);

      // Waiting: no page to open yet, and nothing in the public list.
      await tester.tap(find.text('Cơm chay Hoa Sen'));
      await _wait(tester, 500);
      expect(find.byType(RestaurantDetailScreen), findsNothing);
      await tester.pageBack();
      await _wait(tester, 1000);
      await tester.enterText(find.byType(TextField), 'hoa sen');
      await _wait(tester, 2500);
      expect(find.text('Cơm chay Hoa Sen'), findsNothing);

      await tester.tap(find.byTooltip('Quán tôi đã gợi ý'));
      await _wait(tester, 1200);
      await tester.tap(find.text('Duyệt thử'));
      await _wait(tester, 2500);
      final card = find.ancestor(
          of: find.text('Cơm chay Hoa Sen'), matching: find.byType(VLCard));
      expect(find.descendant(of: card, matching: find.text('Đã duyệt')),
          findsOneWidget);
      expect(
          find.descendant(
              of: card,
              matching:
                  find.text('Đã hiển thị công khai với nhãn Chưa chứng nhận.')),
          findsOneWidget);
      expect(find.text('Duyệt thử'), findsNothing);

      await tester.tap(find.text('Cơm chay Hoa Sen'));
      await _wait(tester, 1200);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      await tester.pageBack();
      await _wait(tester, 800);
      await tester.pageBack();
      await _wait(tester, 2500);
      expect(find.text('Cơm chay Hoa Sen'), findsOneWidget,
          reason: 'public list, still searching "hoa sen"');
      await _wait(tester, 5000); // snackbars
      await _dispose(tester);
    });

    testWidgets('"Từ chối thử" shows the reason', (tester) async {
      await tester.runAsync(() => _repo().createRestaurant(_request));
      await _pump(tester, const MyRestaurantSuggestionsScreen());
      await _wait(tester, 800);
      await tester.tap(find.text('Từ chối thử'));
      await _wait(tester, 2500);
      expect(
          find.text('Lý do: ${MockRestaurantRepository.demoRejectionReason}'),
          findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a hybrid build says it is sample data', (tester) async {
      BackendModules.debugOverride({BackendModule.community});
      await _pump(tester, const MyRestaurantSuggestionsScreen());
      await _wait(tester, 800);
      expect(find.byType(DemoDataBanner), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('no overflow at 360 dp with font scale 1.3', (tester) async {
      await tester.runAsync(() => _repo().createRestaurant(_request));
      await _pump(tester, const MyRestaurantSuggestionsScreen(),
          size: const Size(360, 640), textScale: 1.3);
      await _wait(tester, 800);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  group('no overflow at 360 dp with font scale 1.3', () {
    testWidgets('the picker, search and map', (tester) async {
      await _pump(tester, const LocationPickerScreen(),
          size: const Size(360, 640), textScale: 1.3);
      await _wait(tester, 300);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tìm trên bản đồ'));
      await _wait(tester, 800);
      expect(tester.takeException(), isNull);
      expect(find.text('Dùng vị trí này'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('the form with a place', (tester) async {
      await _pump(tester, const SubmitRestaurantScreen(),
          size: const Size(360, 640), textScale: 1.3);
      await tester.pump();
      await tester.tap(find.text('Chọn vị trí quán'));
      await _wait(tester, 500);
      await tester.tap(find.text('Dùng vị trí hiện tại (mô phỏng)'));
      await _wait(tester, 1000);
      expect(tester.takeException(), isNull);
      expect(find.text('Đổi'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('the location control of the form', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('Chọn vị trí quán'));
      await _wait(tester, 500);
      expect(find.byType(LocationPickerScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Vị trí quán'), findsOneWidget);
    }

    testWidgets('one control; search in the picker fills the place',
        (tester) async {
      await _pump(tester, const SubmitRestaurantScreen(),
          size: const Size(411, 1400));
      expect(find.text('Chọn trên bản đồ'), findsNothing);
      expect(find.text('Tìm địa chỉ'), findsNothing);
      expect(find.text('Dùng vị trí hiện tại'), findsNothing);
      expect(find.text('Đổi'), findsNothing);

      await openPicker(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Tìm địa chỉ, phường, quận…'),
          'ben thanh');
      await _wait(tester, 1000);
      await tester.tap(find.text('Chợ Bến Thành'));
      await _wait(tester, 800);

      expect(find.byType(LocationPickerScreen), findsNothing);
      expect(find.textContaining('Chợ Bến Thành ·'), findsOneWidget);
      expect(find.text('Đổi'), findsOneWidget);
      expect(find.text('Bỏ vị trí'), findsOneWidget);
      expect(find.text('Chọn vị trí quán'), findsNothing);
      await _dispose(tester);
    });

    testWidgets(
        '"Đổi" opens the picker again; "Bỏ vị trí" clears what it filled',
        (tester) async {
      await _pump(tester, const SubmitRestaurantScreen(),
          size: const Size(411, 1400));
      await openPicker(tester);
      await tester.tap(find.text('Dùng vị trí hiện tại (mô phỏng)'));
      await _wait(tester, 800);
      expect(find.textContaining('(vị trí mô phỏng)'), findsOneWidget);
      expect(find.text('7 Công trường Lam Sơn, P. Bến Nghé, Q.1, TP.HCM'),
          findsOneWidget);

      await tester.tap(find.text('Đổi'));
      await _wait(tester, 500);
      expect(find.byType(LocationPickerScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng').last);
      await _wait(tester, 1500);
      expect(find.textContaining('(vị trí mô phỏng)'), findsOneWidget,
          reason: 'closing changes nothing');

      await tester.tap(find.text('Bỏ vị trí'));
      await tester.pump();
      expect(find.text('Chọn vị trí quán'), findsOneWidget);
      expect(find.text('7 Công trường Lam Sơn, P. Bến Nghé, Q.1, TP.HCM'),
          findsNothing);
      await _dispose(tester);
    });

    testWidgets('"Bỏ vị trí" keeps an address the user typed', (tester) async {
      await _pump(tester, const SubmitRestaurantScreen(),
          size: const Size(411, 1400));
      await openPicker(tester);
      await tester.tap(find.text('Dùng vị trí hiện tại (mô phỏng)'));
      await _wait(tester, 800);
      await tester.enterText(find.widgetWithText(TextFormField, 'Địa chỉ'),
          '9 Lý Tự Trọng, P. Bến Nghé, Q.1');
      await tester.tap(find.text('Bỏ vị trí'));
      await tester.pump();
      expect(find.text('9 Lý Tự Trọng, P. Bến Nghé, Q.1'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('the sent suggestion has the coordinates', (tester) async {
      await _pump(tester, const SubmitRestaurantScreen(),
          size: const Size(411, 1400));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên quán'), 'Chay Có Toạ Độ');
      await openPicker(tester);
      await tester.tap(find.text('Dùng vị trí hiện tại (mô phỏng)'));
      await _wait(tester, 800);
      await tester.tap(find.text('Gửi gợi ý'));
      await _wait(tester, 2000);
      final mine = (await tester.runAsync(() => _repo().getMySuggestions()))!;
      final sent = mine.firstWhere((s) => s.name == 'Chay Có Toạ Độ');
      expect(sent.latitude, _q1.latitude);
      expect(sent.longitude, _q1.longitude);
      await _wait(tester, 5000); // snackbar
      await _dispose(tester);
    });
  });

  group('search box of "Quán chay gần bạn"', () {
    Future<List<String>> names(String q) async =>
        (await _repo().listRestaurants(query: q)).map((r) => r.name).toList();

    test('by name, with and without accents, in part', () async {
      for (final q in ['An Lạc', 'an lac', 'AN LẠC', 'an la']) {
        expect(await names(q), contains('Quán Chay An Lạc'), reason: q);
      }
    });

    test('by address, the way it is typed', () async {
      for (final q in [
        'Nguyễn Thị Minh Khai',
        'nguyen thi minh khai',
        'da kao',
        'Q.1',
        'quận 1',
        'quan 1',
        'phường đa kao',
      ]) {
        expect(await names(q), contains('Quán Chay An Lạc'), reason: q);
      }
      final q5 = await names('quan 5');
      expect(q5, contains('Lẩu Nấm Chay Mộc Nhiên'));
      expect(q5, isNot(contains('Quán Chay An Lạc')));
    });

    test('by a dish in the name or the reviews, with and without accents',
        () async {
      for (final q in ['bún riêu', 'bun rieu', 'BUN RIEU']) {
        final hits = await names(q);
        expect(hits, contains('Bún Riêu Chay Hạnh Tâm'), reason: q);
        expect(hits, contains('Quán Chay An Lạc'), reason: 'a review says so');
      }
    });

    test('nothing, and empty', () async {
      expect(await names('xyzxyz'), isEmpty);
      expect((await names('')).length, greaterThan(3));
      expect((await names('   ')).length, greaterThan(3));
    });

    testWidgets('filters while typing; empty and no-result states; ✕',
        (tester) async {
      await _pump(tester, const RestaurantNearbyScreen(),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bun rieu');
      await _wait(tester, 2500);
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsWidgets);
      expect(find.text('Chay Thanh Tịnh'), findsNothing);
      expect(find.textContaining('14 quán'), findsNothing);

      await tester.enterText(find.byType(TextField), 'xyzxyz');
      await _wait(tester, 2500);
      expect(find.text('Chưa có quán nào khớp'), findsOneWidget);
      expect(find.textContaining('Thử từ khoá khác'), findsOneWidget);

      await tester.tap(find.byTooltip('Xoá'));
      await _wait(tester, 2500);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a sponsored place that does not match stays out',
        (tester) async {
      await _pump(tester, const RestaurantNearbyScreen(),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(find.text('Được tài trợ'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'moc nhien');
      await _wait(tester, 2500);
      expect(find.text('Lẩu Nấm Chay Mộc Nhiên'), findsOneWidget);
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsNothing);
      await _dispose(tester);
    });
  });
}
