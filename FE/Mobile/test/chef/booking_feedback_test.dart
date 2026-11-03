// test/chef/booking_feedback_test.dart
// The tester's feedback on the booking flow, on real widgets and the mock
// server: the number stepper, for whom, the share card, the estimate bar, the
// buttons above the chat, the way to payment, the money stages and the member's
// wallet. Every new screen also fails and retries without a crash.
@Timeout(Duration(seconds: 240))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/features/booking/data/booking_api_service.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_rules.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_views.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/book_chef_plan_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/chef_booking_inbox_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/plan_editor_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/widgets/booking_chat_tab.dart';
import 'package:veganlife_mobile/features/booking/presentation/widgets/booking_sheets.dart';
import 'package:veganlife_mobile/features/booking/presentation/widgets/number_stepper_field.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/commerce/data/commerce_api_service.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/data/models/order_model.dart';
import 'package:veganlife_mobile/features/commerce/presentation/controllers/commerce_controllers.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/member_wallet_screen.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

const _tam = {
  'vl.access_token': 'mock.jwt.tam',
  'vl.display_name': 'Lê Quang Tâm',
  'vl.user_id': 'u_chef_tam',
  'vl.role': 'Chef',
};

/// A new account: no health profile.
const _newMember = {
  'vl.access_token': 'mock.jwt.new',
  'vl.display_name': 'Bạn Mới',
  'vl.user_id': 'u_feedback_new',
  'vl.role': 'User',
};

const _chef = Chef(
  id: 'u_chef_tam',
  userId: 'u_chef_tam',
  name: 'Lê Quang Tâm',
  headline: 'Bếp trưởng nhà hàng chay',
  specialties: ['Ẩm thực chay Việt'],
  rating: 4.9,
  reviewCount: 212,
  yearsExperience: 15,
  city: 'TP. Hồ Chí Minh',
  pricePerDay: 150000,
  feedbackPricePerDay: 180000,
);

const _offline = ApiException(message: 'Mất kết nối.', statusCode: 503);

/// Keeps what the form sends, then lets the mock answer.
class _CapturingBookings extends MockBookingRepository {
  _CapturingBookings()
      : super(
          currentUserId: () => 'u_me',
          currentUserName: () => 'Minh Anh',
          currentRole: () => UserRole.user,
        );

  CreateBookingRequestDto? sent;

  @override
  Future<BookingDto> createBooking(CreateBookingRequestDto request) {
    sent = request;
    return super.createBooking(request);
  }
}

/// The member's answer to an offer doesn't get through.
class _FailingAccept extends MockBookingRepository {
  _FailingAccept()
      : super(
          currentUserId: () => 'u_me',
          currentUserName: () => 'Minh Anh',
          currentRole: () => UserRole.user,
        );

  @override
  Future<BookingDto> respondToOffer(String id, String offerId,
          {required bool accept}) async =>
      throw _offline;
}

class _FailingWalletPay extends MockCommerceRepository {
  _FailingWalletPay() : super(currentUserId: () => 'u_me');

  @override
  Future<OrderDto> payWithWallet(String orderId) async => throw _offline;
}

class _FailingHealth extends MockMealPlannerRepository {
  _FailingHealth() : super(userId: 'u_me');

  @override
  Future<HealthProfileDto?> getHealthProfile() async => throw _offline;
}

MockBookingRepository _repo(String id, UserRole role) => MockBookingRepository(
      currentUserId: () => id,
      currentUserName: () => id == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
      currentRole: () => role,
    );

final _member = _repo('u_me', UserRole.user);
final _chefRepo = _repo('u_chef_tam', UserRole.chef);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> session = _minhAnh,
  Size size = const Size(411, 1400),
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
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

Future<void> _wait(WidgetTester tester, [int seconds = 3]) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Finder _bookingDays() => find.byKey(const ValueKey('booking-days'));

String _text(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

void main() {
  setUp(() {
    MockCommerceDb.reset();
    MockProfileRepository.reset();
    MockMealPlannerRepository.reset();
  });

  tearDown(() => BackendModules.debugOverride(null));

  group('NumberStepperField', () {
    Future<List<int>> pumpStepper(WidgetTester tester,
        {int value = 7,
        int min = 3,
        int max = 30,
        List<bool>? validity,
        double textScale = 1}) async {
      final changes = <int>[];
      var current = value;
      await _pump(
          tester,
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  NumberStepperField(
                    fieldKey: const ValueKey('n'),
                    value: current,
                    min: min,
                    max: max,
                    unit: 'ngày',
                    onChanged: (v) => setState(() {
                      current = v;
                      changes.add(v);
                    }),
                    onValidityChanged: validity?.add,
                  ),
                  const TextField(key: ValueKey('other')),
                ],
              ),
            ),
          ),
          textScale: textScale);
      return changes;
    }

    final n = find.byKey(const ValueKey('n'));

    testWidgets('− / + and typing, within the limits', (tester) async {
      final changes = await pumpStepper(tester);
      await tester.tap(find.byTooltip('Thêm 1 ngày'));
      await tester.pump();
      expect(_text(tester, n), '8');
      await tester.tap(find.byTooltip('Bớt 1 ngày'));
      await tester.pump();
      await tester.enterText(n, '12');
      await tester.pump();
      expect(changes, [8, 7, 12]);
    });

    testWidgets('buttons stop at the limits', (tester) async {
      await pumpStepper(tester, value: 3, max: 4);
      expect(
          tester
              .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.remove_rounded))
              .onPressed,
          isNull);
      await tester.tap(find.byTooltip('Thêm 1 ngày'));
      await tester.pump();
      expect(
          tester
              .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.add_rounded))
              .onPressed,
          isNull);
    });

    testWidgets('out of range or empty: a message, no number, clamps on blur',
        (tester) async {
      final validity = <bool>[];
      final changes = await pumpStepper(tester, validity: validity);
      const message = 'Số ngày từ 3 đến 30.';

      await tester.tap(n);
      await tester.enterText(n, '31');
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      expect(validity.last, isFalse);
      expect(changes, isEmpty, reason: 'never a number outside the limits');

      await tester.tap(find.byKey(const ValueKey('other')));
      await tester.pump();
      expect(_text(tester, n), '30');
      expect(find.text(message), findsNothing);
      expect(validity.last, isTrue);
      expect(changes, [30]);

      await tester.tap(n);
      await tester.enterText(n, '');
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('other')));
      await tester.pump();
      expect(_text(tester, n), '30', reason: 'empty: back to the last number');

      await tester.tap(n);
      await tester.enterText(n, '1');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_text(tester, n), '3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('huge numbers and inverted limits never crash', (tester) async {
      await pumpStepper(tester, value: 40, min: 10, max: 5);
      expect(tester.takeException(), isNull);
      expect(
          tester
              .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.add_rounded))
              .onPressed,
          isNull);
      await tester.enterText(n, '99999999999');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_text(tester, n).length, lessThanOrEqualTo(4));
      expect(NumberStepperField.clampTo(40, 10, 5), 10);
    });

    testWidgets('360 dp at font scale 1.3 fits', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      await pumpStepper(tester, textScale: 1.3);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('booking form', () {
    Future<_CapturingBookings> pumpForm(
      WidgetTester tester, {
      Size size = const Size(411, 2600),
      double textScale = 1,
      ThemeMode themeMode = ThemeMode.light,
      Map<String, Object> session = _minhAnh,
    }) async {
      final api = _CapturingBookings();
      await _pump(tester, const BookChefPlanScreen(chef: _chef),
          size: size,
          textScale: textScale,
          themeMode: themeMode,
          session: session,
          overrides: [bookingApiProvider.overrideWithValue(api)]);
      await _wait(tester, 2);
      return api;
    }

    Future<void> send(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Gửi yêu cầu'));
      await _wait(tester, 2);
    }

    Future<void> needs(WidgetTester tester) => tester.enterText(
        find.widgetWithText(TextField, 'Nhu cầu & ghi chú'),
        'Mình cần thực đơn chay tăng cơ, bữa sáng nhanh dưới 15 phút.');

    testWidgets('no day chips anywhere: the stepper instead', (tester) async {
      await pumpForm(tester);
      expect(find.text('Số ngày'), findsOneWidget);
      expect(_text(tester, _bookingDays()), '7');
      for (final chip in [
        '3 ngày',
        '7 ngày',
        '10 ngày',
        '14 ngày',
        '30 ngày'
      ]) {
        expect(find.widgetWithText(ChoiceChip, chip), findsNothing,
            reason: chip);
      }
      await _dispose(tester);
    });

    testWidgets('invalid days: a message, submit blocked, no estimate',
        (tester) async {
      final api = await pumpForm(tester);
      await needs(tester);
      await tester.enterText(_bookingDays(), '50');
      await tester.pump();
      expect(find.text('Số ngày từ 3 đến 30.'), findsOneWidget);
      expect(find.text('Chờ báo giá'), findsOneWidget);
      await send(tester);
      expect(api.sent, isNull);
      expect(find.byType(BookChefPlanScreen), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('the chef\'s own limits apply', (tester) async {
      await _pump(
          tester,
          const BookChefPlanScreen(
              chef: Chef(
            id: 'c',
            name: 'Chef',
            headline: 'H',
            specialties: [],
            rating: 4,
            reviewCount: 0,
            yearsExperience: 1,
            city: '',
            pricePerDay: 100000,
            feedbackPricePerDay: 100000,
            minPlanDays: 10,
            maxPlanDays: 14,
          )));
      await _wait(tester, 2);
      expect(_text(tester, _bookingDays()), '10');
      await tester.enterText(_bookingDays(), '15');
      await tester.pump();
      expect(find.text('Số ngày từ 10 đến 14.'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('Cho tôi: the card lists what the request sends',
        (tester) async {
      final api = await pumpForm(tester);
      expect(find.text('Chuyên gia sẽ thấy'), findsOneWidget);
      for (final row in [
        'Chiều cao',
        'Cân nặng',
        'BMI',
        'Mục tiêu',
        'Dị ứng',
        'Nhu cầu năng lượng',
      ]) {
        expect(find.text(row), findsWidgets, reason: row);
      }
      expect(find.text('172 cm'), findsOneWidget);
      expect(find.text('66 kg'), findsOneWidget);
      await needs(tester);
      await send(tester);
      final sent = api.sent!;
      expect(sent.audience, BookingAudience.self);
      expect(sent.toJson()['shareHealthProfile'], isTrue);
      expect(sent.toJson()['goal'], 'lean_muscle');
      expect(sent.toJson()['allergies'], ['peanut']);
      final shown = MemberHealthDto.fromJson(sent.healthSnapshot!);
      expect(shown.heightCm, 172);
      expect(shown.weightKg, 66);
      await _dispose(tester);
    });

    testWidgets('Cho tôi with the switch off: only allergies go',
        (tester) async {
      final api = await pumpForm(tester);
      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Chia sẻ hồ sơ sức khoẻ với chuyên gia'));
      await tester.pump();
      expect(find.text('Chiều cao'), findsNothing);
      expect(find.text('Mục tiêu'), findsNothing);
      expect(find.text('Dị ứng'), findsWidgets);
      expect(find.textContaining('Đang tắt'), findsOneWidget);
      await needs(tester);
      await send(tester);
      final json = api.sent!.toJson();
      expect(json['shareHealthProfile'], isFalse);
      expect(json.containsKey('goal'), isFalse);
      expect(json['allergies'], ['peanut']);
      expect(api.sent!.healthSnapshot, isNull);
      await _dispose(tester);
    });

    testWidgets(
        'Cho gia đình: no goal, BMI or personal needs; people, allergies and '
        'meals stay; no misleading switch', (tester) async {
      final api = await pumpForm(tester);
      await tester.tap(find.text('Cho gia đình'));
      await tester.pump();
      expect(find.text('Nhu cầu của gia đình'), findsOneWidget);
      expect(find.text('Mục tiêu'), findsNothing);
      expect(find.text('BMI'), findsNothing);
      expect(find.text('Chiều cao'), findsNothing);
      expect(find.text('Nhu cầu năng lượng'), findsNothing);
      expect(find.widgetWithText(TextField, 'Nhu cầu & ghi chú'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Số người'), findsOneWidget);
      expect(find.text('Gia đình · 4 người'), findsOneWidget);
      expect(find.text('Dị ứng'), findsWidgets);
      expect(find.text('Các bữa trong ngày'), findsOneWidget);
      expect(find.text('Đậu phộng'), findsWidgets);

      // People: the same stepper; the card follows.
      final people = find.byKey(const ValueKey('booking-people'));
      await tester.enterText(people, '6');
      await tester.pump();
      expect(find.text('Gia đình · 6 người'), findsOneWidget);
      await tester.enterText(people, '50');
      await tester.pump();
      expect(find.text('Số người từ 2 đến 20.'), findsOneWidget);
      await send(tester);
      expect(api.sent, isNull, reason: 'blocked while invalid');
      await tester.enterText(people, '6');
      await tester.pump();

      await send(tester);
      final json = api.sent!.toJson();
      expect(json['audience'], 'Family');
      expect(json['familySize'], 6);
      expect(json.containsKey('goal'), isFalse);
      expect(json['shareHealthProfile'], isFalse);
      expect(json['needs'], isEmpty);
      expect(json['allergies'], ['peanut']);
      expect(json['mealPattern'], isNotEmpty);
      expect(api.sent!.healthSnapshot, isNull);
      await _dispose(tester);
    });

    testWidgets('a new account shares nothing and says so', (tester) async {
      final api = await pumpForm(tester, session: _newMember);
      expect(find.textContaining('Bạn chưa có hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Chiều cao'), findsNothing);
      await needs(tester);
      await send(tester);
      expect(api.sent!.toJson()['shareHealthProfile'], isFalse);
      await _dispose(tester);
    });

    testWidgets(
        'estimate: live, with a breakdown; family says it isn\'t per '
        'person', (tester) async {
      await pumpForm(tester);
      expect(find.text('Giá ước tính'), findsOneWidget);
      expect(find.text('1.260.000đ'), findsOneWidget);
      await tester.tap(find.byTooltip('Thêm 1 ngày').first);
      await tester.pump();
      expect(find.text('1.440.000đ'), findsOneWidget);
      await tester.tap(find.text('Giao trọn kế hoạch một lần'));
      await tester.pump();
      expect(find.text('1.200.000đ'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('estimate-open')));
      await tester.pumpAndSettle();
      expect(find.text('8 ngày'), findsOneWidget);
      expect(find.text('150.000đ/ngày'), findsWidgets);
      expect(find.text('8 × 150.000đ = 1.200.000đ'), findsOneWidget);
      expect(find.textContaining('thoả thuận trong chat'), findsOneWidget);
      expect(find.textContaining('không nhân theo số người'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cho gia đình'));
      await tester.pump();
      expect(find.text('1.200.000đ'), findsOneWidget,
          reason: 'the rates do not depend on people');
      await tester.tap(find.byKey(const ValueKey('estimate-open')));
      await tester.pumpAndSettle();
      expect(find.text('Gia đình · 4 người'), findsWidgets);
      expect(find.textContaining('không nhân theo số người'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a chef with no listed price: no invented figure',
        (tester) async {
      await _pump(
          tester,
          const BookChefPlanScreen(
              chef: Chef(
            id: 'c',
            name: 'Chef',
            headline: 'H',
            specialties: [],
            rating: 4,
            reviewCount: 0,
            yearsExperience: 1,
            city: '',
            pricePerDay: 0,
            feedbackPricePerDay: 0,
          )));
      await _wait(tester, 2);
      expect(find.text('Chờ báo giá'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('360 dp, font scale 1.3, dark, keyboard up: no overflow',
        (tester) async {
      await pumpForm(tester,
          size: const Size(360, 640),
          textScale: 1.3,
          themeMode: ThemeMode.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('1.260.000đ'), findsOneWidget);

      // A real keyboard: the bar stays above it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Gửi yêu cầu'), findsOneWidget);
      expect(tester.getBottomLeft(find.text('Gửi yêu cầu')).dy,
          lessThan(640 - 300));

      await tester.tap(find.text('Gửi yêu cầu'));
      await _wait(tester, 1);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('a health profile that fails to load: retry, nothing shared',
        (tester) async {
      final api = _CapturingBookings();
      await _pump(tester, const BookChefPlanScreen(chef: _chef),
          size: const Size(411, 2600),
          overrides: [
            bookingApiProvider.overrideWithValue(api),
            mealPlannerApiProvider.overrideWithValue(_FailingHealth()),
          ]);
      await _wait(tester, 1);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Chưa tải được hồ sơ'), findsOneWidget);
      expect(find.text('Chiều cao'), findsNothing);
      await needs(tester);
      await send(tester);
      expect(api.sent!.toJson()['shareHealthProfile'], isFalse);
      await _dispose(tester);
    });
  });

  group('offer sheet', () {
    testWidgets('the same stepper, no chips; invalid days block sending',
        (tester) async {
      OfferRequestDto? result;
      await _pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showPriceOfferSheet(
                  context,
                  initial: OfferRequestDto(
                    price: 1000000,
                    planDays: 5,
                    bookingType: BookingType.oneShot,
                    startDate: addDays(vnDateOf(DateTime.now()), 3),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final days = find.byKey(const ValueKey('offer-days'));
      expect(find.widgetWithText(ChoiceChip, '7 ngày'), findsNothing);
      expect(_text(tester, days), '5');
      await tester.enterText(days, '99');
      await tester.pump();
      await tester.ensureVisible(find.text('Gửi đề xuất'));
      await tester.tap(find.text('Gửi đề xuất'));
      await tester.pump();
      expect(find.text('Số ngày từ 3 đến 30.'), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(days, '9');
      await tester.pump();
      await tester.ensureVisible(find.text('Gửi đề xuất'));
      await tester.tap(find.text('Gửi đề xuất'));
      await tester.pumpAndSettle();
      expect(result!.planDays, 9);
    });

    testWidgets('a stored offer outside the limits is clamped, not a crash',
        (tester) async {
      await _pump(
          tester,
          Scaffold(
            body: PriceOfferSheet(
              initial: OfferRequestDto(
                price: 1000000,
                planDays: 99,
                bookingType: BookingType.oneShot,
                startDate: addDays(vnDateOf(DateTime.now()), 3),
              ),
            ),
          ),
          size: const Size(411, 1000));
      expect(tester.takeException(), isNull);
      expect(_text(tester, find.byKey(const ValueKey('offer-days'))), '30');
    });
  });

  group('buttons above the chat', () {
    Finder inHeader(String text) => find.descendant(
        of: find.byWidgetPredicate((w) =>
            w.runtimeType.toString() == '_Header' ||
            w.key == const ValueKey('booking-actions')),
        matching: find.text(text));

    testWidgets('member: only "Huỷ yêu cầu" above; the answers are on the card',
        (tester) async {
      await _pump(
          tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'));
      await _wait(tester);
      expect(inHeader('Huỷ yêu cầu'), findsOneWidget);
      expect(inHeader('Đồng ý 1.500.000đ'), findsNothing);
      expect(inHeader('Đề xuất giá khác'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(OfferCard),
              matching: find.widgetWithText(FilledButton, 'Đồng ý')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(OfferCard),
              matching: find.text('Đề xuất giá khác')),
          findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('after scrolling away the offer stays answerable',
        (tester) async {
      // Enough chat after the offer to push its card out of view.
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await _member.sendMessage(
              'b_ma_tam_nego',
              SendMessageRequestDto(
                  body: 'Tin nhắn thứ $i để đẩy thẻ lên trên.'));
        }
      });
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'),
          size: const Size(411, 800));
      await _wait(tester);
      await tester.pump();
      expect(find.byType(OfferCard), findsNothing, reason: 'scrolled away');
      expect(find.textContaining('đang chờ bạn trả lời'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Đồng ý'), findsOneWidget);

      // Back up to the card: the bar leaves, one set of buttons.
      await tester.dragUntilVisible(
        find.byType(OfferCard),
        find.byWidgetPredicate((w) => w is ListView),
        const Offset(0, 200),
      );
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.byType(OfferCard));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('đang chờ bạn trả lời'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('the pinned bar accepts too', (tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await _member.sendMessage(
              'b_ma_tam_nego',
              SendMessageRequestDto(
                  body: 'Tin nhắn thứ $i để đẩy thẻ lên trên.'));
        }
      });
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'),
          size: const Size(411, 800));
      await _wait(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đồng ý'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Đồng ý 1.500.000đ?'), findsOneWidget);
      await tester.tap(find.text('Xem lại'));
      await tester.pump(const Duration(seconds: 1));
      await _dispose(tester);
    });

    testWidgets('chef: "Không đồng ý" closes the deal, honestly for both',
        (tester) async {
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_nam_tam_req'),
          session: _tam);
      await _wait(tester);
      expect(find.text('Báo giá'), findsOneWidget, reason: 'in the chat');
      expect(inHeader('Báo giá'), findsNothing);
      await tester.tap(inHeader('Không đồng ý'));
      await tester.pumpAndSettle();
      expect(find.textContaining('không bị trừ tiền'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Lý do'), 'Bận');
      await tester.tap(find.widgetWithText(FilledButton, 'Không đồng ý'));
      await tester.pump();
      expect(find.textContaining('ít nhất 10 ký tự'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Lý do'),
          'Lịch của mình đã kín trong 2 tuần tới.');
      await tester.tap(find.widgetWithText(FilledButton, 'Không đồng ý'));
      await _wait(tester, 3);
      expect(find.textContaining('Thành viên không bị trừ tiền'), findsWidgets);
      expect(inHeader('Không đồng ý'), findsNothing);
      final b =
          (await tester.runAsync(() => _chefRepo.getBooking('b_nam_tam_req')))!;
      expect(b.status, BookingStatus.declined);
      await _dispose(tester);
    });

    testWidgets('member after the chef said no: an honest result, no dead end',
        (tester) async {
      await tester.runAsync(() => _chefRepo.decline(
          'b_ma_tam_nego', 'Lịch của mình đã kín trong 2 tuần tới.'));
      await _pump(
          tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'));
      await _wait(tester);
      expect(find.textContaining('Bạn không bị trừ tiền'), findsWidgets);
      expect(find.textContaining('có thể đặt chuyên gia khác'), findsOneWidget);
      expect(find.text('Huỷ yêu cầu'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('chef can make an offer from the chat, on a member counter too',
        (tester) async {
      final start = addDays(vnDateOf(DateTime.now()), 5);
      await tester.runAsync(() async {
        await _member.sendOffer(
            'b_ma_tam_nego',
            OfferRequestDto(
                price: 1200000,
                planDays: 10,
                bookingType: BookingType.dailyFeedback,
                startDate: start));
      });
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'),
          session: _tam);
      await _wait(tester);
      expect(inHeader('Đồng ý 1.200.000đ'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(OfferCard),
              matching: find.widgetWithText(FilledButton, 'Đồng ý')),
          findsOneWidget);
      await tester.tap(find.byTooltip('Đề xuất giá'));
      await tester.pumpAndSettle();
      expect(find.text('Đề xuất giá khác'), findsWidgets);
      expect(find.byKey(const ValueKey('offer-price')), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('way to payment', () {
    testWidgets('chef accepts a counter-offer: stays, member gets the button',
        (tester) async {
      final start = addDays(vnDateOf(DateTime.now()), 5);
      await tester.runAsync(() => _member.sendOffer(
          'b_ma_tam_nego',
          OfferRequestDto(
              price: 1200000,
              planDays: 10,
              bookingType: BookingType.dailyFeedback,
              startDate: start)));
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'),
          session: _tam);
      await _wait(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đồng ý'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Đồng ý')));
      await _wait(tester, 3);
      expect(find.byType(PaymentScreen), findsNothing,
          reason: 'the chef does not pay');
      expect(find.textContaining('Chờ thành viên thanh toán'), findsWidgets);
      await _dispose(tester);

      await _pump(
          tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'));
      await _wait(tester);
      expect(find.text('Thanh toán 1.200.000đ'), findsOneWidget);
      expect(
          find.textContaining('Hai bên đã đồng ý 1.200.000đ'), findsOneWidget);
      await tester.tap(find.text('Thanh toán 1.200.000đ'));
      await _wait(tester, 3);
      expect(find.byType(PaymentScreen), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets(
        'member accepts: straight to payment, Back to one booking page, paying '
        'later still works', (tester) async {
      await _pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(BookingDetailScreen.route('b_ma_tam_nego')),
                child: const Text('open'),
              ),
            ),
          ));
      await tester.tap(find.text('open'));
      await _wait(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đồng ý'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Đồng ý')));
      await _wait(tester, 4); // accept, the order, its QR, the order again
      expect(find.byType(PaymentScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pump();
      await tester.tap(find.text('Rời đi'));
      await _wait(tester, 2);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(find.byType(PaymentScreen, skipOffstage: false), findsNothing);

      // Back again: the page under it, no second booking page.
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('open'), findsOneWidget);
      expect(
          find.byType(BookingDetailScreen, skipOffstage: false), findsNothing);
      await _dispose(tester);
    });

    testWidgets('accepting fails: a message, still on the booking',
        (tester) async {
      final api = _FailingAccept();
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'),
          overrides: [bookingApiProvider.overrideWithValue(api)]);
      await _wait(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Đồng ý'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Đồng ý')));
      await _wait(tester, 1);
      expect(tester.takeException(), isNull);
      expect(find.byType(PaymentScreen), findsNothing);
      expect(find.text('Mất kết nối.'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('money stages in the contract tab', () {
    testWidgets('chef: "Xác nhận hoàn thành" starts the hold, both see it',
        (tester) async {
      await _pump(
          tester,
          const BookingDetailScreen(
              bookingId: 'b_chau_tam_ready', initialTab: 2),
          session: _tam,
          size: const Size(411, 2400));
      await _wait(tester);
      // A family request: people and allergies, no personal profile.
      expect(find.text('Gia đình · 3 người'), findsOneWidget);
      expect(find.textContaining('Gia đình · 3 người · Dị ứng: Đậu phộng'),
          findsOneWidget);
      expect(find.text('Mục tiêu'), findsNothing);
      expect(find.text('Hồ sơ sức khoẻ'), findsNothing);
      expect(find.text('750.000đ'), findsWidgets);
      expect(find.text('VeganLife đang giữ'), findsOneWidget);
      expect(find.text('Chưa có ngày'), findsOneWidget);
      expect(find.text('Giữ 7 ngày để khiếu nại'), findsOneWidget);

      await tester.tap(find.text('Xác nhận hoàn thành'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Xác nhận hoàn thành?'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining('675.000đ')),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
      await _wait(tester, 3);
      expect(find.text('Xác nhận hoàn thành'), findsNothing);
      expect(find.textContaining('Đã hoàn thành'), findsWidgets);
      expect(find.textContaining('Đến '), findsWidgets);
      final b = (await tester
          .runAsync(() => _chefRepo.getBooking('b_chau_tam_ready')))!;
      expect(b.status, BookingStatus.ended);
      expect(b.escrow!.releaseAt, isNotNull);
      await _dispose(tester);
    });

    testWidgets('chef: all sent but before the last day: says when, no button',
        (tester) async {
      final start = addDays(vnDateOf(DateTime.now()), 2);
      final id = (await tester.runAsync(() async {
        final created = await _member.createBooking(CreateBookingRequestDto(
          chefId: 'u_chef_tam',
          bookingType: BookingType.oneShot,
          planDays: 3,
          startDate: start,
          goal: 'maintain',
          allergies: const [],
          mealPattern: MealPattern.standard,
          needs: 'Mình cần thực đơn chay đủ chất, bữa sáng dưới 15 phút.',
        ));
        final quoted = await _chefRepo.sendOffer(
            created.id,
            OfferRequestDto(
                price: 450000,
                planDays: 3,
                bookingType: BookingType.oneShot,
                startDate: start));
        await _member.respondToOffer(created.id, quoted.currentOffer!.id,
            accept: true);
        final order = await _member.startPayment(created.id);
        final commerce = MockCommerceDb.instance;
        commerce.markPaid(commerce.payment(order.payment!.id));
        for (var day = 1; day <= 3; day++) {
          await _chefRepo.savePlanDay(
              created.id,
              day,
              PlanDayRequestDto(meals: [
                for (final slot in MealPattern.standard)
                  PlanMealDto(
                      slot: slot,
                      recipe: PlanRecipeDto(name: 'Món ${slot.label}')),
              ]));
        }
        await _chefRepo.sendWholePlan(created.id);
        return created.id;
      }))!;
      await _pump(tester, BookingDetailScreen(bookingId: id), session: _tam);
      await _wait(tester);
      expect(find.text('Xác nhận hoàn thành'), findsNothing);
      expect(find.textContaining('Xác nhận hoàn thành được từ ngày kết thúc'),
          findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('chef: days missing means "Soạn kế hoạch", no confirm yet',
        (tester) async {
      await _pump(
          tester, const BookingDetailScreen(bookingId: 'b_vy_tam_active'),
          session: _tam);
      await _wait(tester);
      expect(find.text('Xác nhận hoàn thành'), findsNothing);
      expect(find.text('Soạn kế hoạch'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('member: in the hold with a date and "Khiếu nại"',
        (tester) async {
      await _pump(tester,
          const BookingDetailScreen(bookingId: 'b_ma_tam_hold', initialTab: 2),
          size: const Size(411, 2000));
      await _wait(tester);
      expect(find.text('Khiếu nại'), findsOneWidget);
      expect(find.textContaining('Hợp đồng đã hoàn thành'), findsOneWidget);
      expect(find.text('Chuyên gia xác nhận hoàn thành'), findsOneWidget);
      expect(find.text('VeganLife đang giữ'), findsOneWidget);
      await _dispose(tester);
    });

    for (final (who, session) in [('member', _minhAnh), ('chef', _tam)]) {
      testWidgets('$who: an auto-completed contract says the system did it',
          (tester) async {
        await _pump(
            tester,
            const BookingDetailScreen(
                bookingId: 'b_ma_tam_auto', initialTab: 2),
            session: session,
            size: const Size(411, 2400));
        await _wait(tester);
        expect(find.text(autoCompletedNote), findsOneWidget);
        expect(
            find.textContaining('$autoCompletedNote. VeganLife giữ tiền đến'),
            findsOneWidget);
        expect(find.text('Chuyên gia xác nhận hoàn thành'), findsNothing);
        expect(find.text('Xác nhận hoàn thành'), findsNothing);
        expect(find.text('Chưa có ngày'), findsNothing);
        await _dispose(tester);
      });
    }

    testWidgets('member: days missing long after the end ask for a complaint',
        (tester) async {
      await _pump(tester,
          const BookingDetailScreen(bookingId: 'b_ma_tam_short', initialTab: 2),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(find.textContaining('bạn hãy gửi khiếu nại'), findsOneWidget);
      expect(find.text('Khiếu nại'), findsOneWidget);
      expect(
          find.textContaining('chưa đủ nên không tự hoàn tất'), findsOneWidget);
      expect(find.text('Chưa có ngày'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('chef: the same booking is flagged "Cần bạn xử lý"',
        (tester) async {
      await _pump(tester, const ChefBookingInboxScreen(),
          session: _tam, size: const Size(411, 2400));
      await _wait(tester);
      await tester.ensureVisible(find.textContaining('Đang thực hiện').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Đang thực hiện').first);
      await _wait(tester);
      expect(find.text('Cần bạn xử lý'), findsWidgets);
      final b = (await tester
          .runAsync(() => _chefRepo.getBooking('b_ma_tam_short')))!;
      expect(chefNeedsAction(b, DateTime.now()), isTrue);
      await _dispose(tester);
    });

    testWidgets('member: a refund reads as going to the wallet',
        (tester) async {
      await _pump(
          tester,
          const BookingDetailScreen(
              bookingId: 'b_ma_thuha_refund', initialTab: 2),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(find.textContaining('vào ví'), findsWidgets);
      expect(find.textContaining('phương thức thanh toán'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('a hold without a release date never crashes the old screens',
        (tester) async {
      await _pump(
          tester,
          const BookingDetailScreen(
              bookingId: 'b_ma_thuha_active', initialTab: 2),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Chưa có ngày'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('member can cancel a paid booking before any day is delivered',
        (tester) async {
      final start = addDays(vnDateOf(DateTime.now()), 4);
      final id = (await tester.runAsync(() async {
        final created = await _member.createBooking(CreateBookingRequestDto(
          chefId: 'u_chef_tam',
          bookingType: BookingType.oneShot,
          planDays: 3,
          startDate: start,
          goal: 'maintain',
          allergies: const [],
          mealPattern: MealPattern.standard,
          needs: 'Mình cần thực đơn chay đủ chất, bữa sáng dưới 15 phút.',
        ));
        final quoted = await _chefRepo.sendOffer(
            created.id,
            OfferRequestDto(
                price: 450000,
                planDays: 3,
                bookingType: BookingType.oneShot,
                startDate: start));
        await _member.respondToOffer(created.id, quoted.currentOffer!.id,
            accept: true);
        final order = await _member.startPayment(created.id);
        final commerce = MockCommerceDb.instance;
        commerce.markPaid(commerce.payment(order.payment!.id));
        return created.id;
      }))!;
      await _pump(tester, BookingDetailScreen(bookingId: id));
      await _wait(tester);
      await tester.tap(find.text('Huỷ yêu cầu'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.textContaining('được hoàn vào Ví của tôi'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Lý do'), 'Mình đổi lịch rồi ạ');
      await tester.tap(find.widgetWithText(FilledButton, 'Huỷ yêu cầu'));
      await _wait(tester, 2);
      expect(find.textContaining('đã vào Ví của tôi'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('chef views of a family request', () {
    testWidgets('inbox card', (tester) async {
      await _pump(tester, const ChefBookingInboxScreen(), session: _tam);
      await _wait(tester);
      await tester.ensureVisible(find.text('Đang thực hiện'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Đang thực hiện'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Bảo Châu'), findsOneWidget);
      expect(
          find.text('Gia đình · 3 người · Dị ứng: Đậu phộng'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('plan editor', (tester) async {
      await _pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const PlanEditorScreen(
                            bookingId: 'b_chau_tam_ready'))),
                child: const Text('open'),
              ),
            ),
          ),
          session: _tam);
      await tester.tap(find.text('open'));
      await _wait(tester);
      expect(
          find.text('Gia đình · 3 người · Dị ứng: Đậu phộng'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a personal request still shows the shared profile',
        (tester) async {
      await _pump(tester,
          const BookingDetailScreen(bookingId: 'b_nam_tam_req', initialTab: 2),
          session: _tam);
      await _wait(tester);
      expect(find.text('Cho tôi'), findsOneWidget);
      expect(find.text('Hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.text('Mục tiêu'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('payment screen: the wallet', () {
    Future<String> accepted(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final nego = await _member.getBooking('b_ma_tam_nego');
          await _member.respondToOffer(nego.id, nego.currentOffer!.id,
              accept: true);
          return _member.startPayment(nego.id);
        }))!
            .id;

    Future<void> pumpPayment(WidgetTester tester, String orderId,
            {List<Override> overrides = const []}) =>
        _pump(
            tester,
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(PaymentScreen.route(orderId)),
                  child: const Text('open'),
                ),
              ),
            ),
            overrides: overrides);

    testWidgets('the balance covers it: paid in one tap after a confirmation',
        (tester) async {
      final orderId = await accepted(tester);
      await pumpPayment(tester, orderId);
      await tester.tap(find.text('open'));
      await _wait(tester, 2);
      expect(find.text('Số dư ví 1.600.000đ'), findsOneWidget);
      await tester.tap(find.text('Thanh toán bằng ví'));
      await _wait(tester, 1); // the QR's spinner never settles
      expect(find.text('Thanh toán 1.500.000đ bằng ví?'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining('100.000đ')),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await _wait(tester, 3);
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      expect(MockCommerceDb.instance.availableOf('u_me'), 100000);
      await _dispose(tester);
    });

    testWidgets('below the price: says so, the QR is untouched',
        (tester) async {
      final orderId = await accepted(tester);
      MockCommerceDb.instance.walletEntries
          .removeWhere((e) => e.userId == 'u_me');
      await pumpPayment(tester, orderId);
      await tester.tap(find.text('open'));
      await _wait(tester, 2);
      expect(find.text('Thanh toán bằng ví'), findsNothing);
      expect(
          find.textContaining('chưa đủ để thanh toán bằng ví'), findsOneWidget);
      expect(find.text('Đang chờ thanh toán…'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a wallet that fails to load never blocks the QR; retry',
        (tester) async {
      final orderId = await accepted(tester);
      var fail = true;
      await pumpPayment(tester, orderId, overrides: [
        memberWalletProvider.overrideWith((ref) async {
          if (fail) throw _offline;
          return const WalletDto(available: 2000000, pending: 0, withdrawn: 0);
        }),
      ]);
      await tester.tap(find.text('open'));
      await _wait(tester, 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Chưa đọc được số dư ví.'), findsOneWidget);
      expect(find.text('Đang chờ thanh toán…'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Thử lại'));
      await _wait(tester, 1);
      expect(find.text('Thanh toán bằng ví'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('paying fails: a message, the screen stays', (tester) async {
      final orderId = await accepted(tester);
      await pumpPayment(tester, orderId, overrides: [
        commerceApiProvider.overrideWithValue(_FailingWalletPay()),
      ]);
      await tester.tap(find.text('open'));
      await _wait(tester, 2);
      await tester.tap(find.text('Thanh toán bằng ví'));
      await _wait(tester, 1); // the QR's spinner never settles
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await _wait(tester, 1);
      expect(tester.takeException(), isNull);
      expect(find.text('Mất kết nối.'), findsOneWidget);
      expect(find.text('Đang chờ thanh toán…'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('modules on different sides: no wallet offer', (tester) async {
      final orderId = await accepted(tester);
      BackendModules.debugOverride({BackendModule.chefWallet});
      await pumpPayment(tester, orderId);
      await tester.tap(find.text('open'));
      await _wait(tester, 2);
      expect(find.textContaining('ví'), findsNothing);
      await _dispose(tester);
    });
  });

  group('Ví của tôi (member)', () {
    testWidgets('Tôi has the entry; a chef keeps their one wallet',
        (tester) async {
      await _pump(tester, const ProfileScreen(), size: const Size(411, 2600));
      await _wait(tester);
      expect(find.text('Ví của tôi'), findsOneWidget);
      expect(find.text('Ví thành viên'), findsNothing);
      await tester.tap(find.text('Ví của tôi'));
      await _wait(tester);
      expect(find.byType(MemberWalletScreen), findsOneWidget);
      await _dispose(tester);

      await _pump(tester, const ProfileScreen(),
          session: _tam, size: const Size(411, 2600));
      await _wait(tester);
      expect(find.text('Ví của tôi'), findsOneWidget, reason: 'earnings');
      expect(find.text('Ví thành viên'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('balance, history, withdrawing and the mock approval',
        (tester) async {
      await _pump(tester, const MemberWalletScreen(),
          size: const Size(411, 1800));
      await _wait(tester);
      expect(find.text('1.600.000đ'), findsOneWidget);
      expect(find.text('MB Bank •••• 6789'), findsOneWidget);
      expect(
          find.text(
              'Hoàn tiền · Thực đơn 15 ngày · Giao trọn kế hoạch một lần'),
          findsOneWidget);
      expect(find.text('+1.800.000đ'), findsOneWidget);
      expect(find.text('−200.000đ'), findsOneWidget);
      expect(find.text('Mô phỏng duyệt'), findsNothing,
          reason: 'nothing is waiting yet');

      await tester.tap(find.text('Rút tiền'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Số dư ví'), findsOneWidget,
          reason: 'the shared screen');
      await tester.enterText(find.byType(TextFormField), '500000');
      await tester.pump();
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
      await _wait(tester, 3);
      expect(find.text('1.100.000đ'), findsOneWidget);
      expect(find.text('Chờ duyệt'), findsWidgets);
      expect(find.text('Đang chờ duyệt rút 500.000đ'), findsOneWidget);

      await tester.tap(find.text('Mô phỏng duyệt'));
      await _wait(tester, 3);
      expect(find.text('Mô phỏng duyệt'), findsNothing);
      expect(find.text('Đang chờ duyệt rút 500.000đ'), findsNothing);
      expect(find.text('Đã rút 700.000đ'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('no bank account: the form first, no chef gate',
        (tester) async {
      MockCommerceDb.instance.bankAccounts.remove('u_me');
      await _pump(tester, const MemberWalletScreen(),
          size: const Size(411, 1400));
      await _wait(tester);
      expect(find.text('Chưa có tài khoản nhận tiền'), findsOneWidget);
      await tester.tap(find.text('Rút tiền'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Tài khoản nhận tiền'), findsOneWidget);
      expect(find.text('Chỉ dành cho chuyên gia'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('empty: zero, no withdrawal, a clear history', (tester) async {
      MockCommerceDb.scenario = 'empty';
      await _pump(tester, const MemberWalletScreen());
      await _wait(tester);
      expect(find.text('0đ'), findsOneWidget);
      expect(find.text('Chưa có giao dịch nào.'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: find.text('Rút tiền'),
                  matching: find.byWidgetPredicate((w) => w is FilledButton)))
              .onPressed,
          isNull);
      await _dispose(tester);
    });

    testWidgets('a failed load retries, on the balance and on the history',
        (tester) async {
      MockCommerceDb.scenario = 'error';
      await _pump(tester, const MemberWalletScreen());
      await _wait(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Thử lại'), findsOneWidget);
      MockCommerceDb.scenario = 'normal';
      await tester.tap(find.text('Thử lại'));
      await _wait(tester);
      expect(find.text('1.600.000đ'), findsOneWidget);
      await _dispose(tester);

      await _pump(tester, const MemberWalletScreen(), overrides: [
        memberWalletTransactionsProvider
            .overrideWith((ref) async => throw _offline),
      ]);
      await _wait(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('1.600.000đ'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('360 dp, font scale 1.3, dark: no overflow', (tester) async {
      await _pump(tester, const MemberWalletScreen(),
          size: const Size(360, 640),
          textScale: 1.3,
          themeMode: ThemeMode.dark);
      await _wait(tester);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('the sample-data banner in a hybrid build', (tester) async {
      BackendModules.debugOverride({BackendModule.auth});
      await _pump(tester, const MemberWalletScreen());
      await _wait(tester);
      expect(find.text(DemoDataBanner.label), findsOneWidget);
      await _dispose(tester);
    });
  });
}
