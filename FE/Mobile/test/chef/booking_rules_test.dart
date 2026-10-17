// test/chef/booking_rules_test.dart
// Pure booking rules: dates in Asia/Ho_Chi_Minh, escrow release, decision
// math, form rules, inbox grouping and DTO parsing.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_rules.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_views.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';

BookingDto _booking({
  BookingStatus status = BookingStatus.active,
  BookingType type = BookingType.dailyFeedback,
  String start = '2026-10-15',
  int days = 7,
  int delivered = 0,
  Map<String, dynamic>? offer,
  Map<String, dynamic>? contract,
  Map<String, dynamic>? complaint,
}) =>
    BookingDto.fromJson({
      'id': 'b1',
      'member': {'id': 'u_me', 'fullName': 'Minh Anh'},
      'chef': {'id': 'u_chef_tam', 'fullName': 'Lê Quang Tâm'},
      'bookingType': type.apiValue,
      'planDays': days,
      'startDate': start,
      'status': status.apiValue,
      'deliveredDays': delivered,
      'currentOffer': offer,
      'contract': contract,
      'complaint': complaint,
      'createdAt': '2026-10-10T03:00:00Z',
    });

void main() {
  group('dates (Asia/Ho_Chi_Minh)', () {
    test('VN day of an instant and VN wall-clock instants', () {
      // 17:30 UTC on the 16th is 00:30 on the 17th in Vietnam.
      expect(
          vnDateOf(DateTime.utc(2026, 10, 16, 17, 30)), DateTime(2026, 10, 17));
      expect(
          vnTime(DateTime(2026, 10, 20), 6, 0), DateTime.utc(2026, 10, 19, 23));
      expect(formatVnStamp(DateTime.utc(2026, 10, 22, 16, 59)),
          '23:59, 22/10/2026');
    });

    test('end date and release date across the month end', () {
      final start = DateTime(2026, 10, 28);
      final end = planEndDate(start, 7);
      expect(end, DateTime(2026, 11, 3));
      // end 23:59 VN + 3 days = 6/11 23:59 VN = 6/11 16:59 UTC.
      expect(escrowReleaseAt(end), DateTime.utc(2026, 11, 6, 16, 59));
      expect(planEndDate(DateTime(2026, 12, 30), 3), DateTime(2027, 1, 1));
      expect(escrowReleaseAt(DateTime(2026, 12, 30)),
          DateTime.utc(2027, 1, 2, 16, 59));
    });

    test('delivery deadline: OneShot max(start, paid + 24 h); daily 06:00', () {
      final start = DateTime(2026, 10, 20);
      // Paid long before: the start of the plan.
      expect(
          deliveryDueAt(
              BookingType.oneShot, start, DateTime.utc(2026, 10, 10, 3)),
          vnTime(start, 0, 0));
      // Paid the evening before: 24 h after payment.
      final late = DateTime.utc(2026, 10, 19, 12);
      expect(deliveryDueAt(BookingType.oneShot, start, late),
          late.add(const Duration(hours: 24)));
      expect(deliveryDueAt(BookingType.dailyFeedback, start, late),
          vnTime(start, 6, 0));
      expect(
          formatVnDeadline(dailySendDeadline(start, 5)), '06:00 Thứ Bảy 24/10');
    });
  });

  test('decision math: release, full refund, split with the 10% fee', () {
    final release = decisionOutcome(1050000, ComplaintDecision.releaseToChef);
    expect((release.refund, release.chefGross, release.fee, release.chefNet),
        (0, 1050000, 105000, 945000));
    final refund = decisionOutcome(1050000, ComplaintDecision.refundMember);
    expect((refund.refund, refund.chefGross, refund.fee), (1050000, 0, 0));
    final split = decisionOutcome(1050000, ComplaintDecision.split, 300000);
    expect((split.refund, split.chefGross, split.fee, split.chefNet),
        (300000, 750000, 75000, 675000));
  });

  group('form rules', () {
    test('days, price and start date bounds', () {
      expect(BookingRules.planDays(2), isNotNull);
      expect(BookingRules.planDays(3), isNull);
      expect(BookingRules.planDays(30), isNull);
      expect(BookingRules.planDays(31), isNotNull);
      expect(BookingRules.price(99999), isNotNull);
      expect(BookingRules.price(100000), isNull);
      expect(BookingRules.price(50000000), isNull);
      expect(BookingRules.price(50000001), isNotNull);
      final today = DateTime(2026, 10, 17);
      expect(BookingRules.startDate(today, today),
          'Ngày bắt đầu từ ngày mai trở đi.');
      expect(BookingRules.startDate(DateTime(2026, 10, 18), today), isNull);
    });

    test('needs, notes and reasons', () {
      expect(BookingRules.needs('Ngắn quá'), contains('ít nhất 20'));
      expect(BookingRules.needs('Mình cần thực đơn giảm cân 10 ngày.'), isNull);
      expect(BookingRules.offerNote('x' * 301), isNotNull);
      expect(BookingRules.message(''), isNotNull);
      expect(BookingRules.message('x' * 1001), isNotNull);
      expect(BookingRules.declineReason('Bận'), isNotNull);
      expect(BookingRules.declineReason('Lịch đã kín 2 tuần'), isNull);
    });

    test('complaint: evidence required, a link for health risk, 5 images', () {
      expect(BookingRules.complaintDescription('Ngắn'), isNotNull);
      expect(BookingRules.evidence(ComplaintReason.notAsAgreed, const []),
          contains('ít nhất 1'));
      expect(
          BookingRules.evidence(
              ComplaintReason.healthRisk, const [EvidenceKind.image]),
          'Hãy đính kèm nguồn (bài báo, tài liệu y khoa) chứng minh');
      expect(
          BookingRules.evidence(ComplaintReason.healthRisk,
              const [EvidenceKind.image, EvidenceKind.link]),
          isNull);
      expect(
          BookingRules.evidence(
              ComplaintReason.other, List.filled(6, EvidenceKind.image)),
          'Tối đa 5 ảnh.');
      expect(BookingRules.partialRefund(999, 1050000), isNotNull);
      expect(BookingRules.partialRefund(1050000, 1050000), isNotNull);
      expect(BookingRules.partialRefund(500000, 1050000), isNull);
      expect(BookingRules.isHttpUrl('https://www.fda.gov/a'), isTrue);
      expect(BookingRules.isHttpUrl('fda.gov'), isFalse);
    });

    test('off-platform words in the chat', () {
      expect(BookingRules.mentionsOffPlatform('Kết bạn Zalo nhé'), isTrue);
      expect(BookingRules.mentionsOffPlatform('sđt của mình'), isTrue);
      expect(BookingRules.mentionsOffPlatform('chuyển khoản riêng cho rẻ'),
          isTrue);
      expect(BookingRules.mentionsOffPlatform('gọi 0912345678'), isTrue);
      expect(
          BookingRules.mentionsOffPlatform('Bữa tối hơi nhiều dầu'), isFalse);
    });
  });

  group('inbox and history grouping', () {
    final now = DateTime.utc(2026, 10, 17, 3); // 10:00 VN

    test('tabs by status', () {
      expect(InboxTab.of(BookingStatus.requested), InboxTab.fresh);
      expect(InboxTab.of(BookingStatus.awaitingPayment), InboxTab.negotiating);
      expect(InboxTab.of(BookingStatus.disputed), InboxTab.inProgress);
      expect(InboxTab.of(BookingStatus.resolved), InboxTab.finished);
      expect(BookingStatus.ended.isOngoing, isTrue);
      expect(BookingStatus.expired.isOngoing, isFalse);
    });

    test('what waits on the chef', () {
      expect(chefNeedsAction(_booking(status: BookingStatus.requested), now),
          isTrue);
      final memberOffer = {
        'id': 'of1',
        'proposedBy': 'member',
        'price': 1200000,
        'planDays': 7,
        'bookingType': 'DailyFeedback',
        'startDate': '2026-10-20',
        'status': 'Open',
        'createdAt': '2026-10-16T03:00:00Z',
      };
      expect(
          chefNeedsAction(
              _booking(status: BookingStatus.negotiating, offer: memberOffer),
              now),
          isTrue);
      expect(
          chefNeedsAction(
              _booking(
                  status: BookingStatus.negotiating,
                  offer: {...memberOffer, 'proposedBy': 'chef'}),
              now),
          isFalse);
      expect(
          memberNeedsAction(_booking(
              status: BookingStatus.negotiating,
              offer: {...memberOffer, 'proposedBy': 'chef'})),
          isTrue);
      // Daily plan from the 15th: today is day 3; 2 sent → day 3 is due.
      expect(dueToday(_booking(delivered: 2), now), isTrue);
      expect(dueToday(_booking(delivered: 3), now), isFalse);
      expect(todayIndex(_booking(), now), 3);
    });

    test('progress steps', () {
      expect(bookingStep(_booking(status: BookingStatus.requested)), 1);
      expect(bookingStep(_booking(status: BookingStatus.awaitingPayment)), 2);
      expect(bookingStep(_booking(delivered: 2)), 3);
      expect(bookingStep(_booking(delivered: 7)), 4);
      expect(bookingStep(_booking(status: BookingStatus.completed)), 5);
    });
  });

  test('BookingDto parses the web sample (ids as strings, nested blocks)', () {
    final b = BookingDto.fromJson({
      'id': 604,
      'member': {'id': 7, 'fullName': 'Ngọc Trâm', 'email': 'a@b.vn'},
      'chef': {'id': 3, 'fullName': 'Lê Quang Tâm'},
      'bookingType': 'OneShot',
      'planDays': 7,
      'startDate': '2026-10-10',
      'mealPattern': ['breakfast', 'snack_pm', 'dinner'],
      'allergies': ['peanut'],
      'budgetPerDay': 90000,
      'status': 'Disputed',
      'deliveredDays': 7,
      'contract': {
        'id': 'ct',
        'price': 1050000,
        'planDays': 7,
        'bookingType': 'OneShot',
        'startDate': '2026-10-10',
        'endDate': '2026-10-16',
        'deliveryDueAt': '2026-10-09T17:00:00Z',
        'paymentDueAt': '2026-10-08T17:00:00Z',
        'createdAt': '2026-10-06T17:00:00Z',
      },
      'escrow': {
        'id': 'eh_604',
        'amount': 1050000,
        'status': 'Frozen',
        'heldAt': '2026-10-06T18:00:00Z',
        'releaseAt': '2026-10-19T16:59:00.000Z',
      },
      'complaint': {
        'id': 'cp_tram_tam',
        'reason': 'health_risk',
        'description': '…',
        'requestedOutcome': 'PartialRefund',
        'requestedAmount': 500000,
        'status': 'Open',
        'evidence': [
          {'id': 'e1', 'kind': 'Link', 'url': 'https://www.fda.gov/x'},
          {'id': 'e2', 'kind': 'Image', 'url': 'https://res/x.jpg'},
        ],
        'createdAt': '2026-10-17T00:00:00Z',
      },
      'createdAt': '2026-10-05T02:15:00Z',
    });
    expect(b.id, '604');
    expect(b.member.id, '7');
    expect(
        b.mealPattern, [MealSlot.breakfast, MealSlot.snackPm, MealSlot.dinner]);
    expect(b.status, BookingStatus.disputed);
    expect(b.price, 1050000);
    expect(b.contract!.fee, 105000);
    expect(b.contract!.releaseAt, DateTime.utc(2026, 10, 19, 16, 59));
    expect(b.escrow!.status, EscrowStatus.frozen);
    expect(b.complaint!.reason, ComplaintReason.healthRisk);
    expect(b.complaint!.evidence.map((e) => e.kind),
        [EvidenceKind.link, EvidenceKind.image]);
    expect(b.partyOf('3'), BookingParty.chef);
    expect(b.partyOf('7'), BookingParty.member);
    expect(b.partyOf('9'), isNull);
    // Frozen: no second complaint.
    expect(b.canComplain(DateTime.utc(2026, 10, 18)), isFalse);
  });
}
