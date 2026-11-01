// test/commerce/money_flow_test.dart
// Requirements 2, 3, 7 and 8 on the mock server, with a pinned clock: for whom
// a request is, what it sends, the money from payment to the chef's wallet, and
// the member's wallet. The mock repositories wait like a network.
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/booking/data/mock/mock_booking_db.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_rules.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_views.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_wallet_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/commerce/data/member_wallet_api_service.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/domain/commerce_status.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';

Matcher apiError(int status, [String? code]) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.code, 'code', code ?? anything);

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

  void asMember() {
    userId = 'u_me';
    role = UserRole.user;
  }

  void asTam() {
    userId = 'u_chef_tam';
    role = UserRole.chef;
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 3); // 10:00 VN
    MockCommerceDb.reset(clock: () => now);
    MockMealPlannerRepository.reset();
    asMember();
  });

  CreateBookingRequestDto request({
    BookingAudience audience = BookingAudience.self,
    int? familySize,
    bool share = true,
    String needs = 'Mình cần thực đơn chay đủ chất, bữa sáng dưới 15 phút.',
    BookingType type = BookingType.oneShot,
    int days = 3,
  }) =>
      CreateBookingRequestDto(
        chefId: 'u_chef_tam',
        bookingType: type,
        planDays: days,
        startDate: DateTime(2026, 10, 20),
        audience: audience,
        familySize: familySize,
        goal: 'lose_weight',
        allergies: const ['peanut'],
        mealPattern: MealPattern.standard,
        needs: needs,
        shareHealthProfile: share,
      );

  /// Requested, quoted by Tâm, accepted by the member: waiting for payment.
  Future<BookingDto> agreed(
      {int days = 3, BookingType type = BookingType.oneShot}) async {
    asMember();
    final created =
        await bookings.createBooking(request(days: days, type: type));
    asTam();
    final quoted = await bookings.sendOffer(
        created.id,
        OfferRequestDto(
            price: 150000 * days,
            planDays: days,
            bookingType: type,
            startDate: DateTime(2026, 10, 20)));
    asMember();
    return bookings.respondToOffer(created.id, quoted.currentOffer!.id,
        accept: true);
  }

  Future<BookingDto> paid(
      {int days = 3, BookingType type = BookingType.oneShot}) async {
    final b = await agreed(days: days, type: type);
    final order = await bookings.startPayment(b.id);
    await commerce.mockConfirmPayment(order.payment!.id, success: true);
    return bookings.getBooking(b.id);
  }

  /// Paid, with the whole one-shot plan sent by Tâm.
  Future<BookingDto> delivered({int days = 3}) async {
    final b = await paid(days: days);
    asTam();
    for (var day = 1; day <= days; day++) {
      await bookings.savePlanDay(b.id, day, _fullDay(day));
    }
    await bookings.sendWholePlan(b.id);
    asMember();
    return bookings.getBooking(b.id);
  }

  group('for whom', () {
    test(
        'family: the wire has no goal or health sharing, whatever the form says',
        () {
      final json =
          request(audience: BookingAudience.family, familySize: 4).toJson();
      expect(json['audience'], 'Family');
      expect(json['familySize'], 4);
      expect(json.containsKey('goal'), isFalse);
      expect(json['shareHealthProfile'], isFalse);
      expect(json['allergies'], ['peanut']);
      expect(json['mealPattern'], isNotEmpty);
    });

    test('self without sharing: no goal either; with sharing: goal is sent',
        () {
      final off = request(share: false).toJson();
      expect(off['audience'], 'Self');
      expect(off.containsKey('goal'), isFalse);
      expect(off['shareHealthProfile'], isFalse);
      expect(off.containsKey('familySize'), isFalse);
      final on = request().toJson();
      expect(on['goal'], 'lose_weight');
      expect(on['shareHealthProfile'], isTrue);
    });

    test('family booking stored: none of the personal data reaches the chef',
        () async {
      final created = await bookings.createBooking(request(
          audience: BookingAudience.family,
          familySize: 5,
          needs: 'Nhà có bé.'));
      asTam();
      final b = await bookings.getBooking(created.id);
      expect(b.isFamily, isTrue);
      expect(b.audienceLabel, 'Gia đình · 5 người');
      expect(b.goal, isNull);
      expect(b.shareHealthProfile, isFalse);
      expect(b.memberHealth, isNull);
      expect(b.allergies, ['peanut']);
      final quoted = await bookings.sendOffer(
          b.id,
          OfferRequestDto(
              price: 450000,
              planDays: 3,
              bookingType: BookingType.oneShot,
              startDate: DateTime(2026, 10, 20)));
      asMember();
      final accepted = await bookings
          .respondToOffer(b.id, quoted.currentOffer!.id, accept: true);
      expect(accepted.contract!.scopeText, contains('cho gia đình 5 người'));
      expect(accepted.contract!.scopeText, isNot(contains('hồ sơ')));
      expect(accepted.contract!.scopeText, contains('tránh hoàn toàn'));
    });

    test('family: the note is optional, the number of people is checked',
        () async {
      await expectLater(
          bookings.createBooking(
              request(audience: BookingAudience.family, familySize: 1)),
          throwsA(apiError(400)));
      await expectLater(
          bookings.createBooking(
              request(audience: BookingAudience.family, familySize: 21)),
          throwsA(apiError(400)));
      final b = await bookings.createBooking(
          request(audience: BookingAudience.family, familySize: 2, needs: ''));
      expect(b.needs, isEmpty);
      final chat = await bookings.messages(b.id);
      expect(chat.where((m) => m.kind == MessageKind.text), isEmpty,
          reason: 'no empty bubble');
    });

    test('self: needs are still required', () async {
      await expectLater(bookings.createBooking(request(needs: 'Ngắn')),
          throwsA(apiError(400)));
    });

    test('old data without the field reads as "Cho tôi"; seeds show both',
        () async {
      asTam();
      final inbox = {for (final b in await bookings.chefInbox()) b.id: b};
      expect(inbox['b_nam_tam_req']!.audienceLabel, 'Cho tôi');
      final chau = inbox['b_chau_tam_ready']!;
      expect(chau.audienceLabel, 'Gia đình · 3 người');
      expect(chau.goal, isNull);
      expect(chau.memberHealth, isNull);
      expect(inbox['b_han_tam_done']!.audienceLabel, 'Gia đình · 4 người');
    });
  });

  group('sharing the profile: what is sent matches the card', () {
    test('switch on: exactly the listed fields; off: nothing personal',
        () async {
      final on = await bookings.createBooking(request());
      expect(on.goal, 'lose_weight');
      final health = on.memberHealth!;
      expect(health.rows.map((r) => r.$1).toList(), [
        'Chiều cao',
        'Cân nặng',
        'BMI',
        'Giới tính',
        'Tuổi',
        'Nhu cầu năng lượng',
      ]);
      expect(health.rows.first.$2, '172 cm');
      expect(MockBookingDb.instance.find(on.id)!.memberHealth!.keys.toSet(), {
        'heightCm',
        'weightKg',
        'bmi',
        'gender',
        'age',
        'dailyKcalTarget',
      });

      final off = await bookings.createBooking(request(share: false));
      expect(off.goal, isNull);
      expect(off.shareHealthProfile, isFalse);
      expect(off.memberHealth, isNull);
      expect(off.allergies, ['peanut'], reason: 'allergies always go');
    });

    test('hybrid build: the chef gets what the card showed, not the persona',
        () async {
      final b = await bookings.createBooking(CreateBookingRequestDto(
        chefId: 'u_chef_tam',
        bookingType: BookingType.oneShot,
        planDays: 3,
        startDate: DateTime(2026, 10, 20),
        goal: 'maintain',
        allergies: const [],
        mealPattern: MealPattern.standard,
        needs: 'Mình cần thực đơn chay đủ chất, bữa sáng dưới 15 phút.',
        healthSnapshot: const {'heightCm': 180, 'weightKg': 75, 'bmi': 23.1},
      ));
      expect(b.memberHealth!.heightCm, 180);
      expect(b.memberHealth!.rows.map((r) => r.$1),
          ['Chiều cao', 'Cân nặng', 'BMI']);
    });
  });

  group('money flow', () {
    test('paying holds the money with no release date yet', () async {
      final b = await paid();
      expect(b.status, BookingStatus.active);
      expect(b.escrow!.status, EscrowStatus.held);
      expect(b.escrow!.releaseAt, isNull);
      expect(b.completedAt, isNull);
      expect(b.contract!.holdDays, 7);
    });

    test("confirming waits for every day and the plan's last day", () async {
      final b = await paid();
      asTam();
      await expectLater(bookings.confirmCompletion(b.id),
          throwsA(apiError(409, 'plan_not_delivered')));
      for (var day = 1; day <= 3; day++) {
        await bookings.savePlanDay(b.id, day, _fullDay(day));
      }
      await bookings.sendWholePlan(b.id);
      // A one-shot plan is delivered before it starts: not on day 1.
      now = DateTime.utc(2026, 10, 20, 3);
      await expectLater(bookings.confirmCompletion(b.id),
          throwsA(apiError(409, 'plan_not_delivered')));
      // The plan runs 20–22/10; 22/10 00:00 VN = 21/10 17:00 UTC.
      now = DateTime.utc(2026, 10, 21, 17);
      final done = await bookings.confirmCompletion(b.id);
      expect(done.status, BookingStatus.ended);
      expect(done.completedAt!.toUtc(), now);
      expect(done.escrow!.completedAt!.toUtc(), now);
      expect(done.escrow!.releaseAt!.toUtc(), DateTime.utc(2026, 10, 28, 17));
    });

    test('a complaint during the 7 days freezes it until an admin decides',
        () async {
      final b = await delivered();
      now = DateTime.utc(2026, 10, 22, 3);
      asTam();
      final done = await bookings.confirmCompletion(b.id);
      expect(done.status, BookingStatus.ended);
      asMember();
      now = now.add(const Duration(days: 6));
      await bookings.fileComplaint(
          b.id,
          const ComplaintRequestDto(
            reason: ComplaintReason.notAsAgreed,
            description:
                'Kế hoạch không đúng yêu cầu ít dầu mà hai bên đã thoả thuận.',
            requestedOutcome: RequestedOutcome.fullRefund,
            evidence: [
              EvidenceDto(
                  kind: EvidenceKind.image,
                  url: 'https://res.cloudinary.com/a.jpg'),
            ],
          ));
      now = now.add(const Duration(days: 30));
      var after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.disputed);
      expect(after.escrow!.status, EscrowStatus.frozen);
      asTam();
      expect(
          (await chefWallet.getWallet()).frozen, greaterThanOrEqualTo(405000));
      await expectLater(bookings.confirmCompletion(b.id),
          throwsA(apiError(409, 'has_open_complaint')));
      asMember();
      MockBookingDb.instance
          .decideComplaint(b.id, decision: ComplaintDecision.releaseToChef);
      after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.resolved);
      expect(after.escrow!.status, EscrowStatus.released);
    });

    test('a complaint before the chef confirms freezes it too', () async {
      final b = await delivered();
      await bookings.fileComplaint(
          b.id,
          const ComplaintRequestDto(
            reason: ComplaintReason.notAsAgreed,
            description:
                'Kế hoạch không đúng yêu cầu ít dầu mà hai bên đã thoả thuận.',
            requestedOutcome: RequestedOutcome.fullRefund,
            evidence: [
              EvidenceDto(
                  kind: EvidenceKind.image,
                  url: 'https://res.cloudinary.com/a.jpg'),
            ],
          ));
      final after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.disputed);
      expect(after.escrow!.status, EscrowStatus.frozen);
      expect(after.escrow!.releaseAt, isNull);
    });

    test('past the hold there is no complaint window left', () async {
      final b = await delivered();
      now = DateTime.utc(2026, 10, 22, 3);
      asTam();
      await bookings.confirmCompletion(b.id);
      asMember();
      now = now.add(const Duration(days: 7));
      final after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.completed);
      expect(after.canComplain(now), isFalse);
      await expectLater(
          bookings.fileComplaint(
              b.id,
              const ComplaintRequestDto(
                reason: ComplaintReason.other,
                description:
                    'Mình muốn khiếu nại sau khi hết hạn giữ tiền của hợp đồng.',
                requestedOutcome: RequestedOutcome.fullRefund,
                evidence: [
                  EvidenceDto(
                      kind: EvidenceKind.image,
                      url: 'https://res.cloudinary.com/a.jpg'),
                ],
              )),
          throwsA(apiError(409, 'not_open')));
    });

    test('never delivered in full: no release; a complaint can get it back',
        () async {
      final b = await paid(type: BookingType.dailyFeedback);
      asTam();
      await bookings.savePlanDay(b.id, 1, _fullDay(1));
      await bookings.sendPlanDay(b.id, 1);
      now = DateTime.utc(2027, 1, 1);
      await expectLater(bookings.confirmCompletion(b.id),
          throwsA(apiError(409, 'plan_not_delivered')));
      asMember();
      var after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.active);
      expect(after.escrow!.status, EscrowStatus.held);
      expect(after.escrow!.releaseAt, isNull);
      await bookings.fileComplaint(
          b.id,
          const ComplaintRequestDto(
            reason: ComplaintReason.lateOrMissing,
            description:
                'Kế hoạch đã kết thúc từ lâu mà chuyên gia chưa giao đủ các ngày.',
            requestedOutcome: RequestedOutcome.fullRefund,
            evidence: [
              EvidenceDto(
                  kind: EvidenceKind.image,
                  url: 'https://res.cloudinary.com/a.jpg'),
            ],
          ));
      // The admin refunds: the member's wallet gets it.
      final before = (await wallet.getWallet()).available;
      MockBookingDb.instance
          .decideComplaint(b.id, decision: ComplaintDecision.refundMember);
      after = await bookings.getBooking(b.id);
      expect(after.escrow!.status, EscrowStatus.refunded);
      expect(
          (await wallet.getWallet()).available, before + after.contract!.price);
    });
  });

  group('a chef who never confirms', () {
    // The plan runs 20–22/10, so the moment is 25/10 23:59 VN.
    final moment = DateTime.utc(2026, 10, 25, 16, 59);
    final oneMinuteEarlier = moment.subtract(const Duration(minutes: 1));
    final release = DateTime.utc(2026, 11, 1, 16, 59);

    test('all delivered: completes at that moment, then the usual 7-day hold',
        () async {
      final b = await delivered();
      now = oneMinuteEarlier;
      var after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.active);
      expect(after.completedAt, isNull);
      expect(after.autoCompleted, isFalse);

      now = moment;
      after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.ended);
      expect(after.completedAt!.toUtc(), moment);
      expect(after.autoCompleted, isTrue);
      expect(after.escrow!.status, EscrowStatus.held);
      expect(after.escrow!.completedAt!.toUtc(), moment);
      expect(after.escrow!.releaseAt!.toUtc(), release);
      expect(after.canComplain(now), isTrue, reason: 'the hold is still open');
      final messages = await bookings.messages(b.id);
      expect(messages.last.body, contains(autoCompletedNote));

      // Too late to confirm by hand, and the chef reads the same state.
      asTam();
      final seenByChef = await bookings.getBooking(b.id);
      expect(seenByChef.autoCompleted, isTrue);
      expect(seenByChef.canConfirmCompletion(now), isFalse);
      await expectLater(bookings.confirmCompletion(b.id),
          throwsA(apiError(409, 'not_active')));
      final heldBefore = await chefWallet.getWallet();

      now = release.subtract(const Duration(minutes: 1));
      expect((await bookings.getBooking(b.id)).status, BookingStatus.ended);

      now = release;
      const net = 450000 - 45000;
      final done = await bookings.getBooking(b.id);
      expect(done.status, BookingStatus.completed);
      expect(done.autoCompleted, isTrue);
      expect(done.escrow!.status, EscrowStatus.released);
      expect(done.escrow!.releasedAt!.toUtc(), release);
      final released = await chefWallet.getWallet();
      expect(released.available, heldBefore.available + net);
      final rows = await chefWallet.transactions();
      final row = rows.singleWhere((t) => t.bookingId == b.id);
      expect(row.net, net);
      expect(row.status, LedgerStatus.available);
    });

    test('a first read long after gives the same dates as a job on time',
        () async {
      final b = await delivered();
      now = DateTime.utc(2027, 1, 1);
      final after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.completed);
      expect(after.completedAt!.toUtc(), moment);
      expect(after.escrow!.releaseAt!.toUtc(), release);
      expect(after.escrow!.releasedAt!.toUtc(), release);
    });

    test('the chef confirming in time is not an auto-completion', () async {
      final b = await delivered();
      asTam();
      now = DateTime.utc(2026, 10, 22, 3);
      final done = await bookings.confirmCompletion(b.id);
      expect(done.autoCompleted, isFalse);
      now = moment.add(const Duration(days: 1));
      final after = await bookings.getBooking(b.id);
      expect(after.autoCompleted, isFalse);
      expect(after.completedAt!.toUtc(), DateTime.utc(2026, 10, 22, 3));
    });

    test('an open complaint blocks it', () async {
      final b = await delivered();
      now = DateTime.utc(2026, 10, 23, 3);
      await bookings.fileComplaint(
          b.id,
          const ComplaintRequestDto(
            reason: ComplaintReason.notAsAgreed,
            description:
                'Kế hoạch không đúng yêu cầu ít dầu mà hai bên đã thoả thuận.',
            requestedOutcome: RequestedOutcome.fullRefund,
            evidence: [
              EvidenceDto(
                  kind: EvidenceKind.image,
                  url: 'https://res.cloudinary.com/a.jpg'),
            ],
          ));
      now = DateTime.utc(2027, 1, 1);
      final after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.disputed);
      expect(after.completedAt, isNull);
      expect(after.autoCompleted, isFalse);
      expect(after.escrow!.status, EscrowStatus.frozen);
      expect(after.escrow!.releaseAt, isNull);
    });

    test('days missing: stays held, the member complains, the chef must act',
        () async {
      final b = await paid(type: BookingType.dailyFeedback);
      asTam();
      await bookings.savePlanDay(b.id, 1, _fullDay(1));
      await bookings.sendPlanDay(b.id, 1);
      asMember();

      now = oneMinuteEarlier;
      var after = await bookings.getBooking(b.id);
      expect(after.overdueUndelivered(now), isFalse);
      expect(memberNeedsAction(after, now), isFalse);

      now = moment;
      after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.active);
      expect(after.completedAt, isNull);
      expect(after.autoCompleted, isFalse);
      expect(after.escrow!.status, EscrowStatus.held);
      expect(after.escrow!.releaseAt, isNull);
      expect(after.overdueUndelivered(now), isTrue);
      expect(memberNeedsAction(after, now), isTrue);
      expect(chefNeedsAction(after, now), isTrue);
      expect(after.canComplain(now), isTrue);
      expect(after.canCancelPaid, isFalse, reason: 'a day was delivered');

      // It never moves on its own, however long it waits.
      now = DateTime.utc(2027, 1, 1);
      after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.active);
      expect(after.escrow!.status, EscrowStatus.held);
    });

    test('a day sent after the moment leaves it to the chef or a complaint',
        () async {
      final b = await paid();
      asTam();
      for (var day = 1; day <= 3; day++) {
        await bookings.savePlanDay(b.id, day, _fullDay(day));
      }
      now = moment.add(const Duration(hours: 1));
      await bookings.sendWholePlan(b.id);
      final late = await bookings.getBooking(b.id);
      expect(late.status, BookingStatus.active);
      expect(late.autoCompleted, isFalse);
      expect(late.overdueUndelivered(now), isFalse);
      expect(late.canConfirmCompletion(now), isTrue);
      expect(chefNeedsAction(late, now), isTrue);
      final done = await bookings.confirmCompletion(b.id);
      expect(done.autoCompleted, isFalse);
      expect(done.completedAt!.toUtc(), now);
    });

    test('the seeds show both cases', () async {
      final auto = await bookings.getBooking('b_ma_tam_auto');
      expect(auto.status, BookingStatus.ended);
      expect(auto.autoCompleted, isTrue);
      // The plan ended 6 days ago (17/10 is "today"), so 3 days ago at 23:59 VN.
      expect(auto.completedAt!.toUtc(), DateTime.utc(2026, 10, 14, 16, 59));
      expect(
          auto.escrow!.releaseAt!.toUtc(), DateTime.utc(2026, 10, 21, 16, 59));

      final short = await bookings.getBooking('b_ma_tam_short');
      expect(short.status, BookingStatus.active);
      expect(short.deliveredDays, 3);
      expect(short.overdueUndelivered(now), isTrue);
      expect(short.escrow!.releaseAt, isNull);
    });
  });

  group("member's wallet", () {
    test('seeded: a refund less a withdrawal', () async {
      final w = await wallet.getWallet();
      expect(w.available, 1600000);
      expect(w.withdrawn, 200000);
      expect(w.pending, 0);
      expect(w.bankAccount!.masked, '•••• 6789');
      final history = await wallet.transactions();
      final refund =
          history.firstWhere((t) => t.type == WalletEntryType.refund);
      expect(refund.net, 1800000);
      expect(refund.bookingId, 'b_ma_thuha_refund');
      final out =
          history.firstWhere((t) => t.type == WalletEntryType.withdrawal);
      expect(out.net, -200000);
      expect(out.status, LedgerStatus.completed);
    });

    test('a guest gets 401', () async {
      userId = null;
      await expectLater(wallet.getWallet(), throwsA(apiError(401)));
    });

    test('cancelling after paying: the whole price comes to the wallet',
        () async {
      final b = await paid();
      expect(b.canCancelPaid, isTrue);
      final before = (await wallet.getWallet()).available;
      final after = await bookings.cancel(b.id, 'Mình đổi lịch rồi ạ');
      expect(after.status, BookingStatus.cancelled);
      expect(after.escrow!.status, EscrowStatus.refunded);
      expect(after.escrow!.refundedAmount, 450000);
      expect(memberOutcome(after), 'Đã hoàn 450.000đ vào Ví của tôi');
      expect((await wallet.getWallet()).available, before + 450000);
      expect((await commerce.getOrder(after.paymentOrderId!)).status,
          OrderStatus.refunded);
      asTam();
      final row = (await chefWallet.transactions())
          .singleWhere((t) => t.id == 'tx_in_${b.id}');
      expect(row.status, LedgerStatus.reversed);
    });

    test('once a day is delivered it can only be a complaint', () async {
      final b = await delivered();
      expect(b.canCancelPaid, isFalse);
      await expectLater(bookings.cancel(b.id, 'Mình đổi lịch rồi ạ'),
          throwsA(apiError(409, 'plan_started')));
    });

    test('a split decision: the refund part goes to the wallet', () async {
      final before = (await wallet.getWallet()).available;
      const id = 'b_ma_thuha_active';
      await bookings.fileComplaint(
          id,
          const ComplaintRequestDto(
            reason: ComplaintReason.notAsAgreed,
            description:
                'Kế hoạch không đúng yêu cầu ít dầu mà hai bên đã thoả thuận.',
            requestedOutcome: RequestedOutcome.partialRefund,
            requestedAmount: 300000,
            evidence: [
              EvidenceDto(
                  kind: EvidenceKind.image,
                  url: 'https://res.cloudinary.com/a.jpg'),
            ],
          ));
      MockBookingDb.instance.decideComplaint(id,
          decision: ComplaintDecision.split, refundAmount: 300000);
      expect((await wallet.getWallet()).available, before + 300000);
    });

    test('a payment after the booking closed comes back to the wallet',
        () async {
      final b = await agreed();
      final order = await bookings.startPayment(b.id);
      asTam();
      await bookings.decline(b.id, 'Lịch của mình đã kín trong 2 tuần tới.');
      asMember();
      final before = (await wallet.getWallet()).available;
      // The QR stopped working; a transfer that still lands is refunded.
      MockCommerceDb.instance
          .markPaid(MockCommerceDb.instance.payment(order.payment!.id));
      expect((await wallet.getWallet()).available, before + 450000);
    });

    test('paying from the wallet funds the escrow and stops the QR', () async {
      final b = await agreed();
      final order = await bookings.startPayment(b.id);
      final paidOrder = await commerce.payWithWallet(order.id);
      expect(paidOrder.status, OrderStatus.paid);
      expect(paidOrder.payment!.provider, 'Wallet');
      expect(paidOrder.escrow!.status, EscrowStatus.held);
      expect((await wallet.getWallet()).available, 1600000 - 450000);
      final after = await bookings.getBooking(b.id);
      expect(after.status, BookingStatus.active);
      final history = await wallet.transactions();
      final payment =
          history.firstWhere((t) => t.type == WalletEntryType.payment);
      expect(payment.net, -450000);
      expect(payment.bookingId, b.id);
      await expectLater(
          commerce.mockConfirmPayment(order.payment!.id, success: true),
          throwsA(apiError(409, 'payment_expired')),
          reason: 'the old QR is dead, nobody pays twice');
      await expectLater(commerce.payWithWallet(order.id),
          throwsA(apiError(409, 'not_awaiting_payment')));
    });

    test('a balance below the price is refused: no partial payment', () async {
      final nego = await bookings.getBooking('b_ma_tam_nego');
      await bookings.respondToOffer(nego.id, nego.currentOffer!.id,
          accept: true);
      final order = await bookings.startPayment(nego.id);
      MockCommerceDb.instance.walletEntries
          .removeWhere((e) => e.userId == 'u_me');
      await expectLater(commerce.payWithWallet(order.id),
          throwsA(apiError(409, 'insufficient_balance')));
    });

    test('withdrawing: minimum, balance, bank account, an admin decides',
        () async {
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 50000)),
          throwsA(apiError(400, 'amount_too_small')));
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 1600001)),
          throwsA(apiError(409, 'insufficient_balance')));
      final w = await wallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 600000));
      expect(w.status, LedgerStatus.processing);
      expect(w.accountNumber, '•••• 6789');
      var balance = await wallet.getWallet();
      expect(balance.available, 1000000);
      expect(balance.processing, 600000);

      await wallet.mockDecideWithdrawal(w.id, approve: false);
      balance = await wallet.getWallet();
      expect(balance.available, 1600000,
          reason: 'refused: back in the balance');
      final refused = await wallet.withdrawals();
      expect(refused.first.status, LedgerStatus.rejected);

      final again = await wallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 600000));
      await wallet.mockDecideWithdrawal(again.id, approve: true);
      balance = await wallet.getWallet();
      expect(balance.available, 1000000);
      expect(balance.withdrawn, 800000);

      await expectLater(wallet.mockDecideWithdrawal('wd_tam_3', approve: true),
          throwsA(apiError(404)),
          reason: "another wallet's request");
      MockCommerceDb.instance.bankAccounts.remove('u_me');
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 100000)),
          throwsA(apiError(409, 'no_bank_account')));
    });

    test('bank account: same rules, #fail, one per user', () async {
      await expectLater(
          wallet.saveBankAccount(const BankAccountDto(
              bankName: 'ACB',
              accountNumber: '123456789',
              accountHolder: 'MINH ANH #fail')),
          throwsA(apiError(503)));
      await expectLater(
          wallet.saveBankAccount(const BankAccountDto(
              bankName: 'ACB', accountNumber: '12', accountHolder: 'MINH ANH')),
          throwsA(apiError(400)));
      final saved = await wallet.saveBankAccount(const BankAccountDto(
          bankName: 'ACB',
          accountNumber: '123456789',
          accountHolder: 'minh anh'));
      expect(saved.accountHolder, 'MINH ANH');
      asTam();
      expect(
          (await chefWallet.getWallet()).bankAccount!.bankName, 'Vietcombank');
    });

    test('MOCK_COMMERCE_SCENARIO empties or fails the wallet', () async {
      MockCommerceDb.scenario = 'empty';
      expect((await wallet.getWallet()).available, 0);
      expect(await wallet.transactions(), isEmpty);
      expect(await wallet.withdrawals(), isEmpty);
      MockCommerceDb.scenario = 'error';
      await expectLater(wallet.getWallet(), throwsA(apiError(503)));
      await expectLater(wallet.transactions(), throwsA(apiError(503)));
    });

    test("one wallet per user: a chef's refund and earnings are one balance",
        () async {
      asTam();
      expect((await wallet.getWallet()).available, 110000);
      expect((await chefWallet.getWallet()).available, 110000);
      MockCommerceDb.instance.walletEntries.add(MockWalletEntryRow(
        id: 'wtx_test',
        userId: 'u_chef_tam',
        type: 'Refund',
        amount: 500000,
        createdAt: now,
        planTitle: 'Thực đơn 3 ngày',
      ));
      expect((await wallet.getWallet()).available, 610000);
      expect((await chefWallet.getWallet()).available, 610000);
      final rows = await chefWallet.transactions();
      expect(rows.singleWhere((t) => t.id == 'wtx_test').net, 500000);
    });

    test('withdrawals carry the role that asked', () async {
      await wallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 100000));
      final db = MockCommerceDb.instance;
      expect(db.withdrawals.last.role, 'member');
      expect(db.withdrawals.last.userId, 'u_me');
      asTam();
      await chefWallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 100000));
      expect(db.withdrawals.last.role, 'chef');
      expect(db.withdrawals.last.userId, 'u_chef_tam');
    });

    test('a refund leaves the payment Paid; the order shows it', () async {
      final b = await paid();
      await bookings.cancel(b.id, 'Mình đổi lịch rồi ạ');
      final order = await commerce.getOrder(b.paymentOrderId!);
      expect(order.status, OrderStatus.refunded);
      expect(order.payment!.status, PaymentStatus.paid);
    });
  });
}
