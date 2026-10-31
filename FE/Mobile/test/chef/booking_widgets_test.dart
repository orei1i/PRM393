// test/chef/booking_widgets_test.dart
// Screens of the chef booking flow, Tôi › Chuyên gia and the payment
// screen, on the mock server (real clock; the mocks wait like a network).
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/widgets/sign_in_sheet.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/book_chef_plan_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_history_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/chef_booking_inbox_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/complaint_form_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/plan_editor_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/widgets/request_chef_plan_card.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_profile_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_wallet_screen.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
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

final _member = MockBookingRepository(
  currentUserId: () => 'u_me',
  currentUserName: () => 'Minh Anh',
  currentRole: () => UserRole.user,
);

const _tamChef = Chef(
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

/// Pushes [screen] from a button, so the screen can pop.
Future<void> _pumpPushed(WidgetTester tester, Widget screen,
    {Map<String, Object> session = const {},
    Size size = const Size(411, 900)}) async {
  await _pump(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<Object?>(builder: (_) => screen)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    session: session,
    size: size,
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

/// Unmounts the screen and lets the mock latency timers finish.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Future<void> _wait(WidgetTester tester, [int seconds = 3]) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() {
    MockCommerceDb.reset();
    MockProfileRepository.reset();
    MockMealPlannerRepository.reset();
  });

  group('PaymentScreen (booking order → escrow)', () {
    late String orderId;

    Future<void> pumpPayment(WidgetTester tester,
        {bool showMockControls = true}) async {
      orderId = (await tester.runAsync(() async {
        final nego = await _member.getBooking('b_ma_tam_nego');
        await _member.respondToOffer(nego.id, nego.currentOffer!.id,
            accept: true);
        return _member.startPayment(nego.id);
      }))!
          .id;
      await _pumpPushed(tester,
          PaymentScreen(orderId: orderId, showMockControls: showMockControls),
          session: _minhAnh);
      await tester.pump(const Duration(seconds: 1)); // mock latency
    }

    testWidgets('amount, reference and countdown; paying holds the money',
        (tester) async {
      await pumpPayment(tester);
      expect(find.text('1.500.000đ'), findsOneWidget);
      expect(find.text('Thực đơn 10 ngày'), findsOneWidget);
      expect(find.textContaining(RegExp(r'Mã giao dịch: VL\d{10}')),
          findsOneWidget);
      expect(find.textContaining('Mã hết hạn sau 1'), findsOneWidget);
      expect(find.text('Mã QR mô phỏng'), findsOneWidget);
      expect(find.text('Đang chờ thanh toán…'), findsOneWidget);
      expect(find.textContaining('tiền được giữ đến'), findsOneWidget);

      await tester.ensureVisible(find.text('Mô phỏng đã thanh toán'));
      await tester.tap(find.text('Mô phỏng đã thanh toán'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      expect(find.textContaining('Đang giữ đến'), findsOneWidget);
      expect(find.text('Về kế hoạch'), findsOneWidget);
      expect(find.text('Lịch sử tư vấn'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('leaving while pending asks first; timers stop on dispose',
        (tester) async {
      await pumpPayment(tester);
      await tester.pageBack();
      await tester.pump();
      expect(find.text('Rời màn thanh toán?'), findsOneWidget);
      expect(
          find.text(
              'Bạn có thể thanh toán tiếp trong Lịch sử tư vấn trước hạn thanh toán.'),
          findsOneWidget);
      await tester.tap(find.text('Rời đi'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // no poll fires
    });

    testWidgets('no mock buttons when showMockControls is false',
        (tester) async {
      await pumpPayment(tester, showMockControls: false);
      expect(find.text('1.500.000đ'), findsOneWidget);
      expect(find.text('Mô phỏng đã thanh toán'), findsNothing);
      expect(find.text('Mã QR mô phỏng'), findsNothing);
      await _dispose(tester);
    });
  });

  group('chef profile', () {
    testWidgets('booking card with prices; a guest is asked to sign in to book',
        (tester) async {
      await _pump(tester, const ChefProfileScreen(chefId: 'u_chef_tam'),
          size: const Size(411, 1400));
      await _wait(tester);
      expect(find.text('Thiết kế thực đơn theo yêu cầu'), findsOneWidget);
      expect(
          find.text(
              'Từ 150.000đ/ngày · Có phản hồi mỗi ngày: 180.000đ/ngày · 3–30 ngày · Giá cuối do hai bên thoả thuận'),
          findsOneWidget);
      for (final gone in [
        'Dịch vụ',
        'Đặt lịch tư vấn',
        'Mua gói',
        'Mở nội dung'
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      await tester.tap(find.text('Đặt chuyên gia lên thực đơn').last);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SignInSheet), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('own profile and a chef who is not accepting requests',
        (tester) async {
      await _pump(tester, const ChefProfileScreen(chefId: 'u_chef_tam'),
          session: _tam, size: const Size(411, 1400));
      await _wait(tester);
      expect(find.textContaining('Đây là hồ sơ của bạn'), findsOneWidget);
      expect(find.text('Đặt chuyên gia lên thực đơn'), findsNothing);
      await _dispose(tester);

      await _pump(tester, const ChefProfileScreen(chefId: 'u_chef_minh'),
          session: _minhAnh, size: const Size(411, 1400));
      await _wait(tester);
      expect(
          find.text('Chuyên gia đang tạm ngưng nhận yêu cầu'), findsOneWidget);
      expect(find.text('Đặt chuyên gia lên thực đơn'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('directory pick mode; prices per day; full chips at 2x text',
        (tester) async {
      await _pump(tester, const ChefDirectoryScreen(pickMode: true),
          textScale: 2, size: const Size(411, 2400));
      await _wait(tester);
      expect(find.text('Chọn chuyên gia'), findsOneWidget);
      expect(find.text('Từ 150.000đ/ngày'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Tạm ngưng nhận yêu cầu'), 400,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Tạm ngưng nhận yêu cầu'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tất cả'), -400,
          scrollable: find.byType(Scrollable).first);
      for (final label in ['Tất cả', 'Ẩm thực chay Việt']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
            of: find.byType(ChoiceChip), matching: find.text(label)));
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  group('Tôi', () {
    Future<void> pumpProfile(WidgetTester tester, Map<String, Object> session,
        {double textScale = 1}) async {
      await _pump(tester, const ProfileScreen(),
          session: session, size: const Size(411, 2600), textScale: textScale);
      await _wait(tester);
    }

    testWidgets('Tâm gets the Chuyên gia section with KPIs and tools',
        (tester) async {
      await pumpProfile(tester, _tam);
      expect(find.text(UserRole.chef.label), findsWidgets);
      for (final label in [
        'Yêu cầu tư vấn',
        'Ví của tôi',
        'Hồ sơ & bảng giá',
        'Tài liệu kiến thức',
        'Yêu cầu mới',
        'Đang thực hiện',
        'Đang giữ (đ)',
        'Lịch sử tư vấn',
        'Bạn là chuyên gia đã xác minh',
        'Mở yêu cầu tư vấn ›',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('1.134.000'), findsOneWidget, reason: 'held net');
      for (final gone in [
        'Đơn hàng của tôi',
        'Lịch tư vấn',
        'Bảng điều khiển chuyên gia',
        'Google',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('Minh Anh gets "Lịch sử tư vấn" only, at 2x text too',
        (tester) async {
      await pumpProfile(tester, _minhAnh, textScale: 2);
      expect(find.text('Thành viên'), findsOneWidget);
      expect(find.text('Lịch sử tư vấn'), findsOneWidget);
      expect(find.text('Yêu cầu tư vấn'), findsNothing);
      expect(find.text('Đơn hàng của tôi'), findsNothing);
      expect(find.text('Lịch tư vấn'), findsNothing);
      expect(find.text('Trở thành chuyên gia'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('Lịch sử tư vấn: ongoing and finished tabs with outcomes',
      (tester) async {
    await _pump(tester, const BookingHistoryScreen(), session: _minhAnh);
    await _wait(tester);
    expect(find.text('Lê Quang Tâm'), findsOneWidget);
    expect(find.text('ThS. DD Phạm Thu Hà'), findsOneWidget);
    expect(find.text('Chờ bạn'), findsOneWidget,
        reason: "Tâm's offer waits for Minh Anh");
    expect(find.text('Đã nhận 7/7 ngày'), findsOneWidget);
    await tester.tap(find.text('Đã kết thúc'));
    await tester.pumpAndSettle();
    expect(find.text('Đã chuyển cho chuyên gia'), findsOneWidget);
    expect(find.text('Hoàn tất'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('Yêu cầu tư vấn: tabs with badges; members are kept out',
      (tester) async {
    await _pump(tester, const ChefBookingInboxScreen(), session: _tam);
    await _wait(tester);
    for (final tab in [
      'Mới',
      'Đang thương lượng',
      'Đang thực hiện',
      'Đã kết thúc',
    ]) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    expect(find.text('Hoàng Nam'), findsOneWidget);
    expect(find.text('Cần bạn xử lý'), findsOneWidget);
    await tester.ensureVisible(find.text('Đang thực hiện'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đang thực hiện'));
    await tester.pumpAndSettle();
    expect(find.text('Thảo Vy'), findsOneWidget);
    expect(find.text('Ngọc Trâm'), findsOneWidget);
    expect(find.text('Đã gửi 7/7 ngày'), findsOneWidget);
    await _dispose(tester);

    await _pump(tester, const ChefBookingInboxScreen(), session: _minhAnh);
    await tester.pump();
    expect(find.text('Chỉ dành cho chuyên gia'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets(
      'booking detail: the chef offer in the chat, accepting creates the '
      'contract and asks for payment', (tester) async {
    await _pump(tester, const BookingDetailScreen(bookingId: 'b_ma_tam_nego'),
        session: _minhAnh);
    await _wait(tester);
    expect(find.text('Lê Quang Tâm'), findsOneWidget);
    expect(find.text('Đang thoả thuận giá'), findsOneWidget);
    for (final step in ['Gửi yêu cầu', 'Thoả thuận giá', 'Hoàn tất']) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
    expect(find.text('Đề xuất giá · 1.500.000đ'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đồng ý'), findsOneWidget,
        reason: 'answer from the offer card');

    await tester.ensureVisible(find.text('Đồng ý 1.500.000đ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đồng ý 1.500.000đ'));
    await tester.pumpAndSettle();
    expect(find.text('Đồng ý 1.500.000đ?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Đồng ý')));
    await _wait(tester, 4);
    expect(find.text('Chờ thanh toán'), findsOneWidget);
    expect(find.text('Thanh toán 1.500.000đ'), findsOneWidget);

    await tester.tap(find.text('Hợp đồng'));
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ hợp đồng'), findsOneWidget);
    expect(
        find.textContaining('3 ngày sau khi kết thúc kế hoạch'), findsWidgets);
    await _dispose(tester);
  });

  testWidgets('complaint form: health risk needs a source link',
      (tester) async {
    final booking =
        (await tester.runAsync(() => _member.getBooking('b_ma_thuha_active')))!;
    await _pumpPushed(tester, ComplaintFormScreen(booking: booking),
        session: _minhAnh, size: const Size(411, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Có nội dung ảnh hưởng sức khoẻ'));
    await tester.enterText(find.widgetWithText(TextField, 'Mô tả chi tiết'),
        'Ngày 3 có món chiên nhiều dầu dù mình đã ghi rõ cần ít dầu.');
    await tester.tap(find.text('Gửi khiếu nại'));
    await tester.pump();
    expect(
        find.text('Hãy đính kèm nguồn (bài báo, tài liệu y khoa) chứng minh'),
        findsNWidgets(2),
        reason: 'hint and error');

    await tester.enterText(
        find.widgetWithText(TextField, 'Liên kết nguồn (http/https)'),
        'https://www.vinmec.com/bai-viet-dau-mo');
    await tester.tap(find.text('Thêm liên kết nguồn'));
    await tester.pump();
    expect(find.text('https://www.vinmec.com/bai-viet-dau-mo'), findsOneWidget);
    await tester.tap(find.text('Gửi khiếu nại'));
    await _wait(tester, 2);
    expect(find.text('open'), findsOneWidget, reason: 'popped after filing');
    final after =
        (await tester.runAsync(() => _member.getBooking('b_ma_thuha_active')))!;
    expect(after.complaint, isNotNull);
    await _dispose(tester);
  });

  testWidgets(
      "plan editor: yesterday's feedback on top, today's draft incomplete",
      (tester) async {
    await _pumpPushed(
        tester, const PlanEditorScreen(bookingId: 'b_vy_tam_active'),
        session: _tam, size: const Size(411, 1600));
    await _wait(tester);
    expect(find.text('Soạn kế hoạch'), findsOneWidget);
    expect(
        find.text(
            'Phản hồi ngày 2: ★★★★ · Làm theo một phần · "Bữa tối hơi nhiều dầu, mai anh cho em món hấp nhé."'),
        findsOneWidget);
    expect(find.textContaining('Hạn gửi: 06:00'), findsOneWidget);
    expect(find.text('Chưa có món'), findsOneWidget, reason: 'dinner missing');
    final send = find.widgetWithText(FilledButton, 'Gửi ngày này');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await _dispose(tester);
  });

  testWidgets('book a chef: estimate follows the type; sending opens the chat',
      (tester) async {
    await _pumpPushed(tester, const BookChefPlanScreen(chef: _tamChef),
        session: _minhAnh, size: const Size(411, 2400));
    await _wait(tester);
    expect(
        find.text(
            '≈ 7 ngày × 180.000đ = 1.260.000đ (giá cuối do hai bên thoả thuận)'),
        findsOneWidget);
    await tester.tap(find.text('Giao trọn kế hoạch một lần'));
    await tester.pump();
    expect(
        find.text(
            '≈ 7 ngày × 150.000đ = 1.050.000đ (giá cuối do hai bên thoả thuận)'),
        findsOneWidget);
    expect(find.text('Đậu phộng'), findsOneWidget,
        reason: 'allergies from the health profile');

    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pump();
    expect(find.textContaining('ít nhất 20 ký tự'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nhu cầu & ghi chú'),
        'Mình cần thực đơn chay tăng cơ, bữa sáng nhanh dưới 15 phút.');
    await tester.tap(find.text('Gửi yêu cầu'));
    await _wait(tester, 4);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    expect(find.text('Chờ báo giá'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('Thực đơn card: guests sign in first, members pick a chef',
      (tester) async {
    await _pump(tester, const Scaffold(body: RequestChefPlanCard()));
    await tester.tap(find.text('Nhờ chuyên gia lên thực đơn ›'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SignInSheet), findsOneWidget);
    await _dispose(tester);

    await _pump(tester, const Scaffold(body: RequestChefPlanCard()),
        session: _minhAnh);
    await tester.tap(find.text('Nhờ chuyên gia lên thực đơn ›'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn chuyên gia'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('wallet: held, frozen and available figures; escrow ledger',
      (tester) async {
    await _pump(tester, const ChefWalletScreen(),
        session: _tam, size: const Size(411, 2600));
    await _wait(tester, 4);
    expect(find.text('110.000đ'), findsOneWidget);
    expect(find.text('1.134.000đ'), findsWidgets);
    expect(find.text('945.000đ'), findsWidgets);
    expect(find.text('Tạm giữ do khiếu nại'), findsWidgets);
    expect(find.text('Vietcombank •••• 6789'), findsOneWidget);
    expect(find.text('Thu nhập · Thực đơn 7 ngày · Có phản hồi mỗi ngày'),
        findsWidgets);
    expect(find.textContaining('Giữ đến'), findsOneWidget);
    expect(find.text('Gộp 1.260.000đ · Phí 126.000đ · Thực nhận 1.134.000đ'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets(
      'chef view: a new request offers "Báo giá" / "Từ chối" and shows the '
      'shared health profile', (tester) async {
    await _pump(tester, const BookingDetailScreen(bookingId: 'b_nam_tam_req'),
        session: _tam);
    await _wait(tester);
    expect(find.text('Hoàng Nam'), findsOneWidget);
    expect(find.text('Báo giá'), findsOneWidget);
    expect(find.text('Từ chối'), findsOneWidget);
    expect(find.text('Thành viên chờ bạn báo giá.'), findsOneWidget);
    await tester.tap(find.text('Hợp đồng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('26 tuổi'), findsOneWidget);
    expect(
        find.text(
            'Hồ sơ hợp đồng được tạo khi hai bên đồng ý một đề xuất giá.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets(
      'chef view of a complaint: evidence, answer and the frozen escrow',
      (tester) async {
    await _pump(tester,
        const BookingDetailScreen(bookingId: 'b_tram_tam', initialTab: 2),
        session: _tam, size: const Size(411, 2400));
    await _wait(tester);
    expect(find.text('Khiếu nại'), findsOneWidget);
    expect(find.text('Có nội dung ảnh hưởng sức khoẻ'), findsOneWidget);
    expect(
        find.text(
            'FDA: Nước ép bưởi và một số loại thuốc không nên dùng chung'),
        findsOneWidget);
    expect(find.text('Ảnh chụp kế hoạch ngày 4'), findsOneWidget);
    expect(find.text('Phản hồi của chuyên gia'), findsOneWidget);
    expect(find.text('Khiếu nại · tạm giữ tiền'), findsOneWidget);
    expect(find.text('Chờ Ban quản trị quyết định'), findsOneWidget);
    expect(find.text('Bạn nhận sau phí'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets(
      'member plan tab: delivered days and "Áp dụng kế hoạch vào Thực đơn"',
      (tester) async {
    await _pump(
        tester,
        const BookingDetailScreen(
            bookingId: 'b_ma_thuha_active', initialTab: 1),
        session: _minhAnh,
        size: const Size(411, 2400));
    await _wait(tester);
    expect(find.text('Áp dụng kế hoạch vào Thực đơn'), findsOneWidget);
    expect(find.textContaining('Ngày 1 · '), findsOneWidget);
    expect(find.textContaining('Uống đủ 2 lít nước'), findsOneWidget);
    expect(find.text('Phản hồi ngày này'), findsNothing,
        reason: 'one-shot plans have no daily feedback');
    expect(find.text('Khiếu nại'), findsOneWidget, reason: 'header action');
    await tester.tap(find.text('Áp dụng kế hoạch vào Thực đơn'));
    // The seeded week holds other dishes: replacing them is confirmed first.
    for (var i = 0;
        i < 16 && find.byType(AlertDialog).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.text('Thay và áp dụng'));
    // The planner loads, then all 28 meals go in one batched request: done
    // within 8 s of mock latency (one request per meal took ~25 s).
    for (var i = 0; i < 32 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining('Thực đơn')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  test('BookingDto.toJson round trip keeps the plan meal fields', () {
    final meal = PlanMealDto.fromJson({
      'slot': 'snack_pm',
      'recipe': {
        'id': 'rc_1',
        'name': 'Chè đậu đen',
        'calories': 180,
        'ingredients': [
          {'name': 'Đậu đen'},
          'Đường phèn',
        ],
      },
      'note': 'Ít đường',
    });
    expect(meal.recipe.ingredients, ['Đậu đen', 'Đường phèn']);
    expect(PlanMealDto.fromJson(meal.toJson()).recipe.calories, 180);
  });
}
