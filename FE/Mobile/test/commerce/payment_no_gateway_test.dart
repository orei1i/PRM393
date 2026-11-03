// test/commerce/payment_no_gateway_test.dart
// The payment screen on the real modules, with fakes in place of the server: a
// gateway that is missing or down stays a message on that screen, the wallet
// keeps working, and nothing but the server's answer reads as paid.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/booking/data/booking_api_service.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/commerce/data/commerce_api_service.dart';
import 'package:veganlife_mobile/features/commerce/data/member_wallet_api_service.dart';
import 'package:veganlife_mobile/features/commerce/data/models/order_model.dart';
import 'package:veganlife_mobile/features/commerce/data/models/payment_model.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';

const _orderId = 'ord_1';
const _me = 'member_real_id';

Map<String, dynamic> _payment(String status, {String provider = 'Sandbox'}) => {
      'id': 'pay_1',
      'orderId': _orderId,
      'provider': provider,
      'transactionRef': 'VL0001',
      'qrCodeUrl': null,
      'status': status,
      'amount': 300000,
      'expiresAt':
          DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
    };

OrderDto _order({String status = 'Pending', Map<String, dynamic>? payment}) =>
    OrderDto.fromJson({
      'id': _orderId,
      'userId': _me,
      'bookingId': 'b_1',
      'amount': 300000,
      'status': status,
      'createdAt': '2026-11-01T00:00:00Z',
      'booking': {
        'id': 'b_1',
        'chefId': 'chef_1',
        'chefName': 'Chuyên gia Thử',
        'bookingType': 'OneShot',
        'planDays': 3,
        'startDate': '2026-11-10',
        'endDate': '2026-11-12',
        'status': 'AwaitingPayment',
      },
      'payment': payment,
    });

class _Commerce implements CommerceApiService {
  _Commerce({this.renewError, Map<String, dynamic>? payment})
      : order = _order(payment: payment);

  OrderDto order;
  ApiException? renewError;
  var renewCalls = 0;
  var walletCalls = 0;
  final confirmed = <bool>[];

  @override
  Future<OrderDto> getOrder(String id) async => order;

  @override
  Future<PaymentDto> renewPayment(String orderId) async {
    renewCalls++;
    final error = renewError;
    if (error != null) throw error;
    order = _order(payment: _payment('Pending'));
    return order.payment!;
  }

  @override
  Future<PaymentDto> getPayment(String id) async => order.payment!;

  @override
  Future<OrderDto> payWithWallet(String orderId) async {
    walletCalls++;
    order = _order(status: 'Paid', payment: {
      ..._payment('Paid', provider: 'Wallet'),
      'paidAt': DateTime.now().toIso8601String(),
    });
    return order;
  }

  @override
  Future<PaymentDto> mockConfirmPayment(String paymentId,
      {required bool success}) async {
    confirmed.add(success);
    order = _order(
        status: success ? 'Paid' : 'Pending',
        payment: _payment(success ? 'Paid' : 'Failed'));
    return order.payment!;
  }
}

class _Wallet implements MemberWalletApiService {
  _Wallet(this.available);

  int available;

  @override
  Future<WalletDto> getWallet() async =>
      WalletDto(available: available, pending: 0, withdrawn: 0);

  @override
  Future<List<WalletTransactionDto>> transactions() async => const [];

  @override
  Future<List<WithdrawalDto>> withdrawals() async => const [];

  @override
  Future<BankAccountDto> saveBankAccount(BankAccountDto account) async =>
      account;

  @override
  Future<WithdrawalDto> requestWithdrawal(WithdrawalRequestDto request) =>
      throw UnimplementedError();

  @override
  Future<WithdrawalDto> mockDecideWithdrawal(String id,
          {required bool approve}) =>
      throw UnimplementedError();
}

const _noGateway = ApiException(
  message: 'Cổng thanh toán chưa sẵn sàng.',
  statusCode: 503,
  code: 'payment_unavailable',
);

Future<void> _pump(WidgetTester tester, Widget home,
    {required _Commerce commerce,
    required int balance,
    List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(600, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SessionController.accessTokenKey: 'test-token',
    'vl.user_id': _me,
    'vl.display_name': 'Thành viên',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      commerceApiProvider.overrideWithValue(commerce),
      memberWalletApiProvider.overrideWithValue(_Wallet(balance)),
      ...overrides,
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  setUp(() => BackendModules.debugOverride(const {
        BackendModule.auth,
        BackendModule.commerce,
        BackendModule.chefWallet,
        BackendModule.bookings,
      }));
  tearDown(() => BackendModules.debugOverride(null));

  group('no gateway', () {
    testWidgets('it says so and stays, with no QR and nothing paid',
        (tester) async {
      final commerce = _Commerce(renewError: _noGateway);
      await _pump(
          tester, const PaymentScreen(orderId: _orderId, autoRenew: true),
          commerce: commerce, balance: 0);

      expect(commerce.renewCalls, 1);
      expect(find.text('Chưa thanh toán qua cổng được'), findsOneWidget);
      expect(find.textContaining('Cổng thanh toán đang chưa sẵn sàng'),
          findsOneWidget);
      expect(find.textContaining('chưa bị trừ tiền'), findsOneWidget);
      expect(find.text('Thanh toán thành công'), findsNothing);
      expect(find.textContaining('Mã giao dịch'), findsNothing);
      expect(find.textContaining('Mô phỏng'), findsNothing);
      expect(find.text('Số dư ví 0đ chưa đủ để thanh toán bằng ví.'),
          findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('the wallet still pays, and only then it reads as paid',
        (tester) async {
      final commerce = _Commerce(renewError: _noGateway);
      await _pump(
          tester, const PaymentScreen(orderId: _orderId, autoRenew: true),
          commerce: commerce, balance: 500000);

      expect(find.text('Số dư ví 500.000đ'), findsOneWidget);
      await tester.tap(find.text('Thanh toán bằng ví'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(commerce.walletCalls, 0, reason: 'asks first');
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(commerce.walletCalls, 1);
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('"Thử lại" gets the QR once the gateway is back',
        (tester) async {
      final commerce = _Commerce(renewError: _noGateway);
      await _pump(
          tester, const PaymentScreen(orderId: _orderId, autoRenew: true),
          commerce: commerce, balance: 0);
      commerce.renewError = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(commerce.renewCalls, 2);
      expect(find.text('Chưa thanh toán qua cổng được'), findsNothing);
      expect(find.textContaining('VL0001'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('any other failure is said too, and stays', (tester) async {
      final commerce = _Commerce(
          renewError: const ApiException(
              message: 'Không kết nối được máy chủ.', statusCode: null));
      await _pump(
          tester, const PaymentScreen(orderId: _orderId, autoRenew: true),
          commerce: commerce, balance: 500000);
      expect(find.text('Chưa tạo được mã QR'), findsOneWidget);
      expect(find.textContaining('Không kết nối được máy chủ.'), findsOneWidget);
      expect(find.text('Thanh toán bằng ví'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('an expired QR still offers the wallet', (tester) async {
      final commerce = _Commerce(payment: _payment('Expired'));
      await _pump(tester, const PaymentScreen(orderId: _orderId),
          commerce: commerce, balance: 500000);
      expect(find.text('Mã QR đã hết hạn'), findsOneWidget);
      expect(find.text('Tạo mã mới'), findsOneWidget);
      expect(find.text('Thanh toán bằng ví'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('what a pending payment shows', () {
    testWidgets('the sandbox gateway says it is one, not a bank QR',
        (tester) async {
      final commerce = _Commerce();
      await _pump(
          tester, const PaymentScreen(orderId: _orderId, autoRenew: true),
          commerce: commerce, balance: 0);
      expect(find.textContaining('Cổng thử nghiệm, không có tiền thật'),
          findsOneWidget);
      expect(find.textContaining('Quét bằng ứng dụng ngân hàng'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('the demo pays through the sandbox from this screen',
        (tester) async {
      final commerce = _Commerce();
      await _pump(
          tester, const PaymentScreen(orderId: _orderId, autoRenew: true),
          commerce: commerce, balance: 0);
      expect(find.textContaining('không có tiền thật'), findsWidgets);

      final paid = find.text('Mô phỏng đã thanh toán');
      await tester.ensureVisible(paid);
      await tester.tap(paid);
      await tester.pump(const Duration(seconds: 1));
      expect(commerce.confirmed, [true]);
      expect(paid, findsNothing, reason: 'the order is paid');
      await _dispose(tester);
    });

    testWidgets('a real gateway without a picture draws no made-up QR',
        (tester) async {
      final commerce = _Commerce(payment: _payment('Pending', provider: 'MoMo'));
      await _pump(tester, const PaymentScreen(orderId: _orderId),
          commerce: commerce, balance: 0);
      expect(find.text('Máy chủ chưa gửi mã QR.'), findsOneWidget);
      expect(find.textContaining('qua MoMo'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('the booking page', () {
    BookingDto booking() => BookingDto.fromJson({
          'id': 'b_1',
          'member': {'id': _me, 'fullName': 'Thành viên', 'email': 'a@b.c'},
          'chef': {'id': 'chef_1', 'fullName': 'Chuyên gia', 'email': 'c@b.c'},
          'bookingType': 'OneShot',
          'planDays': 3,
          'startDate': '2026-11-10',
          'audience': 'Self',
          'allergies': <String>[],
          'mealPattern': ['lunch'],
          'needs': 'Mình cần một thực đơn thuần chay cân bằng.',
          'status': 'AwaitingPayment',
          'deliveredDays': 0,
          'contract': {
            'id': 'c_1',
            'bookingId': 'b_1',
            'offerId': 'o_1',
            'price': 300000,
            'planDays': 3,
            'bookingType': 'OneShot',
            'startDate': '2026-11-10',
            'endDate': '2026-11-12',
            'deliveryDueAt': '2026-11-13T00:00:00Z',
            'feeRate': 0.1,
            'holdDays': 7,
            'paymentDueAt': '2026-11-09T00:00:00Z',
            'createdAt': '2026-11-01T00:00:00Z',
          },
          'paymentOrderId': _orderId,
          'createdAt': '2026-11-01T00:00:00Z',
        });

    testWidgets(
        'on the real BE: the member is recognised by their real id, and '
        '"Thanh toán" opens the payment screen without asking for a QR first',
        (tester) async {
      final commerce = _Commerce(renewError: _noGateway);
      final bookings = _Bookings(booking());
      await _pump(tester, const BookingDetailScreen(bookingId: 'b_1'),
          commerce: commerce,
          balance: 500000,
          overrides: [bookingApiProvider.overrideWithValue(bookings)]);
      expect(find.text('Không xem được yêu cầu này'), findsNothing);
      await tester.tap(find.textContaining('Thanh toán 300.000đ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(bookings.startPayments, 0);
      expect(commerce.renewCalls, 1);
      expect(find.text('Chưa thanh toán qua cổng được'), findsOneWidget);
      expect(find.text('Thanh toán bằng ví'), findsOneWidget);
      await _dispose(tester);
    });
  });
}

/// The mock's plumbing, the fake's booking.
class _Bookings extends MockBookingRepository {
  _Bookings(this.booking)
      : super(
          currentUserId: () => _me,
          currentUserName: () => 'Thành viên',
          currentRole: () => UserRole.user,
        );

  final BookingDto booking;
  var startPayments = 0;

  @override
  Future<BookingDto> getBooking(String id) async => booking;

  @override
  Future<OrderDto> startPayment(String id) async {
    startPayments++;
    throw _noGateway;
  }

  @override
  Future<List<MessageDto>> messages(String id, {DateTime? after}) async =>
      const [];

  @override
  Future<List<PlanDayDto>> plan(String id) async => const [];
}
