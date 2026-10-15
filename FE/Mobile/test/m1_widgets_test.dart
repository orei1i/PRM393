// test/m1_widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/chef/presentation/widgets/booking_sheet.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_studio_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_dashboard_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_wallet_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/consultation_session_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/service_form_screen.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
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

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> session = const {},
  Size size = const Size(411, 900),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
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

/// The chip label is laid out at its full size: one line when it fits on
/// the screen, otherwise wrapped onto lines that are all shown.
void _expectUnclipped(WidgetTester tester, String label,
    {double screenWidth = 411}) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(ChoiceChip), matching: find.text(label)));
  final natural = paragraph.getMaxIntrinsicWidth(double.infinity);
  if (natural < screenWidth - 80) {
    expect(paragraph.size.width, greaterThanOrEqualTo(natural - 0.01),
        reason: '"$label" is clipped');
  }
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.01),
      reason: '"$label" is clipped vertically');
  expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" is cut');
}

/// Unmounts the screen and lets the mock latency timers finish.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(() {
    MockCommerceDb.reset();
    MockProfileRepository.reset();
  });

  testWidgets('chef dashboard is closed to the User role', (tester) async {
    await _pump(tester, const ChefDashboardScreen(), session: _minhAnh);
    expect(find.text('Chỉ dành cho chuyên gia'), findsOneWidget);
    expect(find.text('Lịch hẹn & đơn hàng'), findsNothing);
  });

  testWidgets('chef dashboard shows Tâm\'s counts and next appointment',
      (tester) async {
    await _pump(tester, const ChefDashboardScreen(), session: _tam);
    await tester.pump(const Duration(seconds: 3)); // mock latency
    expect(find.text('Chỉ dành cho chuyên gia'), findsNothing);
    expect(find.text('Doanh thu tháng này'), findsOneWidget);
    expect(find.text('Tài liệu chờ duyệt'), findsOneWidget);
    // Hoàng Nam is waiting for confirmation; Thảo Vy starts in 10 minutes.
    expect(find.textContaining('Thảo Vy'), findsOneWidget);
    expect(find.text('Lịch hẹn & đơn hàng'), findsOneWidget);
    expect(find.text('Ví · 5.462.000đ'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('wallet: balance, bank account and ledger', (tester) async {
    await _pump(tester, const ChefWalletScreen(),
        session: _tam, size: const Size(411, 2400));
    // The ledger starts loading once the balance is on screen.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('5.462.000đ'), findsOneWidget);
    expect(find.text('Đang chờ'), findsWidgets);
    expect(find.text('Vietcombank •••• 6789'), findsOneWidget);
    expect(find.text('Yêu cầu rút tiền'), findsOneWidget);
    expect(find.text('Bị từ chối'), findsWidgets);
    expect(find.text('Thu nhập · Khoá meal prep chay 4 tuần'), findsWidgets);
    expect(find.text('Gộp 350.000đ · Phí 35.000đ · Thực nhận 315.000đ'),
        findsWidgets);
    final withdraw = find.ancestor(
        of: find.text('Rút tiền'),
        matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(withdraw).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  group('Tôi', () {
    Future<void> pumpProfile(WidgetTester tester, Map<String, Object> session,
        {double textScale = 1}) async {
      await _pump(tester, const ProfileScreen(),
          session: session, size: const Size(411, 2400), textScale: textScale);
      await tester.pump(const Duration(seconds: 3)); // mock latency
    }

    testWidgets('Tâm gets the Chuyên gia section and dashboard card',
        (tester) async {
      await pumpProfile(tester, _tam);
      expect(find.text(UserRole.chef.label), findsWidgets);
      expect(find.text('Bảng điều khiển chuyên gia'), findsOneWidget);
      expect(find.text('Bạn là chuyên gia đã xác minh'), findsOneWidget);
      expect(find.text('Mở bảng điều khiển ›'), findsOneWidget);
      expect(find.text('Đơn hàng của tôi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('Minh Anh does not, at 2x text either', (tester) async {
      await pumpProfile(tester, _minhAnh, textScale: 2);
      expect(find.text('Thành viên'), findsOneWidget);
      expect(find.text('Bảng điều khiển chuyên gia'), findsNothing);
      expect(find.text('Trở thành chuyên gia'), findsOneWidget);
      expect(find.text('Đơn hàng của tôi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('specialty chips show full labels at 2x text', (tester) async {
    await _pump(tester, const ChefDirectoryScreen(), textScale: 2);
    await tester.pump(const Duration(seconds: 2)); // mock latency
    for (final label in ['Tất cả', 'Ẩm thực chay Việt']) {
      _expectUnclipped(tester, label);
    }
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('booking day chips are not cut off at 2x text', (tester) async {
    final today = DateTime.now();
    final chef = Chef(
      id: 'u_chef_tam',
      name: 'Lê Quang Tâm',
      headline: '',
      specialties: const [],
      rating: 5,
      reviewCount: 1,
      yearsExperience: 1,
      city: '',
      startingPriceVnd: 350000,
      services: const [
        ChefService(
            id: 'svc',
            chefId: 'u_chef_tam',
            title: 'Tư vấn thực đơn gia đình 7 ngày',
            type: ServiceType.consult,
            price: 350000,
            durationMinutes: 60),
      ],
      availableSlots: [
        for (var d = 1; d <= 3; d++)
          DateTime(today.year, today.month, today.day + d, 9),
      ],
    );
    await _pump(tester, Scaffold(body: BookingSheet(chef: chef)),
        session: _minhAnh, textScale: 2);
    final first = chef.availableSlots.first;
    final weekday =
        const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][first.weekday - 1];
    _expectUnclipped(tester, weekday);
    expect(find.text('Tiếp tục thanh toán · 350.000đ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The sheet also loads the member's bookings (to grey out clashes).
    await _dispose(tester);
  });

  testWidgets('service form: inline errors, content link for courses',
      (tester) async {
    await _pump(tester, const ServiceFormScreen(), session: _tam);
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Tên dịch vụ từ 8 đến 120 ký tự.'), findsOneWidget);
    expect(find.text('Giá từ 50.000đ đến 50.000.000đ.'), findsOneWidget);
    expect(find.text('Đường dẫn nội dung'), findsNothing);

    await tester.tap(find.text('Khoá học'));
    await tester.pumpAndSettle();
    expect(find.text('Đường dẫn nội dung'), findsOneWidget);
    expect(find.text('Thời lượng (phút)'), findsNothing);
  });

  testWidgets('session: "Hoàn thành" waits for 20 characters of notes',
      (tester) async {
    final studio = MockChefStudioRepository(
      currentUserId: () => 'u_chef_tam',
      currentUserName: () => 'Lê Quang Tâm',
      currentRole: () => UserRole.chef,
    );
    await tester.runAsync(() => studio.startConsultation('cs_tam_vy'));
    await _pump(
        tester, const ConsultationSessionScreen(consultationId: 'cs_tam_vy'),
        session: _tam);
    await tester.pump(const Duration(seconds: 2)); // mock latency
    expect(find.text('Đang tư vấn'), findsWidgets);

    FilledButton complete() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Hoàn thành buổi tư vấn'));
    expect(complete().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Ngắn quá');
    await tester.pump();
    expect(complete().onPressed, isNull);
    await tester.enterText(
        find.byType(TextField), 'Thêm đậu gà vào bữa chiều mỗi ngày.');
    await tester.pump();
    expect(complete().onPressed, isNotNull);
  });
}
