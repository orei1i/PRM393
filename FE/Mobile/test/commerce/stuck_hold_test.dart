// test/commerce/stuck_hold_test.dart
// A hold that could not auto-complete and that an admin decides on web
// `/disputes`, on the mock server with a pinned clock: what counts as stuck, the
// money of each decision, each error, and what both sides can do afterwards.
// The mock repositories wait like a network.
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/booking/data/mock/mock_booking_db.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_views.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_wallet_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/commerce/data/member_wallet_api_service.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/domain/commerce_status.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';

const _note =
    'Chuyên gia ngừng giao, hai bên không phản hồi nên Ban quản trị xử lý.';
const _price = 450000;

Matcher apiError(int status, String code) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.code, 'code', code);

PlanDayRequestDto _fullDay(int day) => PlanDayRequestDto(meals: [
      for (final slot in MealPattern.standard)
        PlanMealDto(
            slot: slot,
            recipe:
                PlanRecipeDto(name: 'Món ${slot.label} $day', calories: 400)),
    ]);

void main() {
  late DateTime now;
  String? userId = 'u_me';
  var role = UserRole.user;

  final bookings = MockBookingRepository(
    currentUserId: () => userId,
    currentUserName: () => userId == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
    currentRole: () => role,
  );
  final commerce = MockCommerceRepository(currentUserId: () => userId);
  final chefWallet = MockChefWalletRepository(
      currentUserId: () => userId, currentRole: () => role);
  final wallet = MockMemberWalletRepository(currentUserId: () => userId);

  MockBookingDb db() => MockBookingDb.instance;

  void asMember() {
    userId = 'u_me';
    role = UserRole.user;
  }

  void asTam() {
    userId = 'u_chef_tam';
    role = UserRole.chef;
  }

  // The plan runs 20–22/10, so the moment is 25/10 23:59 VN.
  final moment = DateTime.utc(2026, 10, 25, 16, 59);
  final oneMinuteEarlier = moment.subtract(const Duration(minutes: 1));
  final pastMoment = moment.add(const Duration(days: 2));

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 3); // 10:00 VN
    MockCommerceDb.reset(clock: () => now);
    MockMealPlannerRepository.reset();
    asMember();
  });

  /// Paid, 3 days, 450.000đ, nothing sent.
  Future<BookingDto> paid({BookingType type = BookingType.oneShot}) async {
    asMember();
    final created = await bookings.createBooking(CreateBookingRequestDto(
      chefId: 'u_chef_tam',
      bookingType: type,
      planDays: 3,
      startDate: DateTime(2026, 10, 20),
      goal: 'lose_weight',
      allergies: const ['peanut'],
      mealPattern: MealPattern.standard,
      needs: 'Mình cần thực đơn chay đủ chất, bữa sáng dưới 15 phút.',
    ));
    asTam();
    final quoted = await bookings.sendOffer(
        created.id,
        OfferRequestDto(
            price: _price,
            planDays: 3,
            bookingType: type,
            startDate: DateTime(2026, 10, 20)));
    asMember();
    await bookings.respondToOffer(created.id, quoted.currentOffer!.id,
        accept: true);
    final order = await bookings.startPayment(created.id);
    await commerce.mockConfirmPayment(order.payment!.id, success: true);
    return bookings.getBooking(created.id);
  }

  Future<void> sendAll(String id) async {
    asTam();
    for (var day = 1; day <= 3; day++) {
      await bookings.savePlanDay(id, day, _fullDay(day));
    }
    await bookings.sendWholePlan(id);
    asMember();
  }

  /// One of three days sent, read after the moment.
  Future<BookingDto> stuckMissing() async {
    final b = await paid(type: BookingType.dailyFeedback);
    asTam();
    await bookings.savePlanDay(b.id, 1, _fullDay(1));
    await bookings.sendPlanDay(b.id, 1);
    asMember();
    now = pastMoment;
    return bookings.getBooking(b.id);
  }

  /// Every day sent, all of them after the moment.
  Future<BookingDto> stuckLate() async {
    final b = await paid();
    now = pastMoment;
    await sendAll(b.id);
    return bookings.getBooking(b.id);
  }

  bool stuck(BookingDto b) => db().isStuck(db().booking(b.id));

  void expectNotStuck409(BookingDto b) => expect(
      () => db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.releaseToChef, note: _note),
      throwsA(apiError(409, 'not_stuck')));

  const complaint = ComplaintRequestDto(
    reason: ComplaintReason.lateOrMissing,
    description: 'Chuyên gia giao thiếu ngày so với hợp đồng đã thoả thuận.',
    requestedOutcome: RequestedOutcome.fullRefund,
    evidence: [
      EvidenceDto(
          kind: EvidenceKind.image, url: 'https://res.cloudinary.com/a.jpg'),
    ],
  );

  group('what counts as stuck', () {
    test('days missing: from the moment on, not a minute earlier', () async {
      final b = await paid(type: BookingType.dailyFeedback);
      now = oneMinuteEarlier;
      expect(stuck(b), isFalse);
      expectNotStuck409(b);
      now = moment;
      expect(stuck(b), isTrue);
    });

    test('days sent after the moment: stuck, and the chef can still end it',
        () async {
      final b = await stuckLate();
      expect(b.fullyDelivered, isTrue);
      expect(b.autoCompleted, isFalse);
      expect(b.deliveredAfterAutoComplete(now), isTrue);
      expect(stuck(b), isTrue);
      expect(b.canConfirmCompletion(now), isTrue);

      asTam();
      final done = await bookings.confirmCompletion(b.id);
      expect(done.autoCompleted, isFalse);
      expect(stuck(done), isFalse);
      expectNotStuck409(done);
    });

    test('days still missing: the member complaining ends it', () async {
      final b = await stuckMissing();
      expect(stuck(b), isTrue);
      expect(b.canComplain(now), isTrue);
      final after = await bookings.fileComplaint(b.id, complaint);
      expect(after.escrow!.status, EscrowStatus.frozen);
      expect(stuck(after), isFalse, reason: 'an open complaint');
      expectNotStuck409(after);
    });

    test('an open complaint from before the moment: never stuck', () async {
      final b = await paid();
      now = DateTime.utc(2026, 10, 23, 3);
      final filed = await bookings.fileComplaint(b.id, complaint);
      now = pastMoment;
      expect(stuck(filed), isFalse);
      expectNotStuck409(filed);
    });

    test('before the moment, every day sent: not stuck', () async {
      final b = await paid();
      await sendAll(b.id);
      now = oneMinuteEarlier;
      expect(stuck(b), isFalse);
      expectNotStuck409(b);
    });

    test('every day sent in time: it completed by itself instead', () async {
      final b = await paid();
      await sendAll(b.id);
      now = pastMoment;
      final after = await bookings.getBooking(b.id);
      expect(after.autoCompleted, isTrue);
      expect(after.deliveredAfterAutoComplete(now), isFalse);
      expect(stuck(after), isFalse);
      expectNotStuck409(after);
    });

    test('after the chef confirmed: not stuck', () async {
      final b = await paid();
      await sendAll(b.id);
      asTam();
      now = DateTime.utc(2026, 10, 22, 3);
      final done = await bookings.confirmCompletion(b.id);
      now = pastMoment;
      expect(stuck(done), isFalse);
      expectNotStuck409(done);
    });

    test('a member who cancelled after paying: not stuck', () async {
      final b = await paid();
      final cancelled = await bookings.cancel(b.id, 'Mình đổi lịch rồi ạ');
      now = pastMoment;
      expect(stuck(cancelled), isFalse);
      expect(cancelled.isAdminResolved, isFalse);
      expectNotStuck409(cancelled);
    });

    test('the seed with days missing is stuck', () async {
      final short = db().booking('b_ma_tam_short');
      expect(db().isStuck(short), isTrue);
    });
  });

  group('each decision pays the same as a complaint decision', () {
    test('ReleaseToChef: the chef nets 90 %, the booking is Completed',
        () async {
      final b = await stuckMissing();
      asTam();
      final before = await chefWallet.getWallet();
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.releaseToChef,
          note: '  $_note  ',
          by: 'Lê Minh Quân');

      final after = await bookings.getBooking(b.id);
      final e = after.escrow!;
      expect(after.status, BookingStatus.completed);
      expect(after.completedAt!.toUtc(), now);
      expect(after.autoCompleted, isFalse);
      expect(after.isAdminResolved, isTrue);
      expect(after.cancelReason, isNull);
      expect(e.status, EscrowStatus.released);
      expect(e.releasedAt!.toUtc(), now);
      expect(e.releasedAmount, _price);
      expect(e.feeAmount, 45000);
      expect(e.refundedAmount, 0);
      expect(e.refundedAt, isNull);
      expect(e.completedAt!.toUtc(), now);
      expect(e.releaseAt, isNull);
      expect(e.resolvedBy, 'Lê Minh Quân');
      expect(e.resolutionNote, _note, reason: 'trimmed');

      final w = await chefWallet.getWallet();
      expect(w.available, before.available + 405000);
      expect(w.pending, before.pending - 405000);
      final rows = (await chefWallet.transactions())
          .where((t) => t.bookingId == b.id)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.status, LedgerStatus.available);
      expect(rows.single.net, 405000);
      expect(rows.single.note, contains('Ban quản trị'));

      final order = db().commerce.order(after.paymentOrderId!);
      expect(order.status, OrderStatus.paid);
      asMember();
      final messages = await bookings.messages(b.id);
      expect(messages.last.senderRole, BookingParty.system);
      expect(messages.last.body, contains('Ban quản trị đã xử lý'));
      expect(messages.last.body, contains(_note));
    });

    test(
        'RefundMember: the whole price to the member, the booking is Cancelled',
        () async {
      final b = await stuckLate();
      final memberBefore = await wallet.getWallet();
      asTam();
      final chefBefore = await chefWallet.getWallet();
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.refundMember, note: _note);

      final after = await bookings.getBooking(b.id);
      final e = after.escrow!;
      expect(after.status, BookingStatus.cancelled);
      expect(after.cancelReason, _note);
      expect(after.completedAt, isNull);
      expect(after.isAdminResolved, isTrue);
      expect(e.status, EscrowStatus.refunded);
      expect(e.refundedAmount, _price);
      expect(e.refundedAt!.toUtc(), now);
      expect(e.releasedAmount, 0);
      expect(e.releasedAt, isNull);
      expect(e.feeAmount, 0);
      expect(e.resolvedBy, 'Quản trị viên');

      final chef = await chefWallet.getWallet();
      expect(chef.available, chefBefore.available);
      expect(chef.pending, chefBefore.pending - 405000);
      final chefRow = (await chefWallet.transactions())
          .singleWhere((t) => t.bookingId == b.id);
      expect(chefRow.status, LedgerStatus.reversed);
      expect(chefRow.createdAt.toUtc(), now, reason: 'not the payment date');

      asMember();
      final member = await wallet.getWallet();
      expect(member.available, memberBefore.available + _price);
      final refund = (await wallet.transactions())
          .singleWhere((t) => t.bookingId == b.id && t.net > 0);
      expect(refund.net, _price);
      expect(refund.note, contains('Ban quản trị'));
      expect(db().commerce.order(after.paymentOrderId!).status,
          OrderStatus.refunded);
      expect((await bookings.messages(b.id)).last.body,
          contains('Ban quản trị đã xử lý'));
    });

    test('Split: X to the member, (price − X) × 90 % to the chef, Completed',
        () async {
      final b = await stuckMissing();
      final memberBefore = await wallet.getWallet();
      asTam();
      final chefBefore = await chefWallet.getWallet();
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.split, refundAmount: 300000, note: _note);

      final after = await bookings.getBooking(b.id);
      final e = after.escrow!;
      expect(after.status, BookingStatus.completed);
      expect(after.completedAt!.toUtc(), now);
      expect(e.status, EscrowStatus.partiallyRefunded);
      expect(e.refundedAmount, 300000);
      expect(e.refundedAt!.toUtc(), now);
      expect(e.releasedAmount, 150000);
      expect(e.releasedAt!.toUtc(), now);
      expect(e.feeAmount, 15000);

      final chef = await chefWallet.getWallet();
      expect(chef.available, chefBefore.available + 135000);
      final chefRow = (await chefWallet.transactions())
          .singleWhere((t) => t.bookingId == b.id);
      expect(chefRow.net, 135000);
      expect(chefRow.status, LedgerStatus.available);
      expect(chefRow.note, contains('Ban quản trị'));
      expect(chefRow.note, isNot(contains('khiếu nại')));

      asMember();
      expect((await wallet.getWallet()).available,
          memberBefore.available + 300000);
      expect(db().commerce.order(after.paymentOrderId!).status,
          OrderStatus.partiallyRefunded);
    });
  });

  group('each error', () {
    late BookingDto b;

    setUp(() async {
      b = await stuckMissing();
    });

    void expectFails(
      Matcher matcher, {
      ComplaintDecision decision = ComplaintDecision.releaseToChef,
      int? refundAmount,
      String note = _note,
      String? holdId,
    }) =>
        expect(
            () => db().resolveHold(holdId ?? b.escrow!.id,
                decision: decision, refundAmount: refundAmount, note: note),
            throwsA(matcher));

    test('400 note_too_short, counting no spaces', () {
      final tooShort = apiError(400, 'note_too_short');
      expectFails(tooShort, note: 'Ngắn quá');
      expectFails(tooShort, note: '${' ' * 10}${'a' * 19}${' ' * 10}');
    });

    test('400 invalid_refund_amount: Split only, 1.000 ≤ X < price', () {
      final bad = apiError(400, 'invalid_refund_amount');
      for (final x in [null, 0, 999, _price, _price + 1]) {
        expectFails(bad, decision: ComplaintDecision.split, refundAmount: x);
      }
      // The others ignore it.
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.releaseToChef,
          refundAmount: 999,
          note: _note);
      expect(db().booking(b.id).escrow!.refundedAmount, 0);
    });

    test('a smallest and a largest Split go through', () {
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.split, refundAmount: 1000, note: _note);
      expect(db().booking(b.id).escrow!.refundedAmount, 1000);
    });

    test('404', () {
      expectFails(apiError(404, 'not_found'), holdId: 'eh_none');
    });

    test('409 not_stuck on a hold already decided, whatever the decision', () {
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.refundMember, note: _note);
      for (final d in ComplaintDecision.values) {
        expectFails(apiError(409, 'not_stuck'),
            decision: d, refundAmount: 1000);
      }
    });

    test('a failed attempt changes nothing', () async {
      expectFails(apiError(400, 'note_too_short'), note: 'x');
      final after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.active);
      expect(after.escrow!.status, EscrowStatus.held);
      expect(stuck(after), isTrue);
    });
  });

  group('after a decision', () {
    for (final (decision, refund) in [
      (ComplaintDecision.releaseToChef, null),
      (ComplaintDecision.refundMember, null),
      (ComplaintDecision.split, 200000),
    ]) {
      test('$decision: nothing is left to do on either side', () async {
        final b = await stuckLate();
        db().resolveHold(b.escrow!.id,
            decision: decision, refundAmount: refund, note: _note);

        final after = await bookings.getBooking(b.id);
        expect(after.canComplain(now), isFalse);
        expect(after.canCancelPaid, isFalse);
        expect(after.canConfirmCompletion(now), isFalse);
        expect(after.overdueUndelivered(now), isFalse);
        expect(after.deliveredAfterAutoComplete(now), isFalse);
        expect(memberNeedsAction(after, now), isFalse);
        expect(chefNeedsAction(after, now), isFalse);
        expect(InboxTab.of(after.status), InboxTab.finished);
        expect(memberOutcome(after), startsWith('Ban quản trị đã xử lý: '));

        await expectLater(bookings.fileComplaint(b.id, complaint),
            throwsA(apiError(409, 'not_open')));
        await expectLater(bookings.cancel(b.id, 'Mình đổi lịch rồi ạ'),
            throwsA(apiError(409, 'invalid_status')));
        asTam();
        await expectLater(bookings.confirmCompletion(b.id),
            throwsA(apiError(409, 'not_active')));
        await expectLater(bookings.savePlanDay(b.id, 1, _fullDay(1)),
            throwsA(apiError(409, 'invalid_status')));
        asMember();

        // Nothing moves it later: no release, no second credit.
        final balance = (await wallet.getWallet()).available;
        now = DateTime.utc(2027, 1, 1);
        final later = await bookings.getBooking(b.id);
        expect(later.status, after.status);
        expect(later.escrow!.status, after.escrow!.status);
        expect(later.escrow!.releaseAt, isNull);
        expect((await wallet.getWallet()).available, balance);
      });
    }

    test('what each side reads', () async {
      final b = await stuckMissing();
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.split, refundAmount: 300000, note: _note);
      final after = await bookings.getBooking(b.id);
      expect(adminResolutionOutcome(after, BookingParty.member),
          'Đã hoàn 300.000đ vào Ví của tôi, chuyên gia nhận 135.000đ sau phí');
      expect(adminResolutionOutcome(after, BookingParty.chef),
          'Hoàn 300.000đ cho thành viên, 135.000đ sau phí đã vào ví của bạn');
      expect(bookingStep(after), 5);
    });

    test('a refund stops at the plan step, not at the payment', () async {
      final b = await stuckMissing();
      db().resolveHold(b.escrow!.id,
          decision: ComplaintDecision.refundMember, note: _note);
      expect(bookingStep(await bookings.getBooking(b.id)), 3);
    });
  });

  group('the wire', () {
    BookingDto booking(Map<String, dynamic> escrow,
            {Map<String, dynamic>? complaint}) =>
        BookingDto.fromJson({
          'id': 'b1',
          'status': 'Completed',
          'escrow': {
            'id': 'eh',
            'amount': 100000,
            'status': 'Released',
            ...escrow
          },
          'complaint': complaint,
        });

    test('resolvedBy with no complaint is the admin; anything else is not', () {
      expect(booking({'resolvedBy': 'Lê Minh Quân'}).isAdminResolved, isTrue);
      expect(
          booking({
            'resolvedBy': {'fullName': 'Lê Minh Quân'}
          }).isAdminResolved,
          isTrue);
      expect(booking({}).isAdminResolved, isFalse);
      expect(booking({'resolvedBy': null}).isAdminResolved, isFalse);
      expect(booking({'resolvedBy': ''}).isAdminResolved, isFalse);
      expect(booking({'resolvedBy': 12}).isAdminResolved, isFalse);
      expect(
          booking({'resolvedBy': 'Lê Minh Quân'},
              complaint: {'id': 'cp', 'status': 'Resolved'}).isAdminResolved,
          isFalse);
    });

    test('refundedAt: a date, or nothing', () {
      expect(
          booking({'refundedAt': '2026-11-01T05:00:00.000Z'})
              .escrow!
              .refundedAt!
              .toUtc(),
          DateTime.utc(2026, 11, 1, 5));
      expect(booking({}).escrow!.refundedAt, isNull);
      expect(booking({'refundedAt': 'junk'}).escrow!.refundedAt, isNull);
    });
  });
}
