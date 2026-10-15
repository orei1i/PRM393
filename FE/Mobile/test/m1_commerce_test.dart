// test/m1_commerce_test.dart
// The mock repositories wait like a network (0.5–1 s per call).
@Timeout(Duration(seconds: 90))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/chef/data/mock_chef_repository.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_studio_repository.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/data/models/order_model.dart';
import 'package:veganlife_mobile/features/commerce/domain/commerce_status.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';

Matcher apiError(int status, [String? code]) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.code, 'code', code ?? anything);

void main() {
  group('DTO parsing', () {
    test('INT ids become strings; type variants; missing payment is null', () {
      final order = OrderDto.fromJson({
        'id': 501,
        'userId': 7,
        'serviceId': 13,
        'amount': 690000,
        'status': 'pending',
        'createdAt': '2026-10-15T02:00:00Z',
        'service': {
          'id': 13,
          'title': 'Thực đơn VIP',
          'type': 'VIP Menu',
          'chefId': 3,
          'chefName': 'Thu Hà'
        },
      });
      expect(order.id, '501');
      expect(order.userId, '7');
      expect(order.service.chefId, '3');
      expect(order.status, OrderStatus.pending);
      expect(order.type, ServiceType.vipMenu);
      expect(order.payment, isNull);
      expect(order.accessGrant, isNull);
      expect(order.consultation, isNull);
      expect(order.createdAt.isUtc, isFalse);

      for (final raw in ['VIP Menu', 'VipMenu', 'VIP_MENU', 'vip menu']) {
        expect(ServiceType.fromApi(raw), ServiceType.vipMenu, reason: raw);
      }
      expect(ServiceType.fromApi('Course'), ServiceType.course);
      expect(ServiceType.fromApi(null), ServiceType.consult);
      expect(ConsultationStatus.fromApi('in_progress'),
          ConsultationStatus.inProgress);
      expect(ConsultationStatus.fromApi('AwaitingPayment'),
          ConsultationStatus.awaitingPayment);
      expect(PaymentStatus.fromApi('EXPIRED'), PaymentStatus.expired);
    });

    test('payment, grant and consultation blocks', () {
      final order = OrderDto.fromJson({
        'id': 'od_1',
        'status': 'Paid',
        'amount': 350000,
        'service': {'id': 12, 'title': 'Tư vấn', 'type': 'Consult'},
        'payment': {
          'id': 901,
          'orderId': 'od_1',
          'provider': 'PaymentOS',
          'transactionRef': 'VL2610150001',
          'status': 'Paid',
          'paidAt': '2026-10-15T02:05:00Z',
          'amount': 350000,
        },
        'accessGrant': {
          'id': 77,
          'paymentId': 901,
          'grantedAt': '2026-10-15T02:05:00Z',
          'expiresAt': '2026-10-18T12:30:00Z',
          'status': 'Active',
        },
        'consultation': {
          'id': 31,
          'buyer': {'id': 7, 'name': 'Minh Anh'},
          'startAt': '2026-10-17T12:30:00Z',
          'durationMinutes': 60,
          'status': 'Pending',
          'buyerNote': '  ',
        },
      });
      expect(order.serviceId, '12', reason: 'falls back to service.id');
      expect(order.payment!.id, '901');
      expect(order.payment!.status, PaymentStatus.paid);
      final grant = order.accessGrant!;
      expect(grant.statusAt(DateTime.utc(2026, 10, 16)), GrantStatus.active);
      expect(grant.statusAt(DateTime.utc(2026, 10, 19)), GrantStatus.expired,
          reason: 'an Active grant past expiresAt reads as Expired');
      final c = order.consultation!;
      expect(c.buyer!.fullName, 'Minh Anh');
      expect(c.buyerNote, isNull, reason: 'blank notes are dropped');
      expect(c.endAt.difference(c.startAt).inMinutes, 60);
    });

    test('CreateOrderRequestDto sends numeric ids as numbers, UTC times', () {
      final json = CreateOrderRequestDto(
        serviceId: '12',
        startAt: DateTime.utc(2026, 10, 17, 12, 30).toLocal(),
        note: '  Bé 6 tuổi  ',
      ).toJson();
      expect(json['serviceId'], 12);
      expect(json['startAt'], '2026-10-17T12:30:00.000Z');
      expect(json['note'], 'Bé 6 tuổi');
      expect(const CreateOrderRequestDto(serviceId: 'svc_tam_course').toJson(),
          {'serviceId': 'svc_tam_course'});
    });
  });

  group('mock commerce flow', () {
    late DateTime now;
    late String? userId;
    late String userName;
    late UserRole role;
    final buyer = MockCommerceRepository(
        currentUserId: () => userId, currentUserName: () => userName);
    final studio = MockChefStudioRepository(
      currentUserId: () => userId,
      currentUserName: () => userName,
      currentRole: () => role,
    );
    final chefs = MockChefRepository();

    void asMinhAnh() {
      userId = 'u_me';
      userName = 'Minh Anh';
      role = UserRole.user;
    }

    void asTam() {
      userId = 'u_chef_tam';
      userName = 'Lê Quang Tâm';
      role = UserRole.chef;
    }

    setUp(() {
      now = DateTime(2026, 10, 15, 9);
      MockCommerceDb.reset(clock: () => now);
      asMinhAnh();
    });

    Future<List<DateTime>> freeSlots() async =>
        (await chefs.getChef('u_chef_tam')).availableSlots;

    bool hasSlot(List<DateTime> slots, DateTime slot) =>
        slots.any((s) => s.isAtSameMomentAs(slot));

    test('consult: order holds the slot, payment grants access, chef sees it',
        () async {
      final slot = (await freeSlots()).first;
      final order = await buyer.createOrder(CreateOrderRequestDto(
          serviceId: 'svc_tam_consult', startAt: slot, note: 'Nhà 4 người'));
      expect(order.status, OrderStatus.pending);
      expect(order.amount, 350000);
      final payment = order.payment!;
      expect(payment.status, PaymentStatus.pending);
      expect(payment.transactionRef, matches(RegExp(r'^VL261015\d{4}$')));
      expect(payment.expiresAt!.difference(now), const Duration(minutes: 15));
      expect(order.consultation!.status, ConsultationStatus.awaitingPayment);
      expect(hasSlot(await freeSlots(), slot), isFalse, reason: 'held');

      await buyer.mockConfirmPayment(payment.id, success: true);
      final paid = await buyer.getOrder(order.id);
      expect(paid.status, OrderStatus.paid);
      expect(paid.payment!.paidAt, isNotNull);
      expect(paid.accessGrant!.status, GrantStatus.active);
      expect(paid.accessGrant!.expiresAt, slot.add(const Duration(hours: 24)),
          reason: 'startAt + 24 h');
      expect(paid.consultation!.status, ConsultationStatus.pending);
      expect(hasSlot(await freeSlots(), slot), isFalse, reason: 'still held');

      asTam();
      final pending =
          await studio.myConsultations(status: ConsultationStatus.pending);
      final mine = pending.singleWhere((c) => c.orderId == order.id);
      expect(mine.buyer!.fullName, 'Minh Anh');
      expect(mine.buyerNote, 'Nhà 4 người');
    });

    test('#expire: the QR expires after 30 s, renew and cancel free the slot',
        () async {
      final slot = (await freeSlots()).first;
      final order = await buyer.createOrder(CreateOrderRequestDto(
          serviceId: 'svc_tam_consult', startAt: slot, note: 'thử #expire'));
      expect(order.payment!.expiresAt!.difference(now),
          const Duration(seconds: 30));

      now = now.add(const Duration(seconds: 31));
      final expired = await buyer.getPayment(order.payment!.id);
      expect(expired.status, PaymentStatus.expired);
      expect(hasSlot(await freeSlots(), slot), isTrue,
          reason: 'an expired QR releases the hold');
      await expectLater(buyer.mockConfirmPayment(expired.id, success: true),
          throwsA(apiError(409, 'payment_expired')));

      final renewed = await buyer.renewPayment(order.id);
      expect(renewed.id, isNot(expired.id));
      expect(renewed.transactionRef, isNot(expired.transactionRef));
      expect(renewed.status, PaymentStatus.pending);
      expect(renewed.expiresAt!.difference(now), const Duration(minutes: 15));
      expect(hasSlot(await freeSlots(), slot), isFalse);

      final cancelled = await buyer.cancelOrder(order.id);
      expect(cancelled.status, OrderStatus.cancelled);
      expect(cancelled.payment!.status, PaymentStatus.expired);
      expect(cancelled.consultation!.status, ConsultationStatus.cancelled);
      expect(hasSlot(await freeSlots(), slot), isTrue);
    });

    test('#fail, a taken slot and buying your own service are refused',
        () async {
      final slot = (await freeSlots()).first;
      await expectLater(
          buyer.createOrder(CreateOrderRequestDto(
              serviceId: 'svc_tam_consult', startAt: slot, note: '#fail')),
          throwsA(apiError(503)));

      await buyer.createOrder(
          CreateOrderRequestDto(serviceId: 'svc_tam_consult', startAt: slot));
      userId = 'u_someone';
      await expectLater(
          buyer.createOrder(CreateOrderRequestDto(
              serviceId: 'svc_tam_consult', startAt: slot)),
          throwsA(apiError(409, 'slot_taken')));

      asTam();
      await expectLater(
          buyer.createOrder(
              const CreateOrderRequestDto(serviceId: 'svc_tam_course')),
          throwsA(apiError(409, 'own_service')));
    });

    test('a chef decline and a buyer cancel both refund (stub)', () async {
      final slots = await freeSlots();
      Future<OrderDto> bookAndPay(DateTime slot) async {
        final o = await buyer.createOrder(
            CreateOrderRequestDto(serviceId: 'svc_tam_consult', startAt: slot));
        await buyer.mockConfirmPayment(o.payment!.id, success: true);
        return o;
      }

      final declined = await bookAndPay(slots[0]);
      final cancelled = await bookAndPay(slots[1]);

      asTam();
      final id = (await studio.myConsultations())
          .singleWhere((c) => c.orderId == declined.id)
          .id;
      await expectLater(
          studio.declineConsultation(id, 'Bận'), throwsA(apiError(400)));
      await expectLater(studio.declineConsultation(id, 'Bận việc #fail'),
          throwsA(apiError(503)));
      final c = await studio.declineConsultation(id, 'Hôm đó tôi đi công tác.');
      expect(c.status, ConsultationStatus.declined);

      asMinhAnh();
      final refunded = await buyer.getOrder(declined.id);
      expect(refunded.status, OrderStatus.refunded);
      expect(refunded.payment!.status, PaymentStatus.refunded);
      expect(refunded.accessGrant!.status, GrantStatus.revoked);
      expect(refunded.consultation!.declineReason, 'Hôm đó tôi đi công tác.');
      expect(hasSlot(await freeSlots(), slots[0]), isTrue);

      final mine = (await buyer.myConsultations())
          .singleWhere((c) => c.orderId == cancelled.id);
      final after = await buyer.cancelConsultation(mine.id);
      expect(after.status, ConsultationStatus.cancelled);
      final order = await buyer.getOrder(cancelled.id);
      expect(order.status, OrderStatus.refunded);
      expect(order.accessGrant!.status, GrantStatus.revoked);
    });

    test('a confirmed consult can only be cancelled 24 h ahead', () async {
      final slot = (await freeSlots()).first;
      final o = await buyer.createOrder(
          CreateOrderRequestDto(serviceId: 'svc_tam_consult', startAt: slot));
      await buyer.mockConfirmPayment(o.payment!.id, success: true);
      asTam();
      final id = (await studio.myConsultations())
          .singleWhere((c) => c.orderId == o.id)
          .id;
      await studio.confirmConsultation(id);

      asMinhAnh();
      now = slot.subtract(const Duration(hours: 2));
      await expectLater(
          buyer.cancelConsultation(id), throwsA(apiError(409, 'too_late')));
    });

    test('packages: content needs an Active grant (180 days for a course)',
        () async {
      await expectLater(buyer.getServiceContent('svc_tam_vip'),
          throwsA(apiError(403, 'no_access')));
      // Seeded: Minh Anh owns Tâm's course.
      final seeded = await buyer.getServiceContent('svc_tam_course');
      expect(seeded.contentUrl, startsWith('https://'));
      expect(seeded.summary, contains('## Khoá meal prep chay 4 tuần'));

      final order = await buyer.createOrder(
          const CreateOrderRequestDto(serviceId: 'svc_khoa_course'));
      expect(order.consultation, isNull);
      await buyer.mockConfirmPayment(order.payment!.id, success: true);
      final paid = await buyer.getOrder(order.id);
      expect(paid.accessGrant!.expiresAt, now.add(const Duration(days: 180)));
      expect(paid.canOpenContent(now), isTrue);
      final content = await buyer.getServiceContent('svc_khoa_course');
      expect(content.title, 'Khoá tăng cơ thuần chay 8 tuần');

      now = now.add(const Duration(days: 181));
      await expectLater(buyer.getServiceContent('svc_khoa_course'),
          throwsA(apiError(403, 'no_access')),
          reason: 'expired grant');
    });

    test('a failed payment can be retried with a new QR', () async {
      final order = await buyer
          .createOrder(const CreateOrderRequestDto(serviceId: 'svc_tam_vip'));
      final failed =
          await buyer.mockConfirmPayment(order.payment!.id, success: false);
      expect(failed.status, PaymentStatus.failed);
      final retry = await buyer.renewPayment(order.id);
      expect(retry.status, PaymentStatus.pending);
      expect(retry.transactionRef, isNot(failed.transactionRef));
    });

    test('orders and consultations are per user; guests get 401', () async {
      final orders = await buyer.myOrders();
      expect(orders.map((o) => o.userId).toSet(), {'u_me'});
      expect(orders.map((o) => o.id),
          containsAll(['od_seed_1', 'od_seed_2', 'od_me_course']));
      final vip = orders.singleWhere((o) => o.id == 'od_me_vip_ha');
      expect(vip.status, OrderStatus.pending);
      expect(vip.payment!.status, PaymentStatus.pending);
      expect((await buyer.myOrders(status: OrderStatus.paid)).length, 3);

      asTam();
      expect(await buyer.myOrders(), isEmpty);
      expect(await buyer.myConsultations(), isEmpty);

      userId = null;
      await expectLater(buyer.myOrders(), throwsA(apiError(401)));
    });
  });

  group('PaymentScreen', () {
    late String orderId;

    setUp(() => MockCommerceDb.reset());

    Future<void> pumpPayment(WidgetTester tester,
        {bool showMockControls = true}) async {
      SharedPreferences.setMockInitialValues({
        'vl.access_token': 'mock.jwt',
        'vl.display_name': 'Minh Anh',
        'vl.user_id': 'u_me',
        'vl.role': 'User',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = MockCommerceRepository(
          currentUserId: () => 'u_me', currentUserName: () => 'Minh Anh');
      final slot = MockCommerceDb.instance.freeSlots('u_chef_tam').first;
      orderId = (await tester.runAsync(() => repo.createOrder(
              CreateOrderRequestDto(
                  serviceId: 'svc_tam_consult', startAt: slot))))!
          .id;
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentScreen(
                          orderId: orderId, showMockControls: showMockControls),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // mock latency
    }

    testWidgets('shows amount, reference and countdown; pays via the mock',
        (tester) async {
      await pumpPayment(tester);
      expect(find.text('350.000đ'), findsOneWidget);
      expect(find.textContaining(RegExp(r'Mã giao dịch: VL\d{10}')),
          findsOneWidget);
      expect(find.textContaining('Mã hết hạn sau 1'), findsOneWidget);
      expect(find.text('Mã QR mô phỏng'), findsOneWidget);
      expect(find.text('Đang chờ thanh toán…'), findsOneWidget);

      await tester.ensureVisible(find.text('Mô phỏng đã thanh toán'));
      await tester.tap(find.text('Mô phỏng đã thanh toán'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      expect(find.text('Xem lịch tư vấn'), findsOneWidget);
      expect(find.text('Đơn hàng của tôi'), findsOneWidget);

      // Disposing leaves no timers behind (the test fails otherwise).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('leaving while pending asks first; timers stop on dispose',
        (tester) async {
      await pumpPayment(tester);
      await tester.pageBack();
      await tester.pump();
      expect(find.text('Rời màn thanh toán?'), findsOneWidget);
      expect(find.text('Bạn có thể thanh toán tiếp trong Đơn hàng của tôi.'),
          findsOneWidget);
      await tester.tap(find.text('Rời đi'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // no poll fires
    });

    testWidgets('no mock buttons when showMockControls is false',
        (tester) async {
      await pumpPayment(tester, showMockControls: false);
      expect(find.text('350.000đ'), findsOneWidget);
      expect(find.text('Mô phỏng đã thanh toán'), findsNothing);
      expect(find.text('Mô phỏng thất bại'), findsNothing);
      expect(find.text('Mã QR mô phỏng'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
