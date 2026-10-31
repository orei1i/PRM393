// test/chef/booking_flow_test.dart
// End-to-end booking flows on the mock server, with a pinned mock clock.
// The mock repositories wait like a network (0.2–1 s per call).
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/booking/data/mock/mock_booking_db.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_wallet_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/domain/commerce_status.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';

Matcher apiError(int status, [String? code]) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.code, 'code', code ?? anything);

PlanMealDto _meal(MealSlot slot, String name, int kcal) => PlanMealDto(
    slot: slot,
    recipe: PlanRecipeDto(
        name: name, calories: kcal, ingredients: const ['Đậu hũ', 'Cà chua']));

PlanDayRequestDto _fullDay(String suffix) => PlanDayRequestDto(
      chefNote: 'Ghi chú $suffix',
      meals: [
        _meal(MealSlot.breakfast, 'Cháo yến mạch $suffix', 350),
        _meal(MealSlot.lunch, 'Cơm gạo lứt đậu hũ $suffix', 600),
        _meal(MealSlot.dinner, 'Canh rong biển $suffix', 450),
      ],
    );

void main() {
  // Saturday 17/10/2026, 10:00 in Vietnam.
  late DateTime now;
  String? userId = 'u_me';
  var role = UserRole.user;
  var name = 'Minh Anh';

  final bookings = MockBookingRepository(
    currentUserId: () => userId,
    currentUserName: () => name,
    currentRole: () => role,
  );
  final commerce = MockCommerceRepository(currentUserId: () => userId);
  final wallet = MockChefWalletRepository(
      currentUserId: () => userId, currentRole: () => role);

  void asMember() {
    userId = 'u_me';
    role = UserRole.user;
    name = 'Minh Anh';
  }

  void asTam() {
    userId = 'u_chef_tam';
    role = UserRole.chef;
    name = 'Lê Quang Tâm';
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 3);
    MockCommerceDb.reset(clock: () => now);
    MockMealPlannerRepository.reset();
    asMember();
  });

  CreateBookingRequestDto request({
    String chefId = 'u_chef_tam',
    BookingType type = BookingType.dailyFeedback,
    int days = 7,
    String needs =
        'Mình cần thực đơn chay giảm cân, bữa sáng nhanh dưới 15 phút.',
  }) =>
      CreateBookingRequestDto(
        chefId: chefId,
        bookingType: type,
        planDays: days,
        startDate: DateTime(2026, 10, 20),
        goal: 'lose_weight',
        allergies: const ['peanut'],
        mealPattern: MealPattern.standard,
        budgetPerDay: 80000,
        needs: needs,
      );

  OfferRequestDto offer(int price,
          {int days = 7, BookingType type = BookingType.dailyFeedback}) =>
      OfferRequestDto(
        price: price,
        planDays: days,
        bookingType: type,
        startDate: DateTime(2026, 10, 20),
        note: 'Giá đã gồm danh sách đi chợ.',
      );

  /// Member requests from Tâm, Tâm quotes, the member accepts and pays.
  Future<BookingDto> paidBooking(
      {BookingType type = BookingType.dailyFeedback, int days = 7}) async {
    asMember();
    final created =
        await bookings.createBooking(request(type: type, days: days));
    asTam();
    final quoted = await bookings.sendOffer(
        created.id, offer(150000 * days, days: days, type: type));
    asMember();
    await bookings.respondToOffer(created.id, quoted.currentOffer!.id,
        accept: true);
    final order = await bookings.startPayment(created.id);
    await commerce.mockConfirmPayment(order.payment!.id, success: true);
    return bookings.getBooking(created.id);
  }

  test('seeds mirror the web console (ids, people, amounts, states)', () async {
    final mine = {for (final b in await bookings.myBookings()) b.id: b};
    expect(mine.keys,
        containsAll(['b_ma_tam_nego', 'b_ma_thuha_active', 'b_ma_tam_done']));
    final nego = mine['b_ma_tam_nego']!;
    expect(nego.status, BookingStatus.negotiating);
    expect(nego.openOffer!.price, 1500000);
    expect(nego.openOffer!.proposedBy, BookingParty.chef);
    final thuha = mine['b_ma_thuha_active']!;
    expect(thuha.chef.fullName, 'ThS. DD Phạm Thu Hà');
    expect(thuha.status, BookingStatus.active);
    expect(thuha.deliveredDays, 7);
    expect(thuha.escrow!.status, EscrowStatus.held);
    expect(thuha.paymentOrderId, 'ord_601');
    final done = mine['b_ma_tam_done']!;
    expect(done.status, BookingStatus.completed);
    expect(done.escrow!.status, EscrowStatus.released);
    expect(done.escrow!.feeAmount, 90000);

    asTam();
    final inbox = {for (final b in await bookings.chefInbox()) b.id: b};
    expect(inbox['b_nam_tam_req']!.status, BookingStatus.requested);
    expect(inbox['b_vy_tam_active']!.deliveredDays, 2,
        reason: "today's day is still a draft");
    final tram = inbox['b_tram_tam']!;
    expect(tram.status, BookingStatus.disputed);
    expect(tram.escrow!.status, EscrowStatus.frozen);
    expect(tram.complaint!.id, 'cp_tram_tam');
    expect(tram.complaint!.reason, ComplaintReason.healthRisk);
    expect(tram.complaint!.evidence.map((e) => e.kind),
        [EvidenceKind.link, EvidenceKind.image]);
    expect(tram.complaint!.chefResponse, isNotNull);
    expect(inbox['b_han_tam_done']!.escrow!.amount, 6000000);
    expect(tram.memberHealth?.summary, contains('41 tuổi'));
  });

  test('guests 401, strangers 404, self-booking and paused chefs 409',
      () async {
    userId = null;
    await expectLater(bookings.myBookings(), throwsA(apiError(401)));
    await expectLater(
        bookings.createBooking(request()), throwsA(apiError(401)));
    asMember();
    await expectLater(
        bookings.getBooking('b_nam_tam_req'), throwsA(apiError(404)));
    await expectLater(bookings.chefInbox(), throwsA(apiError(403)));
    await expectLater(bookings.createBooking(request(chefId: 'u_chef_minh')),
        throwsA(apiError(409, 'not_accepting')));
    await expectLater(bookings.createBooking(request(needs: 'Quá ngắn')),
        throwsA(apiError(400)));
    await expectLater(
        bookings.createBooking(
            request(needs: 'Thử lỗi máy chủ #fail cho yêu cầu này nhé')),
        throwsA(apiError(503)));
    asTam();
    await expectLater(bookings.createBooking(request()),
        throwsA(apiError(409, 'self_booking')));
  });

  test(
      'two accounts: request → quote → counter → accept → pay → escrow Held → '
      'day 1 → feedback → day 2 → release after the window (net 90%)',
      () async {
    final created = await bookings.createBooking(request());
    expect(created.status, BookingStatus.requested);
    expect(created.chef.id, 'u_chef_tam');
    expect(created.memberHealth, isNotNull, reason: 'shared by default');

    asTam();
    var b = await bookings.sendOffer(created.id, offer(1260000));
    expect(b.status, BookingStatus.negotiating);
    final chefOffer = b.currentOffer!;
    await expectLater(
        bookings.respondToOffer(created.id, chefOffer.id, accept: true),
        throwsA(apiError(409, 'own_offer')));

    asMember();
    b = await bookings.sendOffer(created.id, offer(1100000));
    final counter = b.currentOffer!;
    expect(counter.proposedBy, BookingParty.member);
    await expectLater(
        bookings.respondToOffer(created.id, chefOffer.id, accept: true),
        throwsA(apiError(409, 'offer_closed')),
        reason: 'only the latest open offer can be accepted');
    final chat = await bookings.messages(created.id);
    expect(
        chat
            .where((m) => m.kind == MessageKind.offer)
            .map((m) => m.offer!.status),
        [OfferStatus.superseded, OfferStatus.open]);

    asTam();
    b = await bookings.respondToOffer(created.id, counter.id, accept: true);
    expect(b.status, BookingStatus.awaitingPayment);
    expect(b.contract!.price, 1100000);
    expect(b.contract!.endDate, DateTime(2026, 10, 26));
    expect(
        b.contract!.paymentDueAt.toUtc(), now.add(const Duration(hours: 48)));

    asMember();
    final order = await bookings.startPayment(created.id);
    expect(order.amount, 1100000);
    expect(order.bookingId, created.id);
    expect(order.payment!.status, PaymentStatus.pending);
    await commerce.mockConfirmPayment(order.payment!.id, success: true);
    b = await bookings.getBooking(created.id);
    expect(b.status, BookingStatus.active);
    expect(b.escrow!.status, EscrowStatus.held);
    expect(b.escrow!.amount, 1100000);
    // 26/10 23:59 VN + 3 days.
    expect(b.escrow!.releaseAt.toUtc(), DateTime.utc(2026, 10, 29, 16, 59));
    expect(b.canComplain(now), isTrue);

    asTam();
    var w = await wallet.getWallet();
    expect(w.pending, 1134000 + 990000);
    await expectLater(bookings.sendPlanDay(created.id, 1),
        throwsA(apiError(409, 'day_incomplete')));
    final draft = await bookings.savePlanDay(created.id, 1, _fullDay('ngày 1'));
    expect(draft.status, PlanDayStatus.draft);
    await expectLater(bookings.sendPlanDay(created.id, 2),
        throwsA(apiError(409, 'previous_day_unsent')));
    final sent = await bookings.sendPlanDay(created.id, 1);
    expect(sent.status, PlanDayStatus.sent);

    // Sent meals reach Minh Anh's Thực đơn › "Từ chuyên gia".
    final fromChef =
        await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
    final dinner = fromChef.firstWhere(
        (s) => s.recipe.name == 'Canh rong biển ngày 1',
        orElse: () => throw StateError('not delivered'));
    expect(dinner.chefName, 'Lê Quang Tâm');
    expect(dinner.slot, 'dinner');
    expect(dinner.targetDate, DateTime(2026, 10, 20));

    // Day 1 (20/10) has started: feedback on a future day is refused.
    now = DateTime.utc(2026, 10, 20, 3);
    asMember();
    expect((await bookings.plan(created.id)).map((d) => d.dayIndex), [1],
        reason: 'the member sees sent days only');
    await bookings.sendDayFeedback(
        created.id,
        1,
        const DayFeedbackDto(
            rating: 4, adherence: Adherence.partly, body: 'Bữa tối bớt dầu'));
    await expectLater(
        bookings.sendDayFeedback(created.id, 2,
            const DayFeedbackDto(rating: 5, adherence: Adherence.all)),
        throwsA(apiError(409, 'day_not_sent')));

    asTam();
    final days = await bookings.plan(created.id);
    expect(days.first.feedback!.summary,
        '★★★★ · Làm theo một phần · "Bữa tối bớt dầu"');
    await bookings.savePlanDay(created.id, 2, _fullDay('ngày 2'));
    await bookings.sendPlanDay(created.id, 2);

    // After 29/10 23:59 VN nobody complained: released, fee 10 %. The seeded
    // Thảo Vy hold is released too; Ngọc Trâm's stays frozen.
    now = DateTime.utc(2026, 10, 29, 17, 0);
    b = await bookings.getBooking(created.id);
    expect(b.status, BookingStatus.completed);
    expect(b.escrow!.status, EscrowStatus.released);
    expect(b.escrow!.feeAmount, 110000);
    w = await wallet.getWallet();
    expect(w.available, 110000 + 1134000 + 990000);
    expect(w.frozen, 945000, reason: 'a disputed hold stays frozen');
    final row = (await wallet.transactions())
        .singleWhere((t) => t.id == 'tx_in_${created.id}');
    expect(row.status, LedgerStatus.available);
    expect((row.gross, row.fee, row.net), (1100000, 110000, 990000));
    expect(row.memberName, 'Minh Anh');
  });

  test(
      'complaint: evidence rules, frozen past the window, split decision '
      '(refund to the original payment, chef gross = price − refund)',
      () async {
    const id = 'b_ma_thuha_active';
    ComplaintRequestDto complaint({
      ComplaintReason reason = ComplaintReason.healthRisk,
      String description =
          'Ngày 3 có món chiên nhiều dầu dù mình đã ghi rõ cần ít dầu vì bệnh dạ dày.',
      List<EvidenceDto> evidence = const [
        EvidenceDto(
            kind: EvidenceKind.link, url: 'https://www.vinmec.com/bai-viet'),
        EvidenceDto(
            kind: EvidenceKind.image, url: 'https://res.cloudinary.com/x.jpg'),
      ],
      RequestedOutcome outcome = RequestedOutcome.partialRefund,
      int? amount = 300000,
    }) =>
        ComplaintRequestDto(
          reason: reason,
          description: description,
          requestedOutcome: outcome,
          requestedAmount: amount,
          evidence: evidence,
        );

    await expectLater(
        bookings.fileComplaint(
            id,
            complaint(evidence: const [
              EvidenceDto(
                  kind: EvidenceKind.image,
                  url: 'https://res.cloudinary.com/x.jpg'),
            ])),
        throwsA(apiError(400)),
        reason: 'health risk needs a source link');
    await expectLater(bookings.fileComplaint(id, complaint(evidence: const [])),
        throwsA(apiError(400)));
    await expectLater(bookings.fileComplaint(id, complaint(amount: 840000)),
        throwsA(apiError(400)),
        reason: 'a partial refund stays below the price');
    await expectLater(
        bookings.fileComplaint(
            id,
            complaint(
                description:
                    'Thử lỗi máy chủ #fail khi gửi khiếu nại kế hoạch này.')),
        throwsA(apiError(503)));

    var b = await bookings.fileComplaint(id, complaint());
    expect(b.status, BookingStatus.disputed);
    expect(b.escrow!.status, EscrowStatus.frozen);
    expect(b.complaint!.status, ComplaintStatus.open);
    expect(b.complaint!.requestedAmount, 300000);
    await expectLater(bookings.fileComplaint(id, complaint()),
        throwsA(apiError(409, 'complaint_exists')));

    // Past releaseAt (24/10 23:59 VN): still frozen.
    now = DateTime.utc(2026, 10, 26);
    b = await bookings.getBooking(id);
    expect(b.escrow!.status, EscrowStatus.frozen);
    expect(b.status, BookingStatus.disputed);

    // The admin splits on web /disputes.
    MockBookingDb.instance.decideComplaint(id,
        decision: ComplaintDecision.split, refundAmount: 300000);
    b = await bookings.getBooking(id);
    expect(b.status, BookingStatus.resolved);
    expect(b.escrow!.status, EscrowStatus.partiallyRefunded);
    expect(b.escrow!.refundedAmount, 300000);
    expect(b.escrow!.releasedAmount, 540000);
    expect(b.escrow!.feeAmount, 54000);
    expect(b.complaint!.decision, ComplaintDecision.split);
    final order = await commerce.getOrder('ord_601');
    expect(order.status, OrderStatus.partiallyRefunded);

    userId = 'u_thu_ha';
    role = UserRole.chef;
    final w = await wallet.getWallet();
    expect(w.available, 486000);
    final row =
        (await wallet.transactions()).singleWhere((t) => t.id == 'tx_in_$id');
    expect(row.note, 'Hoàn 300.000đ cho thành viên theo quyết định khiếu nại');
  });

  test('decline, cancel, #expire payment window and #fail in the chat',
      () async {
    asTam();
    await expectLater(
        bookings.decline('b_nam_tam_req', 'Bận'), throwsA(apiError(400)));
    var b = await bookings.decline(
        'b_nam_tam_req', 'Lịch của mình đã kín trong 2 tuần tới.');
    expect(b.status, BookingStatus.declined);
    await expectLater(
        bookings.sendMessage('b_nam_tam_req',
            const SendMessageRequestDto(body: 'Xin lỗi bạn nhé')),
        throwsA(apiError(409)));

    asMember();
    await expectLater(
        bookings.sendMessage('b_ma_tam_nego',
            const SendMessageRequestDto(body: 'Thử #fail tin nhắn')),
        throwsA(apiError(503)));
    b = await bookings.cancel('b_ma_tam_nego', 'Mình đổi kế hoạch rồi ạ');
    expect(b.status, BookingStatus.cancelled);
    expect(b.currentOffer!.status, OfferStatus.withdrawn);

    final fast = await bookings.createBooking(request(
        needs: 'Thử hết hạn thanh toán nhanh #expire cho kế hoạch này.'));
    asTam();
    final quoted = await bookings.sendOffer(fast.id, offer(1260000));
    asMember();
    b = await bookings.respondToOffer(fast.id, quoted.currentOffer!.id,
        accept: true);
    expect(
        b.contract!.paymentDueAt.toUtc(), now.add(const Duration(seconds: 30)));
    final order = await bookings.startPayment(fast.id);
    expect(
        order.payment!.expiresAt!.isAfter(b.contract!.paymentDueAt), isFalse);
    now = now.add(const Duration(seconds: 31));
    b = await bookings.getBooking(fast.id);
    expect(b.status, BookingStatus.expired);
    expect((await commerce.getOrder(order.id)).status, OrderStatus.cancelled);
    await expectLater(bookings.startPayment(fast.id),
        throwsA(apiError(409, 'not_awaiting_payment')));
  });

  test('OneShot: "Gửi toàn bộ kế hoạch" only once every day is complete',
      () async {
    final b = await paidBooking(type: BookingType.oneShot, days: 3);
    expect(b.status, BookingStatus.active);
    asTam();
    await expectLater(
        bookings.sendWholePlan(b.id), throwsA(apiError(409, 'day_incomplete')));
    await expectLater(
        bookings.sendPlanDay(b.id, 1), throwsA(apiError(409, 'one_shot')));
    for (var i = 1; i <= 3; i++) {
      await bookings.savePlanDay(b.id, i, _fullDay('OS $i'));
    }
    final days = await bookings.sendWholePlan(b.id);
    expect(days.every((d) => d.status == PlanDayStatus.sent), isTrue);
    asMember();
    expect((await bookings.getBooking(b.id)).deliveredDays, 3);
    final fromChef =
        await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
    expect(fromChef.where((s) => RegExp(r'OS \d$').hasMatch(s.recipe.name)),
        hasLength(9));
  });
}
