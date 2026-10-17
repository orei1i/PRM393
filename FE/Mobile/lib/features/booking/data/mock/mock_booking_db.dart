// lib/features/booking/data/mock/mock_booking_db.dart
import 'package:flutter/foundation.dart';

import '../../../../core/utils/formatters.dart';
import '../../../chef_studio/domain/wallet_rules.dart';
import '../../../commerce/data/mock/mock_commerce_db.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../meal_planner/data/chef_suggestion_api_service.dart';
import '../../../meal_planner/domain/entities/health_profile.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../models/booking_models.dart';

part 'mock_booking_seeds.dart';

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

class MockOfferRow {
  MockOfferRow({
    required this.id,
    required this.proposedBy,
    required this.price,
    required this.planDays,
    required this.bookingType,
    required this.startDate,
    required this.note,
    required this.createdAt,
    this.status = OfferStatus.open,
  });

  final String id;
  final BookingParty proposedBy;
  final int price;
  final int planDays;
  final BookingType bookingType;
  final DateTime startDate;
  final String note;
  final DateTime createdAt;
  OfferStatus status;
  DateTime? respondedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'proposedBy': proposedBy.apiValue,
        'price': price,
        'planDays': planDays,
        'bookingType': bookingType.apiValue,
        'startDate': toApiDate(startDate),
        'note': note,
        'status': status.apiValue,
        'createdAt': _iso(createdAt),
        'respondedAt': _iso(respondedAt),
      };
}

class MockContractRow {
  MockContractRow({
    required this.id,
    required this.bookingId,
    required this.offerId,
    required this.price,
    required this.planDays,
    required this.bookingType,
    required this.startDate,
    required this.deliveryDueAt,
    required this.scopeText,
    required this.paymentDueAt,
    required this.createdAt,
  }) : endDate = planEndDate(startDate, planDays);

  final String id;
  final String bookingId;
  final String offerId;
  final int price;
  final int planDays;
  final BookingType bookingType;
  final DateTime startDate;
  final DateTime endDate;

  /// Set again from the payment time when the member pays (OneShot).
  DateTime deliveryDueAt;
  final String scopeText;
  final DateTime paymentDueAt;
  final DateTime createdAt;

  DateTime get releaseAt => escrowReleaseAt(endDate);

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'offerId': offerId,
        'price': price,
        'planDays': planDays,
        'bookingType': bookingType.apiValue,
        'startDate': toApiDate(startDate),
        'endDate': toApiDate(endDate),
        'deliveryDueAt': _iso(deliveryDueAt),
        'dailySendCutoff': BookingRules.dailySendCutoff,
        'feedbackCutoff': BookingRules.feedbackCutoff,
        'scopeText': scopeText,
        'feeRate': BookingRules.feeRate,
        'holdDays': BookingRules.holdDays,
        'paymentDueAt': _iso(paymentDueAt),
        'createdAt': _iso(createdAt),
      };
}

class MockEscrowRow {
  MockEscrowRow({
    required this.id,
    required this.bookingId,
    required this.paymentId,
    required this.amount,
    required this.heldAt,
    required this.releaseAt,
  });

  final String id;
  final String bookingId;
  final String paymentId;
  final int amount;
  final DateTime heldAt;
  final DateTime releaseAt;
  EscrowStatus status = EscrowStatus.held;
  DateTime? releasedAt;
  int releasedAmount = 0;
  int feeAmount = 0;
  int refundedAmount = 0;
  String? resolvedBy;
  String? resolutionNote;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'paymentId': paymentId,
        'amount': amount,
        'status': status.apiValue,
        'heldAt': _iso(heldAt),
        'releaseAt': _iso(releaseAt),
        'releasedAt': _iso(releasedAt),
        'releasedAmount': releasedAmount,
        'feeAmount': feeAmount,
        'refundedAmount': refundedAmount,
        'resolvedBy': resolvedBy,
        'resolutionNote': resolutionNote,
      };
}

class MockEvidenceRow {
  MockEvidenceRow({
    required this.id,
    required this.kind,
    required this.url,
    required this.submittedBy,
    required this.createdAt,
    this.caption,
  });

  final String id;
  final EvidenceKind kind;
  final String url;
  final String? caption;
  final BookingParty submittedBy;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.apiValue,
        'url': url,
        'caption': caption,
        'submittedBy': submittedBy.apiValue,
        'createdAt': _iso(createdAt),
      };
}

class MockComplaintRow {
  MockComplaintRow({
    required this.id,
    required this.bookingId,
    required this.reason,
    required this.description,
    required this.requestedOutcome,
    required this.requestedAmount,
    required this.createdAt,
  });

  final String id;
  final String bookingId;
  final ComplaintReason reason;
  final String description;
  final RequestedOutcome requestedOutcome;
  final int requestedAmount;
  final DateTime createdAt;
  ComplaintStatus status = ComplaintStatus.open;
  final evidence = <MockEvidenceRow>[];
  String? chefResponse;
  DateTime? chefRespondedAt;
  ComplaintDecision? decision;
  int? refundAmount;
  String? adminNote;
  String? decidedBy;
  DateTime? decidedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'reason': reason.apiValue,
        'description': description,
        'requestedOutcome': requestedOutcome.apiValue,
        'requestedAmount': requestedAmount,
        'status': status.apiValue,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'chefResponse': chefResponse,
        'chefRespondedAt': _iso(chefRespondedAt),
        'decision': decision?.apiValue,
        'refundAmount': refundAmount,
        'adminNote': adminNote,
        'decidedBy': decidedBy,
        'decidedAt': _iso(decidedAt),
        'createdAt': _iso(createdAt),
      };
}

class MockPlanDayRow {
  MockPlanDayRow({required this.dayIndex, required this.date});

  final int dayIndex;
  final DateTime date;

  /// `null`: not started ("Chưa soạn").
  PlanDayStatus? status;
  String? chefNote;
  DateTime? sentAt;
  List<PlanMealDto> meals = const [];
  DayFeedbackDto? feedback;

  bool get isSent => status == PlanDayStatus.sent;

  bool isComplete(Iterable<MealSlot> pattern) =>
      pattern.every((s) => meals.any((m) => m.slot == s));

  Map<String, dynamic> toJson() => {
        'dayIndex': dayIndex,
        'date': toApiDate(date),
        'status': status?.apiValue,
        'chefNote': chefNote,
        'sentAt': _iso(sentAt),
        'meals': meals.map((m) => m.toJson()).toList(),
        'feedback': feedback == null
            ? null
            : {
                ...feedback!.toRequestJson(),
                'createdAt': _iso(feedback!.createdAt),
              },
      };
}

class MockMessageRow {
  MockMessageRow({
    required this.id,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.offer,
    this.attachmentUrl,
  });

  String id;
  final String? senderId;
  final BookingParty senderRole;
  final String body;
  final MockOfferRow? offer;
  final String? attachmentUrl;
  final DateTime createdAt;

  MessageKind get kind => offer != null
      ? MessageKind.offer
      : attachmentUrl != null
          ? MessageKind.attachment
          : senderRole == BookingParty.system
              ? MessageKind.system
              : MessageKind.text;

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderRole': senderRole.apiValue,
        'kind': kind.apiValue,
        'body': body,
        'offerId': offer?.id,
        'offer': offer?.toJson(),
        'attachmentUrl': attachmentUrl,
        'createdAt': _iso(createdAt),
      };
}

/// `chef_bookings` with everything that hangs off it.
class MockBookingRow {
  MockBookingRow({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.memberEmail,
    required this.chefId,
    required this.chefUserId,
    required this.chefName,
    required this.chefEmail,
    required this.bookingType,
    required this.planDays,
    required this.startDate,
    required this.goal,
    required this.allergies,
    required this.mealPattern,
    required this.budgetPerDay,
    required this.needs,
    required this.shareHealthProfile,
    required this.status,
    required this.createdAt,
    this.memberHealth,
  }) : updatedAt = createdAt;

  final String id;
  final String memberId;
  final String memberName;
  final String memberEmail;

  /// `chef_profiles.id` and the chef's user id.
  final String chefId;
  final String chefUserId;
  final String chefName;
  final String chefEmail;
  BookingType bookingType;
  int planDays;
  DateTime startDate;
  final String goal;
  final List<String> allergies;
  final List<MealSlot> mealPattern;
  final int? budgetPerDay;
  final String needs;
  final bool shareHealthProfile;
  BookingStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  final Map<String, dynamic>? memberHealth;

  final offers = <MockOfferRow>[];
  MockContractRow? contract;
  MockEscrowRow? escrow;
  MockComplaintRow? complaint;
  final days = <MockPlanDayRow>[];
  final messages = <MockMessageRow>[];
  String? orderId;
  String? declineReason;
  String? cancelReason;

  MockOfferRow? get lastOffer => offers.lastOrNull;

  int get deliveredDays => days.where((d) => d.isSent).length;

  DateTime get endDate => contract?.endDate ?? planEndDate(startDate, planDays);

  MockPlanDayRow day(int dayIndex) =>
      days.where((d) => d.dayIndex == dayIndex).firstOrNull ??
      (throw mockError(404, 'Không có ngày $dayIndex trong kế hoạch.'));

  String nameOf(BookingParty party) =>
      party == BookingParty.chef ? chefName : memberName;
}

/// One entry per paid booking: what the chef wallet ledger is derived from
/// (same as the web `escrowLedger`).
typedef EscrowLedgerEntry = ({
  String chefId,
  String bookingId,
  String? orderId,
  String memberName,
  String planTitle,
  String? transactionRef,
  int amount,
  DateTime heldAt,
  EscrowStatus status,
  DateTime releaseAt,
  DateTime? releasedAt,
  int releasedAmount,
  int feeAmount,
  int refundedAmount,
  String? complaintId,
  DateTime? decidedAt,
});

/// In-memory chef bookings: offers, contracts, booking orders, escrow holds,
/// plan days, chat and complaints. Lives inside [MockCommerceDb] (one reset,
/// one clock) and seeds the same ids, people and amounts as the web console
/// (FE/Web src/lib/mock_bookings.ts).
///
/// Rules are evaluated lazily on every read and write ([settle]): an unpaid
/// booking past `paymentDueAt` expires; an Active one past its end date is
/// Ended; a Held escrow past `releaseAt` without an open complaint is
/// released to the chef (net 90 %); a Frozen one waits for an admin.
class MockBookingDb {
  MockBookingDb.attach(this.commerce);

  /// The store this DB lives in (orders, payments, chef profiles).
  final MockCommerceDb commerce;

  static MockBookingDb get instance => MockCommerceDb.instance.bookingDb;

  /// Mock clock, shared with [MockCommerceDb.clock].
  static DateTime Function() get clock => MockCommerceDb.clock;
  static set clock(DateTime Function() value) => MockCommerceDb.clock = value;

  // Fresh seeds: `MockCommerceDb.reset()` (bookings live inside it).

  final bookings = <MockBookingRow>[];
  int _seq = 0;

  DateTime get now => MockCommerceDb.clock();

  /// The VN calendar day of [now].
  DateTime get today => vnDateOf(now);

  String _newId(String prefix) => '${prefix}_${++_seq}';

  // ---- lookups ------------------------------------------------------------

  MockBookingRow? find(String id) =>
      bookings.where((b) => b.id == id).firstOrNull;

  MockBookingRow booking(String id) =>
      find(id) ??
      (throw mockError(404, 'Không tìm thấy yêu cầu đặt chuyên gia.'));

  // ---- chat ---------------------------------------------------------------

  MockMessageRow say(MockBookingRow row, BookingParty role, String body,
      {DateTime? at, MockOfferRow? offer, String? attachmentUrl}) {
    final message = MockMessageRow(
      id: 'msg_${row.id}_${row.messages.length + 1}',
      senderId: switch (role) {
        BookingParty.member => row.memberId,
        BookingParty.chef => row.chefUserId,
        BookingParty.system => null,
      },
      senderRole: role,
      body: body,
      offer: offer,
      attachmentUrl: attachmentUrl,
      createdAt: at ?? now,
    );
    row.messages.add(message);
    return message;
  }

  // ---- lazy rules ---------------------------------------------------------

  /// Applied on every read and write (the real BE: on read or in a job).
  void settle() {
    final now = this.now;
    for (final row in bookings) {
      final contract = row.contract;
      if (row.status == BookingStatus.awaitingPayment &&
          contract != null &&
          now.isAfter(contract.paymentDueAt)) {
        row
          ..status = BookingStatus.expired
          ..updatedAt = contract.paymentDueAt;
        final orderId = row.orderId;
        if (orderId != null) commerce.cancelUnpaid(commerce.order(orderId));
        say(
            row,
            BookingParty.system,
            'Quá hạn thanh toán — yêu cầu đã hết hiệu lực. '
            'Thành viên có thể gửi yêu cầu mới.',
            at: contract.paymentDueAt);
      }
      if (row.status == BookingStatus.active &&
          contract != null &&
          !now.isBefore(vnTime(addDays(contract.endDate, 1), 0, 0))) {
        row.status = BookingStatus.ended;
      }
      final escrow = row.escrow;
      if (escrow != null &&
          escrow.status == EscrowStatus.held &&
          !now.isBefore(escrow.releaseAt) &&
          row.complaint?.status != ComplaintStatus.open) {
        _autoRelease(row);
      }
    }
  }

  /// Release at releaseAt (no complaint): net 90 % to the chef wallet.
  void _autoRelease(MockBookingRow row) {
    final escrow = row.escrow!;
    escrow
      ..status = EscrowStatus.released
      ..releasedAt = escrow.releaseAt
      ..releasedAmount = escrow.amount
      ..feeAmount = platformFee(escrow.amount)
      ..resolvedBy = null
      ..resolutionNote = null;
    if (row.status == BookingStatus.active ||
        row.status == BookingStatus.ended) {
      row.status = BookingStatus.completed;
    }
    row.updatedAt = escrow.releaseAt;
    say(
        row,
        BookingParty.system,
        'Hết hạn khiếu nại — đã chuyển '
        '${formatVnd(escrow.amount - escrow.feeAmount)} cho chuyên gia '
        '(sau phí ${(kPlatformFeeRate * 100).round()}%).',
        at: escrow.releaseAt);
  }

  // ---- state changes ------------------------------------------------------

  static String scopeText(int planDays, BookingType type,
          List<MealSlot> pattern, List<String> allergies) =>
      'Thiết kế thực đơn chay $planDays ngày (${type.label.toLowerCase()}) '
      'theo hồ sơ và nhu cầu của thành viên: ${pattern.length} bữa mỗi ngày, '
      'có định lượng và cách làm từng món'
      '${allergies.isEmpty ? '' : ', tránh hoàn toàn: ${allergies.join(', ')}'}.';

  MockBookingRow create({
    required String memberId,
    required String memberName,
    required String memberEmail,
    required MockChefRow chef,
    required CreateBookingRequestDto request,
    Map<String, dynamic>? memberHealth,
  }) {
    final row = MockBookingRow(
      id: _newId('bk'),
      memberId: memberId,
      memberName: memberName,
      memberEmail: memberEmail,
      chefId: chef.id,
      chefUserId: chef.userId,
      chefName: chef.fullName,
      chefEmail: chef.email,
      bookingType: request.bookingType,
      planDays: request.planDays,
      startDate: dateOnly(request.startDate),
      goal: request.goal,
      allergies: [...request.allergies],
      mealPattern: MealPattern.normalize(request.mealPattern),
      budgetPerDay: request.budgetPerDay,
      needs: request.needs.trim(),
      shareHealthProfile: request.shareHealthProfile,
      status: BookingStatus.requested,
      createdAt: now,
      memberHealth: request.shareHealthProfile ? memberHealth : null,
    );
    say(
        row,
        BookingParty.system,
        '$memberName đã gửi yêu cầu thiết kế thực đơn ${row.planDays} ngày '
        '(${row.bookingType.label.toLowerCase()}), bắt đầu '
        '${formatDayMonth(row.startDate)}.');
    say(row, BookingParty.member, row.needs);
    bookings.add(row);
    return row;
  }

  MockOfferRow addOffer(
      MockBookingRow row, BookingParty by, OfferRequestDto request) {
    if (!row.status.canNegotiate) {
      throw mockError(
          409, 'Yêu cầu này không còn thoả thuận giá được.', 'invalid_status');
    }
    final at = now;
    for (final o in row.offers) {
      if (o.status == OfferStatus.open) {
        o
          ..status = OfferStatus.superseded
          ..respondedAt = at;
      }
    }
    final offer = MockOfferRow(
      id: 'of_${row.id}_${row.offers.length + 1}',
      proposedBy: by,
      price: request.price,
      planDays: request.planDays,
      bookingType: request.bookingType,
      startDate: dateOnly(request.startDate),
      note: request.note.trim(),
      createdAt: at,
    );
    row
      ..offers.add(offer)
      ..status = BookingStatus.negotiating
      ..updatedAt = at;
    say(
        row,
        by,
        offer.note.isEmpty
            ? 'Đề xuất giá ${formatVnd(offer.price)}'
            : offer.note,
        offer: offer);
    return offer;
  }

  /// Accept: contract, booking order, AwaitingPayment (payment due in 48 h,
  /// or 30 s with `#expire` in the needs). Reject: the offer is closed.
  void respond(MockBookingRow row, String offerId, BookingParty by,
      {required bool accept}) {
    final offer = row.lastOffer;
    if (offer == null || offer.id != offerId || !offer.isOpenOffer) {
      throw mockError(
          409,
          'Đề xuất này không còn hiệu lực. Xem đề xuất mới nhất.',
          'offer_closed');
    }
    if (offer.proposedBy == by) {
      throw mockError(
          409, 'Bên đưa ra đề xuất không tự đồng ý được.', 'own_offer');
    }
    final at = now;
    offer.respondedAt = at;
    if (!accept) {
      offer.status = OfferStatus.rejected;
      row.updatedAt = at;
      say(row, BookingParty.system,
          '${row.nameOf(by)} đã từ chối đề xuất ${formatVnd(offer.price)}.');
      return;
    }
    if (!offer.startDate.isAfter(today)) {
      throw mockError(
          409,
          'Ngày bắt đầu ${formatDayMonth(offer.startDate)} đã qua. Hãy đề xuất lại ngày bắt đầu.',
          'start_date_passed');
    }
    offer.status = OfferStatus.accepted;
    row
      ..planDays = offer.planDays
      ..bookingType = offer.bookingType
      ..startDate = offer.startDate;
    final fast = row.needs.toLowerCase().contains('#expire');
    final dueAt = at.add(
        fast ? BookingRules.fastPaymentWindow : BookingRules.paymentWindow);
    _contract(row, offer, at, dueAt);
    final order = MockOrderRow(
      id: commerce.newId('ord'),
      userId: row.memberId,
      buyerName: row.memberName,
      bookingId: row.id,
      chefId: row.chefId,
      chefName: row.chefName,
      amount: offer.price,
      createdAt: at,
    );
    commerce.orders.add(order);
    row
      ..orderId = order.id
      ..status = BookingStatus.awaitingPayment
      ..updatedAt = at;
    say(
        row,
        BookingParty.system,
        '${row.nameOf(by)} đã đồng ý đề xuất ${formatVnd(offer.price)}. '
        'Hồ sơ hợp đồng đã được tạo — thanh toán trước ${formatVnStamp(dueAt)}.');
  }

  MockContractRow _contract(
      MockBookingRow row, MockOfferRow offer, DateTime at, DateTime dueAt) {
    final contract = MockContractRow(
      id: 'ct_${row.id}',
      bookingId: row.id,
      offerId: offer.id,
      price: offer.price,
      planDays: offer.planDays,
      bookingType: offer.bookingType,
      startDate: offer.startDate,
      deliveryDueAt: deliveryDueAt(offer.bookingType, offer.startDate, at),
      scopeText: scopeText(
          offer.planDays, offer.bookingType, row.mealPattern, row.allergies),
      paymentDueAt: dueAt,
      createdAt: at,
    );
    row.contract = contract;
    row.days
      ..clear()
      ..addAll([
        for (var i = 1; i <= offer.planDays; i++)
          MockPlanDayRow(dayIndex: i, date: addDays(offer.startDate, i - 1)),
      ]);
    return contract;
  }

  /// The member's QR for the contract price: the open one, or a new one.
  MockOrderRow startPayment(MockBookingRow row) {
    settle();
    if (row.status != BookingStatus.awaitingPayment) {
      throw mockError(
          409,
          row.status == BookingStatus.expired
              ? 'Đã quá hạn thanh toán. Gửi yêu cầu mới cho chuyên gia nhé.'
              : 'Yêu cầu này không còn chờ thanh toán.',
          'not_awaiting_payment');
    }
    final order = commerce.order(row.orderId!);
    final current = commerce.latestPayment(order.id);
    if (current == null || current.status != PaymentStatus.pending) {
      // A QR never outlives the payment window.
      final left = row.contract!.paymentDueAt.difference(now);
      var ttl = row.needs.toLowerCase().contains('#expire')
          ? MockCommerceDb.fastExpiryTtl
          : MockCommerceDb.paymentTtl;
      if (left < ttl) ttl = left;
      commerce.openPayment(order, ttl: ttl);
    }
    return order;
  }

  /// PaymentOS confirmed: the money goes into escrow until the plan's end
  /// date 23:59 + 3 days.
  void onOrderPaid(MockOrderRow order, MockPaymentRow payment) {
    final row = find(order.bookingId);
    final contract = row?.contract;
    if (row == null || contract == null) return;
    final paidAt = payment.paidAt ?? now;
    if (row.status != BookingStatus.awaitingPayment) {
      // Paid after expiry or cancellation: straight back to the payer.
      commerce.refund(order);
      say(row, BookingParty.system,
          'Khoản thanh toán đến sau khi yêu cầu đã đóng nên được hoàn lại.');
      return;
    }
    _fund(row, payment, paidAt);
  }

  void _fund(MockBookingRow row, MockPaymentRow payment, DateTime paidAt) {
    final contract = row.contract!;
    contract.deliveryDueAt =
        deliveryDueAt(contract.bookingType, contract.startDate, paidAt);
    final releaseAt = contract.releaseAt;
    row
      ..escrow = MockEscrowRow(
        id: 'eh_${row.orderId!.replaceFirst('ord_', '')}',
        bookingId: row.id,
        paymentId: payment.id,
        amount: contract.price,
        heldAt: paidAt,
        releaseAt: releaseAt,
      )
      ..status = BookingStatus.active
      ..updatedAt = paidAt;
    say(
        row,
        BookingParty.system,
        'Đã thanh toán ${formatVnd(contract.price)} qua PaymentOS. VeganLife '
        'giữ tiền đến ${formatVnStamp(releaseAt)} '
        '(${BookingRules.holdDays} ngày sau khi kết thúc kế hoạch).',
        at: paidAt);
  }

  void cancel(MockBookingRow row, String reason) {
    _closeBeforePayment(row);
    row
      ..status = BookingStatus.cancelled
      ..cancelReason = reason.trim();
    say(row, BookingParty.system,
        '${row.memberName} đã huỷ yêu cầu: "${reason.trim()}"');
  }

  void decline(MockBookingRow row, String reason) {
    _closeBeforePayment(row);
    row
      ..status = BookingStatus.declined
      ..declineReason = reason.trim();
    say(row, BookingParty.system,
        '${row.chefName} đã từ chối yêu cầu: "${reason.trim()}"');
  }

  void _closeBeforePayment(MockBookingRow row) {
    settle();
    if (!row.status.isBeforePayment) {
      throw mockError(409, 'Chỉ huỷ hoặc từ chối được trước khi thanh toán.',
          'invalid_status');
    }
    for (final o in row.offers) {
      if (o.status == OfferStatus.open) {
        o
          ..status = OfferStatus.withdrawn
          ..respondedAt = now;
      }
    }
    final orderId = row.orderId;
    if (orderId != null) commerce.cancelUnpaid(commerce.order(orderId));
    row.updatedAt = now;
  }

  void _expectPlanEditable(MockBookingRow row) {
    settle();
    if (row.status != BookingStatus.active &&
        row.status != BookingStatus.ended) {
      throw mockError(
          409,
          'Chỉ soạn kế hoạch khi đã thanh toán và chưa có khiếu nại.',
          'invalid_status');
    }
  }

  MockPlanDayRow saveDay(
      MockBookingRow row, int dayIndex, PlanDayRequestDto request) {
    _expectPlanEditable(row);
    final day = row.day(dayIndex);
    if (day.isSent) {
      throw mockError(409, 'Ngày này đã gửi cho thành viên.', 'day_sent');
    }
    day
      ..meals = [
        for (final m in request.meals)
          if (m.recipe.name.trim().isNotEmpty) m,
      ]
      ..chefNote = (request.chefNote?.trim().isEmpty ?? true)
          ? null
          : request.chefNote!.trim()
      ..status = PlanDayStatus.draft;
    row.updatedAt = now;
    return day;
  }

  /// DailyFeedback: one day, in order.
  MockPlanDayRow sendDay(MockBookingRow row, int dayIndex) {
    _expectPlanEditable(row);
    if (row.bookingType != BookingType.dailyFeedback) {
      throw mockError(409,
          'Kế hoạch giao một lần: gửi toàn bộ khi đủ các ngày.', 'one_shot');
    }
    final day = row.day(dayIndex);
    if (day.isSent) {
      throw mockError(409, 'Ngày này đã gửi cho thành viên.', 'day_sent');
    }
    if (dayIndex > 1 && !row.day(dayIndex - 1).isSent) {
      throw mockError(
          409, 'Gửi ngày ${dayIndex - 1} trước đã.', 'previous_day_unsent');
    }
    if (!day.isComplete(row.mealPattern)) {
      throw mockError(
          409, 'Ngày $dayIndex chưa đủ món cho các bữa.', 'day_incomplete');
    }
    _send(row, day);
    say(row, BookingParty.system,
        '${row.chefName} đã gửi kế hoạch ngày $dayIndex (${formatDayMonth(day.date)}).');
    return day;
  }

  /// OneShot: every day at once.
  List<MockPlanDayRow> sendAll(MockBookingRow row) {
    _expectPlanEditable(row);
    if (row.bookingType != BookingType.oneShot) {
      throw mockError(409, 'Kế hoạch có phản hồi: gửi từng ngày.', 'daily');
    }
    if (row.days.every((d) => d.isSent)) {
      throw mockError(409, 'Kế hoạch đã gửi.', 'day_sent');
    }
    final missing =
        row.days.where((d) => !d.isComplete(row.mealPattern)).length;
    if (missing > 0) {
      throw mockError(409, 'Còn $missing ngày chưa đủ món.', 'day_incomplete');
    }
    for (final d in row.days) {
      if (!d.isSent) _send(row, d);
    }
    say(row, BookingParty.system,
        '${row.chefName} đã gửi toàn bộ kế hoạch ${row.planDays} ngày.');
    return row.days;
  }

  /// Sent days reach the member's Thực đơn › "Từ chuyên gia" (D15b).
  void _send(MockBookingRow row, MockPlanDayRow day) {
    day
      ..status = PlanDayStatus.sent
      ..sentAt = now;
    row.updatedAt = now;
    for (final meal in day.meals) {
      deliverChefPlanMeal(
        memberId: row.memberId,
        chefUserId: row.chefUserId,
        chefName: row.chefName,
        slot: meal.slot,
        date: day.date,
        name: meal.recipe.name,
        calories: meal.recipe.calories,
        proteinG: meal.recipe.proteinG,
        carbsG: meal.recipe.carbsG,
        fatG: meal.recipe.fatG,
        ingredients: meal.recipe.ingredients,
        instructions: meal.recipe.instructions,
        note: meal.note ?? day.chefNote,
      );
    }
  }

  MockPlanDayRow feedback(
      MockBookingRow row, int dayIndex, DayFeedbackDto request) {
    settle();
    if (row.bookingType != BookingType.dailyFeedback) {
      throw mockError(409,
          'Chỉ kế hoạch có phản hồi mỗi ngày mới gửi phản hồi.', 'one_shot');
    }
    if (row.status != BookingStatus.active &&
        row.status != BookingStatus.ended) {
      throw mockError(
          409, 'Kế hoạch không còn nhận phản hồi.', 'invalid_status');
    }
    final day = row.day(dayIndex);
    if (!day.isSent) {
      throw mockError(409, 'Chuyên gia chưa gửi ngày này.', 'day_not_sent');
    }
    day.feedback = DayFeedbackDto(
      rating: request.rating.clamp(1, 5),
      adherence: request.adherence,
      body: request.body.trim(),
      createdAt: now,
    );
    row.updatedAt = now;
    say(
        row,
        BookingParty.system,
        '${row.memberName} đã phản hồi ngày $dayIndex: ${request.rating}★'
        '${request.body.trim().isEmpty ? '' : ' · ${request.body.trim()}'}');
    return day;
  }

  MockComplaintRow fileComplaint(
      MockBookingRow row, ComplaintRequestDto request) {
    settle();
    final escrow = row.escrow;
    if (row.complaint != null) {
      throw mockError(
          409, 'Bạn đã gửi khiếu nại cho kế hoạch này.', 'complaint_exists');
    }
    if (escrow == null ||
        escrow.status != EscrowStatus.held ||
        !now.isBefore(escrow.releaseAt)) {
      throw mockError(
          409,
          'Đã hết hạn khiếu nại — tiền đã được chuyển cho chuyên gia.',
          'complaint_window_closed');
    }
    final price = row.contract!.price;
    final complaint = MockComplaintRow(
      id: 'cp_${row.id}',
      bookingId: row.id,
      reason: request.reason,
      description: request.description.trim(),
      requestedOutcome: request.requestedOutcome,
      requestedAmount: request.requestedOutcome == RequestedOutcome.fullRefund
          ? price
          : request.requestedAmount ?? 0,
      createdAt: now,
    );
    for (final e in request.evidence) {
      complaint.evidence.add(MockEvidenceRow(
        id: 'ev_${complaint.id}_${complaint.evidence.length + 1}',
        kind: e.kind,
        url: e.url.trim(),
        caption: (e.caption?.trim().isEmpty ?? true) ? null : e.caption!.trim(),
        submittedBy: BookingParty.member,
        createdAt: now,
      ));
    }
    row
      ..complaint = complaint
      ..status = BookingStatus.disputed
      ..updatedAt = now;
    escrow.status = EscrowStatus.frozen;
    say(
        row,
        BookingParty.system,
        '${row.memberName} đã gửi khiếu nại: "${request.reason.label}". '
        'Tiền được tạm giữ đến khi Ban quản trị quyết định.');
    return complaint;
  }

  MockComplaintRow respondToComplaint(
      MockBookingRow row, ComplaintResponseRequestDto request) {
    settle();
    final complaint = row.complaint;
    if (complaint == null || complaint.status != ComplaintStatus.open) {
      throw mockError(
          409, 'Không có khiếu nại đang chờ xử lý.', 'no_complaint');
    }
    complaint
      ..chefResponse = request.text.trim()
      ..chefRespondedAt = now;
    for (final e in request.links) {
      complaint.evidence.add(MockEvidenceRow(
        id: 'ev_${complaint.id}_${complaint.evidence.length + 1}',
        kind: EvidenceKind.link,
        url: e.url.trim(),
        caption: (e.caption?.trim().isEmpty ?? true) ? null : e.caption!.trim(),
        submittedBy: BookingParty.chef,
        createdAt: now,
      ));
    }
    row.updatedAt = now;
    say(row, BookingParty.chef, request.text.trim());
    return complaint;
  }

  /// What an admin does on web `/disputes` (the mobile app has no admin
  /// screen): ReleaseToChef → Released; RefundMember → Refunded to the
  /// original payment method; Split → [refundAmount] back, the rest to the
  /// chef minus the fee.
  @visibleForTesting
  void decideComplaint(
    String bookingId, {
    required ComplaintDecision decision,
    int? refundAmount,
    String note = 'Quyết định của Ban quản trị (mô phỏng).',
    String by = 'Quản trị viên',
    DateTime? at,
  }) =>
      _applyDecision(
          booking(bookingId), decision, refundAmount, note, by, at ?? now);

  void _applyDecision(MockBookingRow row, ComplaintDecision decision,
      int? refundAmount, String note, String by, DateTime at) {
    final complaint = row.complaint;
    final escrow = row.escrow;
    final contract = row.contract;
    if (complaint == null || escrow == null || contract == null) return;
    final out = decisionOutcome(contract.price, decision, refundAmount);
    complaint
      ..status = ComplaintStatus.resolved
      ..decision = decision
      ..refundAmount = out.refund
      ..adminNote = note
      ..decidedBy = by
      ..decidedAt = at;
    escrow
      ..status = switch (decision) {
        ComplaintDecision.releaseToChef => EscrowStatus.released,
        ComplaintDecision.refundMember => EscrowStatus.refunded,
        ComplaintDecision.split => EscrowStatus.partiallyRefunded,
      }
      ..releasedAt = out.chefGross > 0 ? at : null
      ..releasedAmount = out.chefGross
      ..feeAmount = out.fee
      ..refundedAmount = out.refund
      ..resolvedBy = by
      ..resolutionNote = note;
    row
      ..status = BookingStatus.resolved
      ..updatedAt = at;
    final orderId = row.orderId;
    if (out.refund > 0 && orderId != null) {
      commerce.refund(commerce.order(orderId), amount: out.refund);
    }
    final detail = switch (decision) {
      ComplaintDecision.releaseToChef =>
        'chuyên gia nhận ${formatVnd(out.chefNet)} sau phí',
      ComplaintDecision.refundMember =>
        'hoàn ${formatVnd(out.refund)} về phương thức thanh toán ban đầu',
      ComplaintDecision.split =>
        'hoàn ${formatVnd(out.refund)} cho thành viên, chuyên gia nhận ${formatVnd(out.chefNet)} sau phí',
    };
    say(row, BookingParty.system,
        'Ban quản trị đã quyết định: ${decision.label} — $detail. Ghi chú: "$note"',
        at: at);
  }

  // ---- wire JSON ----------------------------------------------------------

  Map<String, dynamic> bookingJson(MockBookingRow row) => {
        'id': row.id,
        'member': {
          'id': row.memberId,
          'fullName': row.memberName,
          'email': row.memberEmail,
        },
        'chef': {
          'id': row.chefUserId,
          'fullName': row.chefName,
          'email': row.chefEmail,
        },
        'bookingType': row.bookingType.apiValue,
        'planDays': row.planDays,
        'startDate': toApiDate(row.startDate),
        'goal': row.goal,
        'allergies': row.allergies,
        'mealPattern': MealPattern.toApi(row.mealPattern),
        'budgetPerDay': row.budgetPerDay,
        'needs': row.needs,
        'shareHealthProfile': row.shareHealthProfile,
        'status': row.status.apiValue,
        'deliveredDays': row.deliveredDays,
        'currentOffer': row.lastOffer?.toJson(),
        'contract': row.contract?.toJson(),
        'escrow': row.escrow?.toJson(),
        'complaint': row.complaint?.toJson(),
        'paymentOrderId': row.orderId,
        'declineReason': row.declineReason,
        'cancelReason': row.cancelReason,
        'memberHealth': row.shareHealthProfile ? row.memberHealth : null,
        'createdAt': _iso(row.createdAt),
        'updatedAt': _iso(row.updatedAt),
      };

  Map<String, dynamic> orderBookingJson(MockBookingRow row) => {
        'id': row.id,
        'chefId': row.chefUserId,
        'chefName': row.chefName,
        'bookingType': row.bookingType.apiValue,
        'planDays': row.planDays,
        'startDate': toApiDate(row.startDate),
        'endDate': toApiDate(row.endDate),
        'status': row.status.apiValue,
      };

  /// One entry per paid booking (the chef wallet's source).
  List<EscrowLedgerEntry> escrowLedger() {
    settle();
    return [
      for (final b in bookings)
        if (b.escrow case final escrow?)
          (
            chefId: b.chefId,
            bookingId: b.id,
            orderId: b.orderId,
            memberName: b.memberName,
            planTitle: planTitle(b.planDays, b.bookingType),
            transactionRef: b.orderId == null
                ? null
                : commerce.paidPayment(b.orderId!)?.transactionRef,
            amount: escrow.amount,
            heldAt: escrow.heldAt,
            status: escrow.status,
            releaseAt: escrow.releaseAt,
            releasedAt: escrow.releasedAt,
            releasedAmount: escrow.releasedAmount,
            feeAmount: escrow.feeAmount,
            refundedAmount: escrow.refundedAmount,
            complaintId: b.complaint?.id,
            decidedAt: b.complaint?.decidedAt,
          ),
    ];
  }

  /// `memberHealth` of a booking from the member's health profile.
  static Map<String, dynamic> memberHealthJson(HealthProfile p) => {
        'heightCm': p.heightCm,
        'weightKg': p.weightKg,
        'bmi': p.bmi,
        if (p.gender != null) 'gender': p.gender!.apiValue,
        if (p.age != null) 'age': p.age,
        'activityLevel': p.activityLevel.apiValue,
        if (p.dailyKcalTarget != null) 'dailyKcalTarget': p.dailyKcalTarget,
      };

  // ---- seeds --------------------------------------------------------------

  void seed() => _seedBookings(this);
}

extension on MockOfferRow {
  bool get isOpenOffer => status == OfferStatus.open;
}
