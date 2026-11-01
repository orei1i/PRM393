// test/chef/stuck_hold_widgets_test.dart
// A booking whose stuck hold an admin decided, on the real detail screen, for
// both sides: the header and the contract tab say so, with no prompts left.
@Timeout(Duration(seconds: 240))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/features/booking/data/mock/mock_booking_db.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_history_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/chef_booking_inbox_screen.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';

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

const _note = 'Chuyên gia ngừng giao từ ngày 4, hai bên không phản hồi.';
const _id = 'b_ma_tam_short'; // 500.000đ, 3 of 5 days sent, past the moment.

void _resolve(ComplaintDecision decision, {int? refund}) {
  final db = MockBookingDb.instance;
  db.resolveHold(db.booking(_id).escrow!.id,
      decision: decision,
      refundAmount: refund,
      note: _note,
      by: 'Lê Minh Quân');
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required Map<String, Object> session,
  Size size = const Size(411, 2400),
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
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

const _contract = BookingDetailScreen(bookingId: _id, initialTab: 2);

void _expectNoPrompts() {
  for (final text in [
    'Khiếu nại',
    'Huỷ yêu cầu',
    'Xác nhận hoàn thành',
    'Soạn kế hoạch',
    'Chuyên gia xác nhận hoàn thành',
    'Chưa có ngày',
  ]) {
    expect(find.text(text), findsNothing, reason: text);
  }
  expect(find.textContaining('bạn hãy gửi khiếu nại'), findsNothing);
  expect(find.textContaining('Hãy gửi đủ rồi xác nhận'), findsNothing);
  expect(find.textContaining('Lý do huỷ'), findsNothing);
  expect(find.textContaining('Đã huỷ:'), findsNothing);
  expect(find.textContaining('Lê Minh Quân'), findsNothing,
      reason: 'both sides read "Ban quản trị", not the admin');
}

void main() {
  setUp(() {
    MockCommerceDb.reset();
    MockProfileRepository.reset();
    MockMealPlannerRepository.reset();
  });

  group('before the decision', () {
    testWidgets('the seed still asks the member to complain', (tester) async {
      await _pump(tester, _contract, session: _minhAnh);
      expect(find.text('Khiếu nại'), findsOneWidget);
      expect(find.text('Ban quản trị xử lý'), findsNothing);
      await _dispose(tester);
    });
  });

  group('the member', () {
    testWidgets('ReleaseToChef', (tester) async {
      _resolve(ComplaintDecision.releaseToChef);
      await _pump(tester, _contract, session: _minhAnh);
      const line = 'Đã chuyển 450.000đ sau phí cho chuyên gia';
      expect(find.text('Ban quản trị đã xử lý: $line. Ghi chú: "$_note"'),
          findsOneWidget);
      expect(find.text(line), findsOneWidget);
      expect(find.text('Ban quản trị xử lý'), findsWidgets);
      expect(find.text('"$_note"'), findsOneWidget);
      expect(find.text('Đã vào ví chuyên gia'), findsWidgets);
      _expectNoPrompts();
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets(
        'RefundMember reads as the admin, not as their own cancellation',
        (tester) async {
      _resolve(ComplaintDecision.refundMember);
      await _pump(tester, _contract, session: _minhAnh);
      const line = 'Đã hoàn 500.000đ vào Ví của tôi';
      expect(find.text('Ban quản trị đã xử lý: $line. Ghi chú: "$_note"'),
          findsOneWidget);
      expect(find.text(line), findsOneWidget);
      expect(find.text('Không chuyển'), findsOneWidget);
      expect(find.text('Đã hoàn 500.000đ vào ví thành viên'), findsOneWidget);
      _expectNoPrompts();
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('Split', (tester) async {
      _resolve(ComplaintDecision.split, refund: 200000);
      await _pump(tester, _contract, session: _minhAnh);
      const line =
          'Đã hoàn 200.000đ vào Ví của tôi, chuyên gia nhận 270.000đ sau phí';
      expect(find.text(line), findsOneWidget);
      expect(
          find.textContaining('Ban quản trị đã xử lý: $line'), findsOneWidget);
      expect(find.text('Hoàn 200.000đ · chuyên gia nhận 270.000đ'),
          findsOneWidget);
      _expectNoPrompts();
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('the card in the history says it too, with no "Chờ bạn"',
        (tester) async {
      _resolve(ComplaintDecision.refundMember);
      await _pump(tester, const BookingHistoryScreen(), session: _minhAnh);
      // Not among the ongoing ones any more.
      expect(
          find.text('Ban quản trị đã xử lý: Đã hoàn 500.000đ vào Ví của tôi'),
          findsNothing);
      await tester.tap(find.text('Đã kết thúc'));
      await tester.pumpAndSettle();
      expect(
          find.text('Ban quản trị đã xử lý: Đã hoàn 500.000đ vào Ví của tôi'),
          findsOneWidget);
      expect(find.text('Chờ bạn'), findsNothing);
      await _dispose(tester);
    });
  });

  group('the chef', () {
    testWidgets('ReleaseToChef', (tester) async {
      _resolve(ComplaintDecision.releaseToChef);
      await _pump(tester, _contract, session: _tam);
      const line = '450.000đ sau phí đã vào ví của bạn';
      expect(find.text('Ban quản trị đã xử lý: $line. Ghi chú: "$_note"'),
          findsOneWidget);
      expect(find.text(line), findsOneWidget);
      expect(find.text('Rút về ngân hàng'), findsOneWidget);
      _expectNoPrompts();
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('RefundMember', (tester) async {
      _resolve(ComplaintDecision.refundMember);
      await _pump(tester, _contract, session: _tam);
      const line = 'Hoàn 500.000đ cho thành viên, bạn không nhận tiền';
      expect(find.text('Ban quản trị đã xử lý: $line. Ghi chú: "$_note"'),
          findsOneWidget);
      expect(find.text(line), findsOneWidget);
      expect(find.text('Rút về ngân hàng'), findsNothing);
      _expectNoPrompts();
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('Split', (tester) async {
      _resolve(ComplaintDecision.split, refund: 200000);
      await _pump(tester, _contract, session: _tam);
      const line =
          'Hoàn 200.000đ cho thành viên, 270.000đ sau phí đã vào ví của bạn';
      expect(find.text(line), findsOneWidget);
      _expectNoPrompts();
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('the inbox no longer flags it "Cần bạn xử lý"', (tester) async {
      _resolve(ComplaintDecision.split, refund: 200000);
      await _pump(tester, const ChefBookingInboxScreen(), session: _tam);
      await tester.ensureVisible(find.textContaining('Đã kết thúc').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Đã kết thúc').first);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(
          find.text(
              'Ban quản trị đã xử lý: Hoàn 200.000đ cho thành viên, 270.000đ sau phí đã vào ví của bạn'),
          findsOneWidget);
      await _dispose(tester);
    });
  });

  testWidgets('360 dp at font 1.3: no overflow, for either side',
      (tester) async {
    _resolve(ComplaintDecision.split, refund: 200000);
    for (final session in [_minhAnh, _tam]) {
      await _pump(tester, _contract,
          session: session, size: const Size(360, 780), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    }
  });

  group('a plan delivered in full after the moment', () {
    // Moves the mock clock past the moment with a chef still able to act: the
    // texts must not promise an auto-completion time already gone.
    testWidgets('neither side is promised a time already gone', (tester) async {
      final db = MockBookingDb.instance;
      final row = db.booking(_id);
      for (final d in row.days) {
        d
          ..status = PlanDayStatus.sent
          ..sentAt = db.now;
      }
      for (final session in [_minhAnh, _tam]) {
        await _pump(tester, _contract, session: session);
        expect(find.textContaining('hệ thống tự hoàn tất lúc'), findsNothing);
        expect(find.textContaining('nên không tự hoàn tất'), findsWidgets);
        expect(tester.takeException(), isNull);
        await _dispose(tester);
      }
    });
  });
}
