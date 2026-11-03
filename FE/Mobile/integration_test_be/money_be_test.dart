// integration_test_be/money_be_test.dart
//
// The money paths through the Flutter adapters (RemoteBooking…, RemoteCommerce…,
// RemoteMemberWallet…, RemoteChefWallet…), on the real money server, with real
// login tokens. Needs the BE with `Payment__Provider=Sandbox`; without a gateway
// only the group at the end runs. Admin routes and the sandbox confirmation have
// no adapter in the app, so those are plain requests with the admin's token.
//
// The money rules (BE_API_VA_LOI.md 5.5): payment held, confirmed from the last
// plan day, 7 days of hold, the chef gets 90 %, one wallet per user.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/booking/data/booking_api_service.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/chef/data/chef_api_service.dart';
import 'package:veganlife_mobile/features/chef_studio/data/chef_studio_api_service.dart';
import 'package:veganlife_mobile/features/chef_studio/data/chef_wallet_api_service.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/chef_studio_models.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/commerce/data/commerce_api_service.dart';
import 'package:veganlife_mobile/features/commerce/data/member_wallet_api_service.dart';
import 'package:veganlife_mobile/features/commerce/domain/commerce_status.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';

import 'be_harness.dart';

/// A member and what the app talks to for them.
class _Member {
  _Member(this.user)
      : bookings = RemoteBookingApiService(user.dio),
        commerce = RemoteCommerceApiService(user.dio),
        wallet = RemoteMemberWalletApiService(user.dio);

  final BeUser user;
  final BookingApiService bookings;
  final CommerceApiService commerce;
  final MemberWalletApiService wallet;

  Future<int> balance() async => (await wallet.getWallet()).available;
}

DateTime _vnToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(now.year, now.month, now.day);
}

const _bank = BankAccountDto(
  bankName: 'Vietcombank',
  accountNumber: '0123456789',
  accountHolder: 'NGUYEN VAN THU',
);

int _fee(int gross) => (gross + 5) ~/ 10;

const _longNote = 'Ban quản trị đã xem xét đủ bằng chứng của hai bên.';

Future<void> main() async {
  final be = await BeHarness.start();

  /// Whether the server opens a QR at all; decided in the first `setUpAll`.
  Future<bool> hasGateway(
      BookingApiService member, BookingApiService chef, String chefId) async {
    final booking = await member.createBooking(_request(chefId));
    final offered = await chef.sendOffer(
        booking.id, _offer(100000, booking.startDate, booking.planDays));
    await member.respondToOffer(booking.id, offered.currentOffer!.id,
        accept: true);
    try {
      await member.startPayment(booking.id);
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 503) return false;
      rethrow;
    } finally {
      await member.cancel(booking.id, 'Chỉ thử xem có cổng thanh toán không.');
    }
  }

  group('money', skip: be.skipReason, () {
    late BeUser chefUser;
    late BookingApiService asChef;
    late ChefWalletApiService chefWallet;
    late String admin;
    late String? noGateway;

    Future<_Member> newMember([String name = 'FE IT Money']) async =>
        _Member(await be.newUser(name: name));

    Future<RawResponse> asAdmin(String method, String path, {Object? data}) =>
        rawRequest(method, path, token: admin, data: data);

    /// Member asks, chef quotes [price], member accepts.
    Future<BookingDto> agree(
      _Member m, {
      int price = 300000,
      BookingType type = BookingType.oneShot,
      int days = 3,
    }) async {
      final booking = await m.bookings
          .createBooking(_request(chefUser.id, type: type, days: days));
      final offered = await asChef.sendOffer(
          booking.id,
          _offer(price, booking.startDate, days,
              type: type, note: 'Báo giá cho kế hoạch của bạn'));
      return m.bookings
          .respondToOffer(booking.id, offered.currentOffer!.id, accept: true);
    }

    /// Opens the QR and has the admin confirm it, as the gateway would.
    Future<BookingDto> payBySandbox(_Member m, BookingDto booking) async {
      final payment = await m.commerce.renewPayment(booking.paymentOrderId!);
      final confirmed = await asAdmin(
          'POST', '/payments/${payment.id}/sandbox-confirm',
          data: {'success': true});
      expect(confirmed.status, 200);
      return m.bookings.getBooking(booking.id);
    }

    Future<BookingDto> paidBooking(_Member m,
            {int price = 300000,
            BookingType type = BookingType.oneShot,
            int days = 3}) async =>
        payBySandbox(m, await agree(m, price: price, type: type, days: days));

    Future<void> saveDay(String id, int dayIndex) => asChef.savePlanDay(
        id, dayIndex, PlanDayRequestDto(meals: _meals(dayIndex)));

    /// Chef: writes every day and sends them, as the plan type allows.
    Future<void> deliver(BookingDto booking) async {
      for (var day = 1; day <= booking.planDays; day++) {
        await saveDay(booking.id, day);
        if (booking.bookingType == BookingType.dailyFeedback) {
          await asChef.sendPlanDay(booking.id, day);
        }
      }
      if (booking.bookingType == BookingType.oneShot) {
        await asChef.sendWholePlan(booking.id);
      }
    }

    /// A member with [amount] in the wallet: a paid booking cancelled before
    /// anything was delivered.
    Future<void> fundWallet(_Member m, int amount) async {
      final paid = await paidBooking(m, price: amount);
      await m.bookings.cancel(paid.id, 'Mình đổi lịch nên chưa cần nữa.');
    }

    setUpAll(() async {
      chefUser = await be.seedUser(seedChefEmail);
      asChef = RemoteBookingApiService(chefUser.dio);
      chefWallet = RemoteChefWalletApiService(chefUser.dio);
      admin = await be.adminToken();
      final probe = await newMember('FE IT Money Probe');
      noGateway = await hasGateway(probe.bookings, asChef, chefUser.id)
          ? null
          : 'No gateway on this BE: run it with Payment__Provider=Sandbox.';
    });

    group('with the sandbox gateway', () {
      void gatewayTest(String name, Future<void> Function() body) =>
          beTest(name, () async {
            if (noGateway != null) {
              markTestSkipped(noGateway!);
              return;
            }
            await body();
          });

      gatewayTest('request, quote, counter, accept; both sides read the same',
          () async {
        final m = await newMember();
        final created =
            await m.bookings.createBooking(_request(chefUser.id, days: 5));
        expect(created.status, BookingStatus.requested);
        expect(created.chef.id, chefUser.id);
        expect(created.member.id, m.user.id);
        expect(created.planDays, 5);
        expect(created.paymentOrderId, isNull);
        expect(created.partyOf(m.user.id), BookingParty.member);
        expect(created.partyOf(chefUser.id), BookingParty.chef);

        expect(
            (await asChef.chefInbox()).map((b) => b.id), contains(created.id));
        expect((await m.bookings.myBookings()).single.id, created.id);

        final quote = await asChef.sendOffer(created.id,
            _offer(500000, created.startDate, 5, note: 'Giá trọn gói'));
        expect(quote.status, BookingStatus.negotiating);
        expect(quote.currentOffer!.proposedBy, BookingParty.chef);
        expect(quote.currentOffer!.status, OfferStatus.open);

        await expectApiError(
            asChef.respondToOffer(created.id, quote.currentOffer!.id,
                accept: true),
            status: 409,
            code: 'own_offer');

        final counter = await m.bookings
            .sendOffer(created.id, _offer(450000, created.startDate, 5));
        expect(counter.currentOffer!.proposedBy, BookingParty.member);
        await expectApiError(
            m.bookings.respondToOffer(created.id, quote.currentOffer!.id,
                accept: true),
            status: 409,
            code: 'offer_closed');

        final accepted = await asChef
            .respondToOffer(created.id, counter.currentOffer!.id, accept: true);
        expect(accepted.status, BookingStatus.awaitingPayment);
        final contract = accepted.contract!;
        expect(contract.price, 450000);
        expect(contract.fee, 45000);
        expect(contract.planDays, 5);
        expect(contract.feeRate, 0.1);
        expect(contract.holdDays, 7);
        expect(contract.startDate, created.startDate);
        expect(
            contract.endDate, created.startDate.add(const Duration(days: 4)));
        expect(contract.paymentDueAt.isAfter(DateTime.now()), isTrue);
        expect(accepted.paymentOrderId, isNotNull,
            reason: 'the payment screen opens from this');

        await expectApiError(
            asChef.respondToOffer(created.id, counter.currentOffer!.id,
                accept: true),
            status: 409,
            code: 'offer_closed');

        final order = await m.commerce.getOrder(accepted.paymentOrderId!);
        expect(order.status, OrderStatus.pending);
        expect(order.amount, 450000);
        expect(order.bookingId, created.id);
        expect(order.payment, isNull, reason: 'no QR until the member asks');
        expect(order.escrow, isNull);
        expect(order.booking.chefName, chefUser.name);
        expect(order.booking.planDays, 5);

        final messages = await m.bookings.messages(created.id);
        expect(
            messages.where((x) => x.kind == MessageKind.offer), hasLength(2));
        expect(messages.first.createdAt.isAfter(DateTime(2020)), isTrue);
        final sent = await m.bookings.sendMessage(
            created.id, const SendMessageRequestDto(body: 'Cảm ơn bạn nhiều'));
        expect(sent.body, 'Cảm ơn bạn nhiều');
        expect(sent.senderRole, BookingParty.member);
        expect(
            (await asChef.messages(created.id, after: messages.last.createdAt))
                .map((x) => x.id),
            contains(sent.id));
        expect((await m.bookings.getBooking(created.id)).status,
            BookingStatus.awaitingPayment);
      });

      gatewayTest(
          'paying by the gateway: the QR is reused, a failure gives a new one, '
          'and it says it is a sandbox', () async {
        final m = await newMember();
        final booking = await agree(m);
        final orderId = booking.paymentOrderId!;

        final first = await m.commerce.renewPayment(orderId);
        expect(first.status, PaymentStatus.pending);
        expect(first.provider, 'Sandbox');
        expect(first.qrCodeUrl, isNull, reason: 'no real QR, so no picture');
        expect(first.amount, 300000);
        expect(first.expiresAt!.isAfter(DateTime.now()), isTrue);
        expect(first.transactionRef, isNotEmpty);

        expect((await m.commerce.renewPayment(orderId)).id, first.id);
        final viaBooking = await m.bookings.startPayment(booking.id);
        expect(viaBooking.id, orderId);
        expect(viaBooking.payment!.id, first.id);
        expect(viaBooking.status, OrderStatus.pending);

        // Only the buyer (Payment:SandboxSelfConfirm, the demo has nobody playing
        // the gateway) and an admin confirm, and only the buyer reads.
        final byChef = await chefUser.raw(
            'POST', '/payments/${first.id}/sandbox-confirm',
            data: {'success': true});
        expect(byChef.status, 404);
        final stranger = await newMember('FE IT Money Stranger');
        await expectApiError(
            stranger.commerce.mockConfirmPayment(first.id, success: true),
            status: 404);
        await expectApiError(stranger.commerce.getPayment(first.id),
            status: 404);
        await expectApiError(stranger.commerce.getOrder(orderId), status: 404);
        await expectApiError(stranger.bookings.getBooking(booking.id),
            status: 404);
        await expectApiError(stranger.commerce.renewPayment(orderId),
            status: 404);
        await expectApiError(asChef.startPayment(booking.id),
            status: 403, code: 'wrong_party');

        final failed = await asAdmin(
            'POST', '/payments/${first.id}/sandbox-confirm',
            data: {'success': false});
        expect(failed.status, 200);
        expect((await m.commerce.getPayment(first.id)).status,
            PaymentStatus.failed);
        var order = await m.commerce.getOrder(orderId);
        expect(order.status, OrderStatus.pending, reason: 'not paid');
        expect(order.escrow, isNull);
        expect((await m.bookings.getBooking(booking.id)).status,
            BookingStatus.awaitingPayment);

        final second = await m.commerce.renewPayment(orderId);
        expect(second.id, isNot(first.id));
        expect(second.status, PaymentStatus.pending);

        // The button of the payment screen.
        final confirmed =
            await m.commerce.mockConfirmPayment(second.id, success: true);
        expect(confirmed.status, PaymentStatus.paid);
        expect((await m.commerce.getPayment(second.id)).status,
            PaymentStatus.paid);
        order = await m.commerce.getOrder(orderId);
        expect(order.status, OrderStatus.paid);
        expect(order.payment!.paidAt, isNotNull);
        expect(order.escrow!.status, EscrowStatus.held);
        expect(order.escrow!.amount, 300000);
        expect(order.escrow!.releaseAt, isNull, reason: 'no date until done');
        expect(order.escrow!.completedAt, isNull);

        final active = await m.bookings.getBooking(booking.id);
        expect(active.status, BookingStatus.active);
        expect(active.canCancelPaid, isTrue);

        // A second tap on anything that pays is refused, and nothing moves.
        await expectApiError(m.commerce.renewPayment(orderId),
            status: 409, code: 'not_awaiting_payment');
        await expectApiError(m.bookings.startPayment(booking.id),
            status: 409, code: 'not_awaiting_payment');
        await expectApiError(m.commerce.payWithWallet(orderId),
            status: 409, code: 'not_awaiting_payment');
        expect(await m.balance(), 0);
      });

      gatewayTest(
          'whole path: deliver, too early, confirm on the last day, 7 days of '
          'hold, the chef gets 90 %', () async {
        final m = await newMember();
        final before = await chefWallet.getWallet();
        final booking = await paidBooking(m, price: 333335);
        final net = 333335 - _fee(333335);
        expect(_fee(333335), 33334, reason: 'half rounds up');
        final paidWallet = await chefWallet.getWallet();
        expect(paidWallet.pending, before.pending + net);
        expect(paidWallet.available, before.available);

        final row = (await chefWallet.transactions())
            .singleWhere((t) => t.bookingId == booking.id);
        expect(row.type, WalletEntryType.income);
        expect(row.status, LedgerStatus.held);
        expect(row.net, net);
        expect(row.gross, 333335);
        expect(row.fee, 33334);
        expect(row.releaseAt, isNull);

        // Nothing delivered: nothing to confirm.
        await expectApiError(asChef.confirmCompletion(booking.id),
            status: 409, code: 'plan_not_delivered');
        await expectApiError(asChef.sendWholePlan(booking.id),
            status: 409, code: 'day_incomplete');
        await deliver(booking);
        var seen = await asChef.getBooking(booking.id);
        expect(seen.deliveredDays, 3);
        expect(seen.fullyDelivered, isTrue);
        final plan = await m.bookings.plan(booking.id);
        expect(plan, hasLength(3));
        expect(plan.every((d) => d.isSent), isTrue);
        expect(plan.first.meals.first.recipe.name, 'Phở chay ngày 1');
        expect(plan.first.meals.first.recipe.calories, 450);
        expect(plan.first.meals.first.slot, MealSlot.lunch);

        // Delivered, but the plan hasn't reached its last day.
        expect(seen.canConfirmCompletion(DateTime.now()), isFalse);
        await expectApiError(asChef.confirmCompletion(booking.id),
            status: 409, code: 'plan_not_delivered');

        // Too late to cancel for a refund once a day is out.
        await expectApiError(
            m.bookings.cancel(booking.id, 'Muốn huỷ sau khi đã nhận kế hoạch.'),
            status: 409,
            code: 'plan_started');

        await timeTravel(booking.id, days: 3);
        seen = await asChef.getBooking(booking.id);
        expect(seen.canConfirmCompletion(DateTime.now()), isTrue);
        final done = await asChef.confirmCompletion(booking.id);
        expect(done.status, BookingStatus.ended);
        expect(done.autoCompleted, isFalse);
        expect(done.completedAt, isNotNull);
        expect(done.escrow!.status, EscrowStatus.held);
        expect(done.escrow!.completedAt, done.completedAt);
        expect(done.escrow!.releaseAt,
            done.completedAt!.add(const Duration(days: 7)));

        // Double tap and reload.
        await expectApiError(asChef.confirmCompletion(booking.id),
            status: 409, code: 'not_active');
        final reload = await m.bookings.getBooking(booking.id);
        expect(reload.status, BookingStatus.ended);
        expect(reload.escrow!.releaseAt, done.escrow!.releaseAt);
        final ended = await chefWallet.getWallet();
        expect(ended.pending, before.pending + net);
        expect(ended.available, before.available);
        expect(
            (await chefWallet.transactions())
                .singleWhere((t) => t.bookingId == booking.id)
                .releaseAt,
            done.escrow!.releaseAt);

        // 7 days later: released on the next read, once.
        await timeTravel(booking.id, days: 8);
        final released = await m.bookings.getBooking(booking.id);
        expect(released.status, BookingStatus.completed);
        expect(released.escrow!.status, EscrowStatus.released);
        expect(released.escrow!.releasedAmount, 333335);
        expect(released.escrow!.feeAmount, 33334);
        expect(released.escrow!.releasedAt, released.escrow!.releaseAt,
            reason: 'the date of the rule, not of the job');
        final paidOut = await chefWallet.getWallet();
        expect(paidOut.available, before.available + net);
        expect(paidOut.pending, before.pending);
        await m.bookings.getBooking(booking.id);
        expect(
            (await chefWallet.getWallet()).available, before.available + net);
        final income = (await chefWallet.transactions())
            .singleWhere((t) => t.bookingId == booking.id);
        expect(income.status, LedgerStatus.available);
        expect(income.net, net);

        // Too late for a complaint now.
        await expectApiError(m.bookings.fileComplaint(booking.id, _complaint()),
            status: 409, code: 'not_open');
      });

      gatewayTest('daily plan: in order, feedback from its day, not the whole',
          () async {
        final m = await newMember();
        final booking = await paidBooking(m,
            price: 360000, type: BookingType.dailyFeedback);
        await expectApiError(asChef.sendPlanDay(booking.id, 1),
            status: 409, code: 'day_incomplete');
        await saveDay(booking.id, 2);
        await expectApiError(asChef.sendPlanDay(booking.id, 2),
            status: 409, code: 'previous_day_unsent');
        await saveDay(booking.id, 1);
        await expectApiError(asChef.sendWholePlan(booking.id),
            status: 409, code: 'daily');
        final sent = await asChef.sendPlanDay(booking.id, 1);
        expect(sent.isSent, isTrue);
        expect(sent.sentAt, isNotNull);
        await expectApiError(asChef.sendPlanDay(booking.id, 1),
            status: 409, code: 'day_sent');
        await expectApiError(
            asChef.savePlanDay(
                booking.id, 1, PlanDayRequestDto(meals: _meals(1))),
            status: 409,
            code: 'day_sent');
        expect((await m.bookings.plan(booking.id)).where((d) => d.isSent),
            hasLength(1));
        const feedback = DayFeedbackDto(
            rating: 4, adherence: Adherence.partly, body: 'Ngon');
        await expectApiError(
            m.bookings.sendDayFeedback(booking.id, 1, feedback),
            status: 409,
            code: 'day_not_started');
        await expectApiError(
            m.bookings.sendDayFeedback(booking.id, 2, feedback),
            status: 409,
            code: 'day_not_sent');

        await timeTravel(booking.id, days: 1);
        final answered =
            await m.bookings.sendDayFeedback(booking.id, 1, feedback);
        expect(answered.feedback!.rating, 4);
        expect(answered.feedback!.adherence, Adherence.partly);
        final read = await asChef.plan(booking.id);
        expect(read.first.feedback!.body, 'Ngon');
        // Cancel for a refund is over: a day went out.
        await expectApiError(
            m.bookings.cancel(booking.id, 'Đổi ý rồi mình huỷ.'),
            status: 409,
            code: 'plan_started');
      });

      gatewayTest('a plan delivered in time completes by itself, once',
          () async {
        final m = await newMember();
        final booking = await paidBooking(m);
        await deliver(booking);
        // End date (start + 2, start is tomorrow) + 3 days at 23:59 VN is over.
        await timeTravel(booking.id, days: 7);
        final auto = await m.bookings.getBooking(booking.id);
        expect(auto.status, BookingStatus.ended);
        expect(auto.autoCompleted, isTrue);
        final endVn = auto.contract!.endDate;
        final expected =
            DateTime.utc(endVn.year, endVn.month, endVn.day + 3, 16, 59);
        expect(auto.completedAt!.toUtc(), expected,
            reason: 'the time of the rule, 23:59 in Vietnam, not of the job');
        expect(auto.escrow!.releaseAt!.toUtc(),
            expected.add(const Duration(days: 7)));
        await expectApiError(asChef.confirmCompletion(booking.id),
            status: 409, code: 'not_active');
        expect(
            (await asChef.messages(booking.id))
                .where((x) => x.kind == MessageKind.system),
            isNotEmpty);
      });

      gatewayTest(
          'a day sent after the deadline: no auto-completion, the chef still '
          'confirms', () async {
        final m = await newMember();
        final booking = await paidBooking(m);
        await saveDay(booking.id, 1);
        await timeTravel(booking.id, days: 8);
        expect((await m.bookings.getBooking(booking.id)).status,
            BookingStatus.active);
        await deliver(booking);
        final late = await m.bookings.getBooking(booking.id);
        expect(late.status, BookingStatus.active);
        expect(late.autoCompleted, isFalse);
        expect(late.deliveredAfterAutoComplete(DateTime.now()), isTrue);
        final done = await asChef.confirmCompletion(booking.id);
        expect(done.status, BookingStatus.ended);
        expect(done.autoCompleted, isFalse);
      });

      gatewayTest(
          'days missing past the deadline: it stays held, an admin sees it '
          'stuck and decides', () async {
        final m = await newMember();
        final booking = await paidBooking(m);
        await saveDay(booking.id, 1);
        await timeTravel(booking.id, days: 8);
        final stuck = await m.bookings.getBooking(booking.id);
        expect(stuck.status, BookingStatus.active);
        expect(stuck.escrow!.status, EscrowStatus.held);
        expect(stuck.escrow!.releaseAt, isNull);
        expect(stuck.overdueUndelivered(DateTime.now()), isTrue);

        final holds =
            await asAdmin('GET', '/admin/escrow/holds?search=${booking.id}');
        final hold =
            holds.dataList.singleWhere((h) => h['bookingId'] == booking.id);
        expect(hold['isStuck'], isTrue);
        final resolved = await asAdmin(
            'POST', '/admin/escrow/holds/${hold['id']}/resolve',
            data: {
              'decision': 'RefundMember',
              'note': _longNote,
            });
        expect(resolved.status, 200);
        final again = await asAdmin(
            'POST', '/admin/escrow/holds/${hold['id']}/resolve',
            data: {
              'decision': 'ReleaseToChef',
              'note': _longNote,
            });
        expect(again.status, 409);
        expect(again.json['code'], 'not_stuck');

        final after = await m.bookings.getBooking(booking.id);
        expect(after.status, BookingStatus.cancelled);
        expect(after.isAdminResolved, isTrue);
        expect(after.escrow!.status, EscrowStatus.refunded);
        expect(after.escrow!.refundedAmount, 300000);
        expect(await m.balance(), 300000);
        expect((await m.commerce.getOrder(after.paymentOrderId!)).status,
            OrderStatus.refunded);
        await expectApiError(m.bookings.fileComplaint(booking.id, _complaint()),
            status: 409, code: 'not_open');
      });

      Future<({_Member member, BookingDto booking, Map<String, dynamic> row})>
          disputed() async {
        final m = await newMember();
        final booking = await paidBooking(m, price: 400000);
        await deliver(booking);
        final filed = await m.bookings.fileComplaint(booking.id, _complaint());
        expect(filed.status, BookingStatus.disputed);
        expect(filed.complaint!.isOpen, isTrue);
        expect(filed.complaint!.requestedAmount, 400000);
        expect(filed.complaint!.evidence, hasLength(1));
        expect(filed.escrow!.status, EscrowStatus.frozen);
        final queue = await asAdmin(
            'GET', '/admin/complaints?status=Open&search=${m.user.email}');
        return (
          member: m,
          booking: filed,
          row: queue.dataList.singleWhere((c) => c['bookingId'] == booking.id),
        );
      }

      gatewayTest(
          'a complaint freezes the money; the chef answers; refund decided',
          () async {
        final d = await disputed();
        final m = d.member;
        final id = d.booking.id;
        final walletBefore = await chefWallet.getWallet();
        final row = (await chefWallet.transactions())
            .singleWhere((t) => t.bookingId == id);
        expect(row.status, LedgerStatus.frozen);
        expect(row.complaintId, d.row['id']);

        await expectApiError(m.bookings.fileComplaint(id, _complaint()),
            status: 409, code: 'not_open');
        await expectApiError(asChef.confirmCompletion(id),
            status: 409, code: 'has_open_complaint');
        await expectApiError(
            m.bookings.cancel(id, 'Muốn huỷ khi đang khiếu nại.'),
            status: 409);

        final answer = await asChef.respondToComplaint(
            id,
            const ComplaintResponseRequestDto(
                text: 'Tôi đã giao đúng thực đơn đã thoả thuận với bạn.'));
        expect(answer.chefResponse, contains('đúng thực đơn'));
        expect(answer.chefRespondedAt, isNotNull);
        expect((await m.bookings.getBooking(id)).complaint!.chefResponse,
            contains('đúng thực đơn'));

        final detail = await asAdmin('GET', '/admin/complaints/${d.row['id']}');
        expect(detail.status, 200);
        final tooShort = await asAdmin(
            'POST', '/admin/complaints/${d.row['id']}/decision',
            data: {'decision': 'RefundMember', 'note': 'ngắn'});
        expect(tooShort.status, 400);
        expect(tooShort.json['code'], 'note_too_short');
        final badAmount = await asAdmin(
            'POST', '/admin/complaints/${d.row['id']}/decision',
            data: {
              'decision': 'Split',
              'refundAmount': 400000,
              'note': _longNote,
            });
        expect(badAmount.status, 400);
        expect(badAmount.json['code'], 'invalid_refund_amount');
        expect(await m.balance(), 0, reason: 'refused: nothing moved');

        final decided = await asAdmin(
            'POST', '/admin/complaints/${d.row['id']}/decision',
            data: {'decision': 'RefundMember', 'note': _longNote});
        expect(decided.status, 200);

        final after = await m.bookings.getBooking(id);
        expect(after.complaint!.status, ComplaintStatus.resolved);
        expect(after.complaint!.decision, ComplaintDecision.refundMember);
        expect(after.complaint!.adminNote, _longNote);
        expect(after.escrow!.status, EscrowStatus.refunded);
        expect(after.escrow!.refundedAmount, 400000);
        expect(after.status, BookingStatus.resolved);
        expect(await m.balance(), 400000);
        final order = await m.commerce.getOrder(after.paymentOrderId!);
        expect(order.status, OrderStatus.refunded);
        final refundRow = (await m.wallet.transactions())
            .singleWhere((t) => t.bookingId == id);
        expect(refundRow.type, WalletEntryType.refund);
        expect(refundRow.net, 400000);

        final walletAfter = await chefWallet.getWallet();
        expect(walletAfter.frozen, walletBefore.frozen - 360000);
        expect(walletAfter.available, walletBefore.available);
        expect(
            (await chefWallet.transactions())
                .singleWhere((t) => t.bookingId == id)
                .status,
            LedgerStatus.reversed);

        final twice = await asAdmin(
            'POST', '/admin/complaints/${d.row['id']}/decision',
            data: {'decision': 'ReleaseToChef', 'note': _longNote});
        expect(twice.status, 409);
        expect(twice.json['code'], 'already_decided');
        expect(await m.balance(), 400000);
        // Reload: nothing is paid twice.
        await m.bookings.getBooking(id);
        await m.wallet.getWallet();
        expect(await m.balance(), 400000);
      });

      gatewayTest('a split: the member gets X, the chef 90 % of the rest',
          () async {
        final d = await disputed();
        final m = d.member;
        final before = await chefWallet.getWallet();
        const refund = 100000;
        final decided = await asAdmin(
            'POST', '/admin/complaints/${d.row['id']}/decision',
            data: {
              'decision': 'Split',
              'refundAmount': refund,
              'note': _longNote,
            });
        expect(decided.status, 200);
        final after = await m.bookings.getBooking(d.booking.id);
        expect(after.escrow!.status, EscrowStatus.partiallyRefunded);
        expect(after.escrow!.refundedAmount, refund);
        expect(after.escrow!.releasedAmount, 300000, reason: 'price - X');
        expect(after.escrow!.feeAmount, 30000, reason: "on the chef's part");
        expect(after.complaint!.refundAmount, refund);
        expect(await m.balance(), refund);
        final wallet = await chefWallet.getWallet();
        expect(wallet.available, before.available + 270000);
        expect(wallet.frozen, before.frozen - 360000);
        expect((await m.commerce.getOrder(after.paymentOrderId!)).status,
            OrderStatus.partiallyRefunded);
        final row = (await chefWallet.transactions())
            .singleWhere((t) => t.bookingId == d.booking.id);
        expect(row.status, LedgerStatus.available);
        expect(row.net, 270000);
      });

      gatewayTest('released to the chef: 90 %, and two admins: one wins',
          () async {
        final d = await disputed();
        final m = d.member;
        final before = await chefWallet.getWallet();
        final path = '/admin/complaints/${d.row['id']}/decision';
        final both = await Future.wait([
          asAdmin('POST', path,
              data: {'decision': 'ReleaseToChef', 'note': _longNote}),
          asAdmin('POST', path,
              data: {'decision': 'RefundMember', 'note': _longNote}),
        ]);
        expect(both.map((r) => r.status).toList()..sort(), [200, 409]);
        final refused = both.singleWhere((r) => r.status == 409);
        expect(refused.json['code'], 'already_decided');
        final after = await m.bookings.getBooking(d.booking.id);
        final wallet = await chefWallet.getWallet();
        final balance = await m.balance();
        if (after.complaint!.decision == ComplaintDecision.releaseToChef) {
          expect(after.escrow!.status, EscrowStatus.released);
          expect(after.escrow!.releasedAmount, 400000);
          expect(after.escrow!.feeAmount, 40000);
          expect(wallet.available, before.available + 360000);
          expect(balance, 0);
        } else {
          expect(after.escrow!.status, EscrowStatus.refunded);
          expect(wallet.available, before.available);
          expect(balance, 400000);
        }
        expect(wallet.frozen, before.frozen - 360000);
      });

      gatewayTest('cancelling before paying costs nothing; a chef can decline',
          () async {
        final m = await newMember();
        final waiting = await agree(m);
        final cancelled = await m.bookings
            .cancel(waiting.id, 'Mình đổi lịch nên chưa cần nữa.');
        expect(cancelled.status, BookingStatus.cancelled);
        expect(cancelled.cancelReason, 'Mình đổi lịch nên chưa cần nữa.');
        expect(cancelled.escrow, isNull);
        expect(await m.balance(), 0);
        await expectApiError(m.bookings.startPayment(waiting.id),
            status: 409, code: 'not_awaiting_payment');

        final asked = await m.bookings.createBooking(_request(chefUser.id));
        await expectApiError(
            m.bookings.decline(asked.id, 'Đầy lịch rồi nhé bạn'),
            status: 403);
        await expectApiError(asChef.decline(asked.id, 'ngắn'), status: 400);
        final declined =
            await asChef.decline(asked.id, 'Lịch của mình đã kín trong tuần.');
        expect(declined.status, BookingStatus.declined);
        expect(declined.declineReason, 'Lịch của mình đã kín trong tuần.');
        await expectApiError(
            asChef.decline(asked.id, 'Lịch của mình đã kín trong tuần.'),
            status: 409,
            code: 'invalid_status');
        expect((await m.bookings.getBooking(asked.id)).status,
            BookingStatus.declined);
      });

      gatewayTest('roles and validation', () async {
        final m = await newMember();
        await expectApiError(m.bookings.createBooking(_request(m.user.id)),
            status: 404);
        await expectApiError(
            m.bookings.createBooking(_request('aaaaaaaaaaaaaaaaaaaaaaaa')),
            status: 404);
        await expectApiError(
            RemoteBookingApiService(chefUser.dio)
                .createBooking(_request(chefUser.id)),
            status: 409,
            code: 'self_booking');
        await expectApiError(
            m.bookings.createBooking(_request(chefUser.id, needs: 'ngắn')),
            status: 400);
        await expectApiError(m.bookings.chefInbox(),
            status: 403, code: 'not_chef');
        await expectApiError(RemoteChefWalletApiService(m.user.dio).getWallet(),
            status: 403, code: 'not_chef');
        await expectApiError(
            RemoteBookingApiService(be.guestDio()).myBookings(),
            status: 401);
        await expectApiError(
            RemoteMemberWalletApiService(be.guestDio()).getWallet(),
            status: 401);
        await expectApiError(
            RemoteCommerceApiService(be.guestDio()).getOrder('x'),
            status: 401);
      });

      gatewayTest(
          'paying from the wallet: covers it or not, one debit on a double tap',
          () async {
        final m = await newMember();
        final poor = await agree(m, price: 200000);
        await expectApiError(m.commerce.payWithWallet(poor.paymentOrderId!),
            status: 409, code: 'insufficient_balance');
        await m.bookings.cancel(poor.id, 'Mình đổi lịch nên chưa cần nữa.');

        await fundWallet(m, 500000);
        expect(await m.balance(), 500000);
        final refund = (await m.wallet.transactions()).first;
        expect(refund.type, WalletEntryType.refund);
        expect(refund.net, 500000);

        final booking = await agree(m, price: 200000);
        final orderId = booking.paymentOrderId!;
        final results = await Future.wait([
          for (var i = 0; i < 4; i++)
            m.commerce
                .payWithWallet(orderId)
                .then<Object?>((o) => o, onError: (Object e) => e),
        ]);
        final refused = results.whereType<ApiException>().toList();
        expect(refused, hasLength(lessThanOrEqualTo(3)));
        for (final e in refused) {
          expect(e.statusCode, 409);
          expect(e.code, 'not_awaiting_payment');
        }
        expect(await m.balance(), 300000, reason: 'one debit');

        final order = await m.commerce.getOrder(orderId);
        expect(order.status, OrderStatus.paid);
        expect(order.payment!.provider, 'Wallet');
        expect(order.payment!.status, PaymentStatus.paid);
        expect(order.escrow!.status, EscrowStatus.held);
        final active = await m.bookings.getBooking(booking.id);
        expect(active.status, BookingStatus.active);
        final payment = (await m.wallet.transactions())
            .singleWhere((t) => t.type == WalletEntryType.payment);
        expect(payment.net, -200000);
        expect(payment.bookingId, booking.id);
        expect(payment.orderId, orderId);

        // Cancelled before delivery: the whole price is back, once.
        final back = await m.bookings
            .cancel(booking.id, 'Mình đổi lịch nên chưa cần nữa.');
        expect(back.status, BookingStatus.cancelled);
        expect(back.escrow!.status, EscrowStatus.refunded);
        expect(back.escrow!.refundedAmount, 200000);
        expect(back.escrow!.resolvedBy, isNull);
        expect(back.isAdminResolved, isFalse);
        expect(await m.balance(), 500000);
        await expectApiError(
            m.bookings.cancel(booking.id, 'Mình đổi lịch nên chưa cần nữa.'),
            status: 409);
        expect(await m.balance(), 500000);
      });

      gatewayTest(
          'one balance, four orders at once: only what it covers is paid',
          () async {
        final m = await newMember();
        await fundWallet(m, 250000);
        final orders = [
          for (var i = 0; i < 4; i++) await agree(m, price: 200000),
        ];
        final results = await Future.wait([
          for (final o in orders)
            m.commerce
                .payWithWallet(o.paymentOrderId!)
                .then<Object?>((x) => x, onError: (Object e) => e),
        ]);
        expect(results.whereType<ApiException>(), hasLength(3));
        for (final e in results.whereType<ApiException>()) {
          expect(e.code, 'insufficient_balance');
        }
        expect(await m.balance(), 50000);
      });

      gatewayTest(
          'a member withdraws: bank account, minimum, balance, double tap, an '
          'admin approves or rejects', () async {
        final m = await newMember();
        await expectApiError(
            m.wallet
                .requestWithdrawal(const WithdrawalRequestDto(amount: 100000)),
            status: 409,
            code: 'no_bank_account');
        await fundWallet(m, 900000);
        var wallet = await m.wallet.getWallet();
        expect(wallet.available, 900000);
        expect(wallet.pending, 0);
        expect(wallet.frozen, 0);
        expect(wallet.bankAccount, isNull);

        final saved = await m.wallet.saveBankAccount(_bank);
        expect(saved.bankName, 'Vietcombank');
        wallet = await m.wallet.getWallet();
        expect(wallet.bankAccount!.accountHolder, _bank.accountHolder);
        await expectApiError(
            m.wallet.saveBankAccount(const BankAccountDto(
                bankName: '', accountNumber: '1', accountHolder: '')),
            status: 400);

        await expectApiError(
            m.wallet
                .requestWithdrawal(const WithdrawalRequestDto(amount: 99999)),
            status: 400,
            code: 'amount_too_small');
        await expectApiError(
            m.wallet
                .requestWithdrawal(const WithdrawalRequestDto(amount: 900001)),
            status: 409,
            code: 'insufficient_balance');

        // Double tap.
        final taps = await Future.wait([
          m.wallet
              .requestWithdrawal(const WithdrawalRequestDto(amount: 200000)),
          m.wallet
              .requestWithdrawal(const WithdrawalRequestDto(amount: 200000)),
        ]);
        expect(taps.first.id, taps.last.id);
        final first = taps.first;
        expect(first.status, LedgerStatus.processing);
        expect(first.amount, 200000);
        expect(first.accountNumber, isNot(contains('0123456')));
        wallet = await m.wallet.getWallet();
        expect(wallet.available, 700000);
        expect(wallet.processing, 200000);
        expect(await m.wallet.withdrawals(), hasLength(1));

        final queue = await asAdmin('GET',
            '/admin/withdrawals?status=Processing&search=${m.user.email}');
        expect(queue.dataList.single['id'].toString(), first.id);

        final badRef = await asAdmin(
            'POST', '/admin/withdrawals/${first.id}/complete',
            data: {'transactionRef': 'x'});
        expect(badRef.status, 400);
        expect(badRef.json['code'], 'invalid_transaction_ref');
        final approved = await asAdmin(
            'POST', '/admin/withdrawals/${first.id}/complete',
            data: {'transactionRef': 'VCB-2026-000123'});
        expect(approved.status, 200);
        wallet = await m.wallet.getWallet();
        expect(wallet.available, 700000);
        expect(wallet.processing, 0);
        expect(wallet.withdrawn, 200000);
        final done = (await m.wallet.withdrawals()).single;
        expect(done.status, LedgerStatus.completed);
        expect(done.processedAt, isNotNull);
        final again = await asAdmin(
            'POST', '/admin/withdrawals/${first.id}/reject',
            data: {'reason': 'Thông tin tài khoản chưa khớp'});
        expect(again.status, 409);
        expect(again.json['code'], 'already_processed');

        // Rejected: the money is back, with the reason.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final second = await m.wallet
            .requestWithdrawal(const WithdrawalRequestDto(amount: 300000));
        expect((await m.wallet.getWallet()).available, 400000);
        final short = await asAdmin(
            'POST', '/admin/withdrawals/${second.id}/reject',
            data: {'reason': 'x'});
        expect(short.status, 400);
        expect(short.json['code'], 'reason_too_short');
        final rejected = await asAdmin(
            'POST', '/admin/withdrawals/${second.id}/reject',
            data: {'reason': 'Thông tin tài khoản chưa khớp'});
        expect(rejected.status, 200);
        wallet = await m.wallet.getWallet();
        expect(wallet.available, 700000);
        expect(wallet.processing, 0);
        expect(wallet.withdrawn, 200000);
        final row = (await m.wallet.withdrawals())
            .singleWhere((w) => w.id == second.id);
        expect(row.status, LedgerStatus.rejected);
        expect(row.reason, 'Thông tin tài khoản chưa khớp');

        final rows = await m.wallet.transactions();
        expect(
            rows
                .where((t) => t.type == WalletEntryType.withdrawal)
                .map((t) => t.status),
            containsAll([LedgerStatus.completed, LedgerStatus.rejected]));
        expect(
            rows
                .where((t) => t.type == WalletEntryType.withdrawal)
                .every((t) => t.net < 0),
            isTrue);
        // Reload: the same numbers.
        expect((await m.wallet.getWallet()).available, 700000);

        // Two admins on one request: one wins, and the money follows it.
        final third = await m.wallet
            .requestWithdrawal(const WithdrawalRequestDto(amount: 400000));
        final race = await Future.wait([
          asAdmin('POST', '/admin/withdrawals/${third.id}/complete',
              data: {'transactionRef': 'VCB-2026-000124'}),
          asAdmin('POST', '/admin/withdrawals/${third.id}/reject',
              data: {'reason': 'Thông tin tài khoản chưa khớp'}),
        ]);
        expect(race.map((r) => r.status).toList()..sort(), [200, 409]);
        wallet = await m.wallet.getWallet();
        expect(wallet.processing, 0);
        if (race.first.status == 200) {
          expect(wallet.available, 300000);
          expect(wallet.withdrawn, 600000);
        } else {
          expect(wallet.available, 700000);
          expect(wallet.withdrawn, 200000);
        }
      });

      gatewayTest('a chef withdraws what was released, and only that',
          () async {
        final m = await newMember();
        final booking = await paidBooking(m, price: 500000);
        await deliver(booking);
        await timeTravel(booking.id, days: 3);
        await asChef.confirmCompletion(booking.id);
        final before = await chefWallet.getWallet();
        await timeTravel(booking.id, days: 8);
        await m.bookings.getBooking(booking.id);
        final paid = await chefWallet.getWallet();
        expect(paid.available, before.available + 450000);
        expect(paid.pending, before.pending - 450000);

        await chefWallet.saveBankAccount(_bank);
        await expectApiError(
            chefWallet.requestWithdrawal(
                WithdrawalRequestDto(amount: paid.available + 1)),
            status: 409,
            code: 'insufficient_balance');
        final request = await chefWallet
            .requestWithdrawal(const WithdrawalRequestDto(amount: 150000));
        expect(request.status, LedgerStatus.processing);
        final after = await chefWallet.getWallet();
        expect(after.available, paid.available - 150000);
        expect(after.processing, paid.processing + 150000);
        expect((await chefWallet.withdrawals()).first.id, request.id);
        final rejected = await asAdmin(
            'POST', '/admin/withdrawals/${request.id}/reject',
            data: {'reason': 'Thông tin tài khoản chưa khớp'});
        expect(rejected.status, 200);
        expect((await chefWallet.getWallet()).available, paid.available);

        final month = _vnToday().toIso8601String().substring(0, 7);
        expect(
            (await chefWallet.transactions(month: month))
                .map((t) => t.bookingId),
            contains(booking.id));
        expect(await chefWallet.transactions(month: '2000-01'), isEmpty);
      });

      gatewayTest(
          'the app confirms only a sandbox payment of its own, and no withdrawal',
          () async {
        final m = await newMember();
        await expectApiError(m.commerce.mockConfirmPayment('x', success: true),
            status: 404);
        await expectLater(
            m.wallet.mockDecideWithdrawal('x', approve: true),
            throwsA(isA<ApiException>()
                .having((e) => e.code, 'code', 'not_supported')));
      });

      gatewayTest('the money adds up over a whole round', () async {
        final m = await newMember();
        final before = await chefWallet.getWallet();
        final prices = <int>[];
        final rng = Random(7);
        for (var i = 0; i < 3; i++) {
          final price = 100000 + rng.nextInt(400000);
          prices.add(price);
          final booking = await paidBooking(m, price: price);
          await deliver(booking);
          await timeTravel(booking.id, days: 3);
          await asChef.confirmCompletion(booking.id);
          await timeTravel(booking.id, days: 8);
          final done = await m.bookings.getBooking(booking.id);
          expect(done.escrow!.releasedAmount, price);
          expect(done.escrow!.feeAmount, _fee(price));
        }
        final after = await chefWallet.getWallet();
        expect(after.available - before.available,
            prices.fold<int>(0, (sum, p) => sum + p - _fee(p)));
      });
    });

    group('a chef from the application to the directory', () {
      /// A new member an admin has just approved, on a new token.
      Future<BeUser> newChef(String name) async {
        final applicant = await be.newUser(name: name);
        final profile = RemoteProfileApiService(applicant.dio);
        await profile.submitChefApplication(_application());
        var me = (await profile.getMe()).toEntity();
        expect(me.chefApplication, ChefApplicationStatus.pending);
        expect(me.role, UserRole.user);
        await expectApiError(profile.submitChefApplication(_application()),
            status: 409, code: 'already_pending');

        final queue =
            await asAdmin('GET', '/admin/chef-applications?status=pending');
        final row =
            queue.dataList.singleWhere((a) => a['userId'] == applicant.id);
        expect(row['specialties'], ['Tăng cơ']);
        final reviewed = await asAdmin(
            'POST', '/admin/chef-applications/${row['id']}/review',
            data: {'decision': 'approved', 'note': ''});
        expect(reviewed.status, 200);

        // The old token carries the old role.
        expect((await applicant.raw('GET', '/users/me')).status, 401);
        final chef = await applicant.signInAgain();
        me = (await RemoteProfileApiService(chef.dio).getMe()).toEntity();
        expect(me.role, UserRole.chef);
        expect(me.chefApplication, ChefApplicationStatus.approved);
        await expectApiError(
            RemoteProfileApiService(chef.dio)
                .submitChefApplication(_application()),
            status: 409,
            code: 'already_chef');
        return chef;
      }

      gatewayIf(String name, Future<void> Function() body) =>
          beTest(name, () async {
            if (noGateway != null) {
              markTestSkipped(noGateway!);
              return;
            }
            await body();
          });

      beTest('a rejected application says why, and can be sent again',
          () async {
        final applicant = await be.newUser(name: 'FE IT Chef Bi Tu Choi');
        final profile = RemoteProfileApiService(applicant.dio);
        await profile.submitChefApplication(_application());
        final queue =
            await asAdmin('GET', '/admin/chef-applications?status=pending');
        final row =
            queue.dataList.singleWhere((a) => a['userId'] == applicant.id);
        final noNote = await asAdmin(
            'POST', '/admin/chef-applications/${row['id']}/review',
            data: {'decision': 'rejected', 'note': ''});
        expect(noNote.status, 400);
        expect(noNote.json['code'], 'note_required');
        final rejected = await asAdmin(
            'POST', '/admin/chef-applications/${row['id']}/review',
            data: {'decision': 'rejected', 'note': 'Chứng chỉ chưa rõ ràng'});
        expect(rejected.status, 200);
        final me = (await profile.getMe()).toEntity();
        expect(me.chefApplication, ChefApplicationStatus.rejected);
        expect(me.chefRejectReason, 'Chứng chỉ chưa rõ ràng');
        await profile.submitChefApplication(_application());
        expect((await profile.getMe()).toEntity().chefApplication,
            ChefApplicationStatus.pending);
      });

      gatewayIf(
          'listed once approved; profile and prices; booked by its directory '
          'id; paid to its own wallet; withdrawn', () async {
        final chef = await newChef('FE IT Chef Moi');
        final studio = RemoteChefStudioApiService(chef.dio);
        final directory = RemoteChefApiService(be.guestDio());

        var mine = await studio.getMyProfile();
        expect(mine.userId, chef.id);
        expect(mine.specialty, isNotEmpty);
        mine = await studio.updateMyProfile(const ChefProfileRequestDto(
          specialty: 'Tăng cơ',
          bio: 'Chuyên gia thử cho kiểm thử tích hợp của VeganLife.',
          pricePerDay: 150000,
          feedbackPricePerDay: 200000,
          minPlanDays: 3,
          maxPlanDays: 10,
        ));
        expect(mine.pricePerDay, 150000);
        expect(mine.maxPlanDays, 10);

        final listed = (await directory.listChefs(query: 'FE IT Chef Moi'))
            .where((c) => c.userId == chef.id)
            .single;
        expect(listed.id, mine.id);
        expect(listed.fullName, 'FE IT Chef Moi');
        expect(listed.pricePerDay, 150000);
        expect(listed.feedbackPricePerDay, 200000);
        expect(listed.maxPlanDays, 10);
        expect(listed.acceptingBookings, isTrue);
        expect(listed.specialties, ['Tăng cơ']);
        final byProfile = await directory.getChef(mine.id);
        final byUser = await directory.getChef(chef.id);
        expect(byProfile.id, byUser.id);
        expect(byProfile.bio, contains('kiểm thử tích hợp'));
        await expectApiError(directory.getChef('aaaaaaaaaaaaaaaaaaaaaaaa'),
            status: 404);

        // The member books from the directory row.
        final m = await newMember('FE IT Chef Khach');
        await expectApiError(
            m.bookings.createBooking(_request(listed.id, days: 11)),
            status: 400);
        final asThisChef = RemoteBookingApiService(chef.dio);
        final booking = await m.bookings.createBooking(_request(listed.id));
        expect(booking.chef.id, chef.id, reason: 'the user id, on every row');
        expect(booking.partyOf(chef.id), BookingParty.chef);
        expect((await asThisChef.chefInbox()).single.id, booking.id);

        await studio.updateMyProfile(const ChefProfileRequestDto(
          specialty: 'Tăng cơ',
          bio: 'Chuyên gia thử cho kiểm thử tích hợp của VeganLife.',
          pricePerDay: 150000,
          feedbackPricePerDay: 200000,
          acceptingBookings: false,
        ));
        await expectApiError(m.bookings.createBooking(_request(listed.id)),
            status: 409, code: 'not_accepting');
        await studio.updateMyProfile(const ChefProfileRequestDto(
          specialty: 'Tăng cơ',
          bio: 'Chuyên gia thử cho kiểm thử tích hợp của VeganLife.',
          pricePerDay: 150000,
          feedbackPricePerDay: 200000,
        ));

        final offered = await asThisChef.sendOffer(
            booking.id, _offer(450000, booking.startDate, 3));
        final accepted = await m.bookings
            .respondToOffer(booking.id, offered.currentOffer!.id, accept: true);
        await payBySandbox(m, accepted);

        for (var day = 1; day <= 3; day++) {
          await asThisChef.savePlanDay(booking.id, day,
              PlanDayRequestDto(meals: _meals(day, peanut: day == 1)));
        }
        await asThisChef.sendWholePlan(booking.id);

        // "Từ chuyên gia": the planner reads the days sent, with their allergens.
        final planner =
            RemoteMealPlannerApiService(m.user.dio, userId: m.user.id);
        final rows = await planner.getChefSuggestions();
        expect(rows, hasLength(6));
        expect(rows.map((r) => r.chefName).toSet(), {'FE IT Chef Moi'});
        final peanut =
            rows.singleWhere((r) => r.recipe.name == 'Gỏi đậu phộng');
        expect(peanut.recipe.allergens, contains('peanut'),
            reason: 'a safety label');
        expect(peanut.slot, 'lunch');
        expect(peanut.targetDate, booking.startDate);

        // "Áp dụng kế hoạch vào Thực đơn".
        await planner.updateHealthProfile(_healthProfile);
        final week = startOfWeek(booking.startDate);
        final plan = await planner.createEmptyMealPlan(startDate: week);
        expect(plan.days, isNotEmpty);
        final applied = await planner.addMealToCurrentPlan(AddMealRequestDto(
          date: _vnToday(),
          slot: MealSlot.dinner,
          name: 'Canh chua của chuyên gia',
          calories: 380,
          source: 'chef',
          sourceName: 'FE IT Chef Moi',
          ingredients: const ['Cà chua'],
        ));
        expect(applied.meals[MealSlot.dinner.apiValue]?.name,
            'Canh chua của chuyên gia');

        final chefMoney = RemoteChefWalletApiService(chef.dio);
        var wallet = await chefMoney.getWallet();
        expect(wallet.pending, 405000);
        expect(wallet.available, 0);
        await timeTravel(booking.id, days: 3);
        await asThisChef.confirmCompletion(booking.id);
        await timeTravel(booking.id, days: 8);
        wallet = await chefMoney.getWallet();
        expect(wallet.pending, 0);
        expect(wallet.available, 405000);
        expect(wallet.processing, 0);

        await expectApiError(
            chefMoney
                .requestWithdrawal(const WithdrawalRequestDto(amount: 405000)),
            status: 409,
            code: 'no_bank_account');
        final saved = await chefMoney.saveBankAccount(_bank);
        expect(saved.accountHolder, _bank.accountHolder);
        final request = await chefMoney
            .requestWithdrawal(const WithdrawalRequestDto(amount: 405000));
        expect((await chefMoney.getWallet()).available, 0);
        final done = await asAdmin(
            'POST', '/admin/withdrawals/${request.id}/complete',
            data: {'transactionRef': 'VCB-2026-000999'});
        expect(done.status, 200);
        wallet = await chefMoney.getWallet();
        expect(wallet.available, 0);
        expect(wallet.withdrawn, 405000);
        expect((await chefMoney.withdrawals()).single.status,
            LedgerStatus.completed);
        final rowsAfter = await chefMoney.transactions();
        expect(rowsAfter.map((t) => t.type),
            containsAll([WalletEntryType.income, WalletEntryType.withdrawal]));

        // Its documents wait for an admin; nothing else reads them yet.
        final doc = await studio.submitKnowledgeDoc(KnowledgeDocRequestDto(
          title: 'Tài liệu thử của chuyên gia',
          fileUrl: '',
          content:
              'Nội dung tài liệu thử ${randomHex(16)} đủ dài của chuyên gia '
              'để máy chủ nhận và chờ quản trị viên duyệt.',
        ));
        expect(doc.title, 'Tài liệu thử của chuyên gia');
        expect((await studio.myKnowledgeDocs()).map((d) => d.id),
            contains(doc.id));
      });

      beTest('a member is not a chef; a chef with no profile reads a 404',
          () async {
        final m = await newMember('FE IT Chef Khong');
        await expectApiError(
            RemoteChefStudioApiService(m.user.dio).getMyProfile(),
            status: 403,
            code: 'not_chef');
      });
    });

    group('without a gateway', () {
      void noGatewayTest(String name, Future<void> Function() body) =>
          beTest(name, () async {
            if (noGateway == null) {
              markTestSkipped('This BE has a gateway: run it with no '
                  'Payment__Provider.');
              return;
            }
            await body();
          });

      noGatewayTest('the QR routes say so, and nothing is marked as paid',
          () async {
        final m = await newMember();
        final booking = await agree(m);
        await expectApiError(m.bookings.startPayment(booking.id),
            status: 503, code: 'payment_unavailable');
        await expectApiError(m.commerce.renewPayment(booking.paymentOrderId!),
            status: 503, code: 'payment_unavailable');
        final order = await m.commerce.getOrder(booking.paymentOrderId!);
        expect(order.status, OrderStatus.pending);
        expect(order.payment, isNull);
        expect((await m.bookings.getBooking(booking.id)).status,
            BookingStatus.awaitingPayment);
        final confirm = await rawRequest('POST', '/payments/x/sandbox-confirm',
            token: admin, data: {'success': true});
        expect(confirm.status, 404);
      });
    });
  });
}

CreateBookingRequestDto _request(
  String chefId, {
  BookingType type = BookingType.oneShot,
  int days = 3,
  String needs = 'Mình muốn một thực đơn thuần chay cân bằng trong tuần này.',
}) =>
    CreateBookingRequestDto(
      chefId: chefId,
      bookingType: type,
      planDays: days,
      startDate: _vnToday().add(const Duration(days: 1)),
      goal: HealthGoal.maintain.apiValue,
      allergies: const ['peanut'],
      mealPattern: const [MealSlot.lunch, MealSlot.dinner],
      needs: needs,
      budgetPerDay: 100000,
    );

OfferRequestDto _offer(int price, DateTime start, int days,
        {BookingType type = BookingType.oneShot, String note = ''}) =>
    OfferRequestDto(
      price: price,
      planDays: days,
      bookingType: type,
      startDate: start,
      note: note,
    );

ChefApplicationRequest _application() => const ChefApplicationRequest(
      specialties: ['Tăng cơ'],
      yearsExperience: 5,
      city: 'TP.HCM',
      bio: 'Tôi có năm năm kinh nghiệm thiết kế thực đơn thuần chay tăng cơ.',
      certificates: ['Chứng chỉ dinh dưỡng'],
    );

const _healthProfile = UpdateHealthProfileRequestDto(
  heightCm: 170,
  weightKg: 66,
  goal: HealthGoal.maintain,
  allergies: [],
  dietaryRestrictions: [],
  gender: Gender.female,
  birthYear: 1997,
  activityLevel: ActivityLevel.light,
  mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
);

List<PlanMealDto> _meals(int day, {bool peanut = false}) => [
      PlanMealDto(
        slot: MealSlot.lunch,
        recipe: PlanRecipeDto(
          name: peanut ? 'Gỏi đậu phộng' : 'Phở chay ngày $day',
          calories: 450,
          proteinG: 18,
          carbsG: 60,
          fatG: 10,
          ingredients: const ['Bánh phở', 'Nấm rơm'],
          instructions: 'Nấu nước dùng, chan vào phở.',
        ),
      ),
      PlanMealDto(
        slot: MealSlot.dinner,
        recipe: PlanRecipeDto(name: 'Canh chua ngày $day', calories: 380),
      ),
    ];

ComplaintRequestDto _complaint() => const ComplaintRequestDto(
      reason: ComplaintReason.notAsAgreed,
      description: 'Kế hoạch không đúng như đã thoả thuận trong phần trao đổi.',
      requestedOutcome: RequestedOutcome.fullRefund,
      evidence: [
        EvidenceDto(
          id: '',
          kind: EvidenceKind.link,
          url: 'https://example.com/anh-bang-chung.png',
          caption: 'Ảnh chụp',
          submittedBy: BookingParty.member,
        ),
      ],
    );
