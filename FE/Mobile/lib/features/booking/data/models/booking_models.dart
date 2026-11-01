// lib/features/booking/data/models/booking_models.dart
//
// Chef meal-plan bookings (plan D15 / §2.4). Same shapes as the web admin
// (FE/Web src/types/bookings.ts); ids are INT on the BE, strings here.
// NOT in the 26-table SQL design — proposed tables: chef_bookings,
// booking_offers, booking_messages, booking_contracts, booking_plan_days,
// booking_plan_meals, booking_day_feedback, escrow_holds, booking_complaints,
// complaint_evidence; orders.booking_id; wallet_transactions.booking_id.
//
// BookingDto — GET /bookings/{id}, items of GET /bookings/me and
// GET /chefs/me/bookings
// { "id": "b_ma_tam_nego",
//   "member": { "id": "u_me", "fullName": "Minh Anh", "email": "minhanh.nguyen@gmail.com" },
//   "chef":   { "id": "u_chef_tam", "fullName": "Lê Quang Tâm", "email": "tam.chefchay@gmail.com" },
//   "bookingType": "DailyFeedback", "planDays": 10, "startDate": "2026-10-20",
//   "audience": "Self" | "Family",   // missing (older data) reads as "Self"
//   "familySize": null | 4,          // Family only
//   "goal": "lose_weight" | null,    // null for Family, or Self without sharing
//   "allergies": ["peanut"], "mealPattern": ["breakfast","lunch","dinner"],
//   "budgetPerDay": 80000, "needs": "…", "shareHealthProfile": true,
//   "status": "Negotiating", "deliveredDays": 0,
//   "completedAt": null | "…",       // completed; the hold runs from here
//   "autoCompleted": false,          // true: the system did it, not the chef
//   "currentOffer": OfferDto | null, "contract": ContractDto | null,
//   "escrow": EscrowHoldDto | null, "complaint": ComplaintDto | null,
//   "paymentOrderId": "ord_601" | null, "declineReason": null, "cancelReason": null,
//   "memberHealth": { "heightCm": 160, "weightKg": 55, "bmi": 21.5, "gender": "Female",
//                     "age": 29, "activityLevel": "light", "dailyKcalTarget": 1600 } | null,
//   "createdAt": "2026-10-16T03:00:00Z", "updatedAt": "…" }
//   memberHealth (mobile addition, computed by BE): sent only when shareHealthProfile
//   is true (never for Family), to the two parties. The web console ignores it.
//
// OfferDto     { "id": "of_b_ma_tam_nego_1", "proposedBy": "chef" | "member", "price": 1500000,
//                "planDays": 10, "bookingType": "DailyFeedback", "startDate": "2026-10-20",
//                "note": "…", "status": "Open", "createdAt": "…", "respondedAt": null }
// ContractDto  { "id": "ct_…", "bookingId", "offerId", "price": 1500000, "planDays": 10,
//                "bookingType": "DailyFeedback", "startDate": "2026-10-20", "endDate": "2026-10-29",
//                "deliveryDueAt": "…", "dailySendCutoff": "06:00", "feedbackCutoff": "21:00",
//                "scopeText": "…", "feeRate": 0.1, "holdDays": 7, "paymentDueAt": "…", "createdAt": "…" }
// EscrowHoldDto { "id": "eh_604", "bookingId": "b_tram_tam", "paymentId": "pay_…", "amount": 1050000,
//                 "status": "Held" | "Frozen" | "Released" | "Refunded" | "PartiallyRefunded",
//                 "heldAt": "…", "completedAt": null | "…",
//                 "releaseAt": null | "2026-10-19T16:59:00.000Z", "releasedAt": null,
//                 "releasedAmount": 0, "feeAmount": 0, "refundedAmount": 0, "refundedAt": null,
//                 "resolvedBy": null, "resolutionNote": null }
//   releaseAt is null until the contract is completed, then completedAt + 7 days (exact instant).
//   The chef confirms; or, with every day delivered by then and no open complaint, the
//   system completes it at endDate + 3 days 23:59 VN (completedAt = that moment,
//   autoCompleted = true). With days missing at that moment nothing happens: the money
//   stays held (a stuck hold) and the member is asked to complain.
//   An admin decides a stuck hold on web `/disputes` (POST /admin/escrow/holds/{id}/resolve):
//   resolvedBy and resolutionNote are set with no complaint, the booking is Completed
//   (release, split) or Cancelled (refund). A member's own cancellation leaves resolvedBy null.
//   Released: net 90 % to the chef wallet. Refunds go to the member's wallet.
// ComplaintDto { "id": "cp_tram_tam", "bookingId": "b_tram_tam", "reason": "health_risk",
//                "description": "…", "requestedOutcome": "PartialRefund", "requestedAmount": 500000,
//                "status": "Open" | "Resolved",
//                "evidence": [{ "id", "kind": "Link" | "Image", "url", "caption",
//                               "submittedBy": "member" | "chef", "createdAt" }],
//                "chefResponse": "…" | null, "chefRespondedAt": "…" | null,
//                "decision": null | "ReleaseToChef" | "RefundMember" | "Split",
//                "refundAmount": null | 300000, "adminNote": null, "decidedBy": null,
//                "decidedAt": null, "createdAt": "…" }
// PlanDayDto   { "dayIndex": 1, "date": "2026-10-20", "status": "Draft" | "Sent", "chefNote": "…",
//                "sentAt": "…" | null,
//                "meals": [{ "slot": "breakfast",
//                            "recipe": { "id": "rc_…", "name": "…", "calories": 420,
//                                        "proteinG": 18, "carbsG": 60, "fatG": 9,       // optional
//                                        "ingredients": ["Yến mạch", "Chuối"],          // optional
//                                        "instructions": "1. …" },                       // optional
//                            "note": "…" | null }],
//                "feedback": { "rating": 4, "adherence": "All" | "Partly" | "None", "body": "…",
//                              "createdAt": "…" } | null }
// MessageDto   { "id", "senderId": "u_chef_tam" | null, "senderRole": "member" | "chef" | "system",
//                "kind": "Text" | "Offer" | "System" | "Attachment", "body", "offerId": null,
//                "offer": OfferDto | null, "attachmentUrl": null, "createdAt" }
//
// Requests:
// POST /bookings { chefId, bookingType, planDays, startDate, audience, familySize?, goal?,
//                  allergies, mealPattern, budgetPerDay?, needs, shareHealthProfile }
//      → BookingDto (Requested). Self: needs ≥ 20 characters, goal only when sharing.
//      Family: familySize 2–20, needs optional, no goal, shareHealthProfile false.
//      409 self_booking, 409 not_accepting, 400 validation, 401 guest
// POST /bookings/{id}/messages { body, attachmentUrl? } → MessageDto ; GET ?after= → [MessageDto]
// POST /bookings/{id}/offers { price, planDays, bookingType, startDate, note } → BookingDto
// POST /bookings/{id}/offers/{offerId}/accept|reject → BookingDto
//      accept: contract created, AwaitingPayment,
//      paymentDueAt = min(now + 48 h, startDate 00:00 VN)
// POST /bookings/{id}/cancel { reason }: before payment, or after it while no day was
//      delivered (409 plan_started): the whole price goes to the member's wallet.
// POST /chefs/me/bookings/{id}/decline { reason }: before payment ("Không đồng ý").
// POST /chefs/me/bookings/{id}/complete → BookingDto (Ended, completedAt, escrow.releaseAt)
//      every day delivered and today ≥ endDate, else 409 plan_not_delivered;
//      409 not_active, 409 has_open_complaint
// POST /bookings/{id}/payments → OrderDto (orders.booking_id, PaymentOS QR)
// GET  /bookings/{id}/plan → [PlanDayDto]
// PUT  /bookings/{id}/plan/days/{dayIndex}/feedback { rating, adherence, body } → PlanDayDto
// PUT  /chefs/me/bookings/{id}/plan/days/{dayIndex} { chefNote, meals: [{ slot, recipeId?,
//      recipe?: { name, calories?, proteinG?, carbsG?, fatG?, ingredients, instructions? }, note? }] }
// POST /chefs/me/bookings/{id}/plan/days/{dayIndex}/send ; POST /chefs/me/bookings/{id}/plan/send
// GET/POST /bookings/{id}/complaint { reason, description, requestedOutcome, requestedAmount?,
//      evidence: [{ kind, url, caption? }] } → BookingDto (Disputed, escrow Frozen)
// POST /chefs/me/bookings/{id}/complaint/response { text, links: [{ kind: "Link", url, caption? }] }
import '../../../../core/utils/energy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../meal_planner/domain/entities/health_profile.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';

int? _intOrNull(Object? value) => value == null ? null : readInt(value);

/// A name sent as a plain string or as `{ fullName }` (the web accepts both).
String? _personName(Object? value) => switch (value) {
      final String name => name,
      {'fullName': final String name} => name,
      _ => null,
    };

/// One text, or the list of steps a BE `RecipeResponse` sends: one per line.
String? _instructionsText(Object? value) => switch (value) {
      final String text => text,
      final List<Object?> steps => steps.whereType<String>().join('\n'),
      _ => null,
    };

double? _doubleOrNull(Object? value) =>
    value == null ? null : readDouble(value);

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) f) =>
    value is List<Object?>
        ? value.whereType<Map<String, dynamic>>().map(f).toList()
        : <T>[];

class BookingPersonDto {
  const BookingPersonDto(
      {required this.id, required this.fullName, this.email = ''});

  factory BookingPersonDto.fromJson(Map<String, dynamic> json) =>
      BookingPersonDto(
        id: json['id']?.toString() ?? '',
        fullName: json['fullName'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );

  /// The user id (chef bookings: the chef's user id).
  final String id;
  final String fullName;
  final String email;

  Map<String, dynamic> toJson() =>
      {'id': id, 'fullName': fullName, 'email': email};
}

class OfferDto {
  const OfferDto({
    required this.id,
    required this.proposedBy,
    required this.price,
    required this.planDays,
    required this.bookingType,
    required this.startDate,
    required this.status,
    required this.createdAt,
    this.note = '',
    this.respondedAt,
  });

  factory OfferDto.fromJson(Map<String, dynamic> json) => OfferDto(
        id: json['id']?.toString() ?? '',
        proposedBy: BookingParty.fromApi(json['proposedBy']),
        price: readInt(json['price']),
        planDays: readInt(json['planDays']),
        bookingType: BookingType.fromApi(json['bookingType']),
        startDate: readDate(json['startDate']),
        note: json['note'] as String? ?? '',
        status: OfferStatus.fromApi(json['status']),
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        respondedAt: readDateTime(json['respondedAt']),
      );

  static OfferDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? OfferDto.fromJson(value) : null;

  final String id;
  final BookingParty proposedBy;
  final int price;
  final int planDays;
  final BookingType bookingType;
  final DateTime startDate;
  final String note;
  final OfferStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  bool get isOpen => status == OfferStatus.open;

  /// "Đề xuất giá · 1.500.000đ · 10 ngày · Có phản hồi mỗi ngày · bắt đầu 20/10".
  String get summary =>
      '${formatVnd(price)} · $planDays ngày · ${bookingType.label} · bắt đầu ${formatDayMonth(startDate)}';
}

/// `booking_contracts`: the accepted offer, frozen.
class ContractDto {
  const ContractDto({
    required this.id,
    required this.bookingId,
    required this.offerId,
    required this.price,
    required this.planDays,
    required this.bookingType,
    required this.startDate,
    required this.endDate,
    required this.deliveryDueAt,
    required this.paymentDueAt,
    required this.createdAt,
    this.dailySendCutoff = BookingRules.dailySendCutoff,
    this.feedbackCutoff = BookingRules.feedbackCutoff,
    this.scopeText = '',
    this.feeRate = BookingRules.feeRate,
    this.holdDays = BookingRules.holdDays,
  });

  factory ContractDto.fromJson(Map<String, dynamic> json) => ContractDto(
        id: json['id']?.toString() ?? '',
        bookingId: json['bookingId']?.toString() ?? '',
        offerId: json['offerId']?.toString() ?? '',
        price: readInt(json['price']),
        planDays: readInt(json['planDays']),
        bookingType: BookingType.fromApi(json['bookingType']),
        startDate: readDate(json['startDate']),
        endDate: readDate(json['endDate']),
        deliveryDueAt: readDateTime(json['deliveryDueAt']) ?? DateTime.now(),
        dailySendCutoff:
            json['dailySendCutoff'] as String? ?? BookingRules.dailySendCutoff,
        feedbackCutoff:
            json['feedbackCutoff'] as String? ?? BookingRules.feedbackCutoff,
        scopeText: json['scopeText'] as String? ?? '',
        feeRate: json['feeRate'] == null
            ? BookingRules.feeRate
            : readDouble(json['feeRate']),
        holdDays: json['holdDays'] == null
            ? BookingRules.holdDays
            : readInt(json['holdDays']),
        paymentDueAt: readDateTime(json['paymentDueAt']) ?? DateTime.now(),
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      );

  static ContractDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? ContractDto.fromJson(value) : null;

  final String id;
  final String bookingId;
  final String offerId;
  final int price;
  final int planDays;
  final BookingType bookingType;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime deliveryDueAt;
  final String dailySendCutoff;
  final String feedbackCutoff;
  final String scopeText;
  final double feeRate;
  final int holdDays;
  final DateTime paymentDueAt;
  final DateTime createdAt;

  int get fee => (price * feeRate).round();
}

class EscrowHoldDto {
  const EscrowHoldDto({
    required this.id,
    required this.amount,
    required this.status,
    required this.heldAt,
    this.completedAt,
    this.releaseAt,
    this.bookingId = '',
    this.paymentId = '',
    this.releasedAt,
    this.releasedAmount = 0,
    this.feeAmount = 0,
    this.refundedAmount = 0,
    this.refundedAt,
    this.resolvedBy,
    this.resolutionNote,
  });

  factory EscrowHoldDto.fromJson(Map<String, dynamic> json) => EscrowHoldDto(
        id: json['id']?.toString() ?? '',
        bookingId: json['bookingId']?.toString() ?? '',
        paymentId: json['paymentId']?.toString() ?? '',
        amount: readInt(json['amount']),
        status: EscrowStatus.fromApi(json['status']),
        heldAt: readDateTime(json['heldAt']) ?? DateTime.now(),
        completedAt: readDateTime(json['completedAt']),
        releaseAt: readDateTime(json['releaseAt']),
        releasedAt: readDateTime(json['releasedAt']),
        releasedAmount: readInt(json['releasedAmount']),
        feeAmount: readInt(json['feeAmount']),
        refundedAmount: readInt(json['refundedAmount']),
        refundedAt: readDateTime(json['refundedAt']),
        resolvedBy: _personName(json['resolvedBy']),
        resolutionNote: json['resolutionNote'] as String?,
      );

  static EscrowHoldDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? EscrowHoldDto.fromJson(value) : null;

  final String id;
  final String bookingId;
  final String paymentId;

  /// = contract price (gross).
  final int amount;
  final EscrowStatus status;
  final DateTime heldAt;

  /// When the chef confirmed; `null` before that.
  final DateTime? completedAt;

  /// `null` until the chef confirms: [completedAt] + 7 days.
  final DateTime? releaseAt;
  final DateTime? releasedAt;

  /// Gross that went to the chef (before the fee).
  final int releasedAmount;
  final int feeAmount;

  /// Sent back to the member's wallet.
  final int refundedAmount;
  final DateTime? refundedAt;
  final String? resolvedBy;
  final String? resolutionNote;
}

class EvidenceDto {
  const EvidenceDto({
    required this.kind,
    required this.url,
    this.id = '',
    this.caption,
    this.submittedBy = BookingParty.member,
    this.createdAt,
  });

  factory EvidenceDto.fromJson(Map<String, dynamic> json) => EvidenceDto(
        id: json['id']?.toString() ?? '',
        kind: EvidenceKind.fromApi(json['kind']),
        url: json['url'] as String? ?? '',
        caption: json['caption'] as String?,
        submittedBy: BookingParty.fromApi(json['submittedBy']),
        createdAt: readDateTime(json['createdAt']),
      );

  final String id;
  final EvidenceKind kind;
  final String url;
  final String? caption;
  final BookingParty submittedBy;
  final DateTime? createdAt;

  /// Request body item (`complaint_evidence`).
  Map<String, dynamic> toRequestJson() => {
        'kind': kind.apiValue,
        'url': url.trim(),
        if (caption != null && caption!.trim().isNotEmpty)
          'caption': caption!.trim(),
      };
}

class ComplaintDto {
  const ComplaintDto({
    required this.id,
    required this.reason,
    required this.description,
    required this.requestedOutcome,
    required this.requestedAmount,
    required this.status,
    required this.createdAt,
    this.bookingId = '',
    this.evidence = const [],
    this.chefResponse,
    this.chefRespondedAt,
    this.decision,
    this.refundAmount,
    this.adminNote,
    this.decidedBy,
    this.decidedAt,
  });

  factory ComplaintDto.fromJson(Map<String, dynamic> json) => ComplaintDto(
        id: json['id']?.toString() ?? '',
        bookingId: json['bookingId']?.toString() ?? '',
        reason: ComplaintReason.fromApi(json['reason']),
        description: json['description'] as String? ?? '',
        requestedOutcome: RequestedOutcome.fromApi(json['requestedOutcome']),
        requestedAmount: readInt(json['requestedAmount']),
        status: ComplaintStatus.fromApi(json['status']),
        evidence: _list(json['evidence'], EvidenceDto.fromJson),
        chefResponse: json['chefResponse'] as String?,
        chefRespondedAt: readDateTime(json['chefRespondedAt']),
        decision: ComplaintDecision.fromApiOrNull(json['decision']),
        refundAmount: _intOrNull(json['refundAmount']),
        adminNote: json['adminNote'] as String?,
        decidedBy: _personName(json['decidedBy']),
        decidedAt: readDateTime(json['decidedAt']),
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      );

  static ComplaintDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? ComplaintDto.fromJson(value) : null;

  final String id;
  final String bookingId;
  final ComplaintReason reason;
  final String description;
  final RequestedOutcome requestedOutcome;

  /// = contract price for a full refund.
  final int requestedAmount;
  final ComplaintStatus status;
  final List<EvidenceDto> evidence;
  final String? chefResponse;
  final DateTime? chefRespondedAt;
  final ComplaintDecision? decision;

  /// Back to the member (0 for ReleaseToChef).
  final int? refundAmount;
  final String? adminNote;
  final String? decidedBy;
  final DateTime? decidedAt;
  final DateTime createdAt;

  bool get isOpen => status == ComplaintStatus.open;
}

/// The dish of a plan meal (a `recipes` row created by the chef).
class PlanRecipeDto {
  const PlanRecipeDto({
    required this.name,
    this.id = '',
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.ingredients = const [],
    this.instructions,
  });

  factory PlanRecipeDto.fromJson(Map<String, dynamic> json) {
    final kcal = json['calories'] ?? json['caloriesCache'];
    return PlanRecipeDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      calories: kcal == null || readInt(kcal) <= 0 ? null : readInt(kcal),
      proteinG: _doubleOrNull(json['proteinG']),
      carbsG: _doubleOrNull(json['carbsG']),
      fatG: _doubleOrNull(json['fatG']),
      ingredients: json['ingredients'] is List<Object?>
          ? [
              for (final i in json['ingredients'] as List<Object?>)
                if (i is String)
                  i
                else if (i is Map<String, dynamic> && i['name'] is String)
                  i['name'] as String,
            ]
          : const [],
      instructions: _instructionsText(json['instructions']),
    );
  }

  final String id;
  final String name;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final List<String> ingredients;
  final String? instructions;

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name.trim(),
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'proteinG': proteinG,
        if (carbsG != null) 'carbsG': carbsG,
        if (fatG != null) 'fatG': fatG,
        if (ingredients.isNotEmpty) 'ingredients': ingredients,
        if (instructions != null && instructions!.trim().isNotEmpty)
          'instructions': instructions!.trim(),
      };
}

class PlanMealDto {
  const PlanMealDto({required this.slot, required this.recipe, this.note});

  factory PlanMealDto.fromJson(Map<String, dynamic> json) => PlanMealDto(
        slot: MealSlot.fromApi(json['slot']?.toString() ?? '') ??
            MealSlot.breakfast,
        recipe: PlanRecipeDto.fromJson(readMap(json['recipe'])),
        note: json['note'] as String?,
      );

  final MealSlot slot;
  final PlanRecipeDto recipe;
  final String? note;

  Map<String, dynamic> toJson() => {
        'slot': slot.apiValue,
        'recipe': recipe.toJson(),
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };
}

class DayFeedbackDto {
  const DayFeedbackDto({
    required this.rating,
    required this.adherence,
    this.body = '',
    this.createdAt,
  });

  factory DayFeedbackDto.fromJson(Map<String, dynamic> json) => DayFeedbackDto(
        rating: readInt(json['rating']).clamp(1, 5),
        adherence: Adherence.fromApi(json['adherence']),
        body: json['body'] as String? ?? '',
        createdAt: readDateTime(json['createdAt']),
      );

  static DayFeedbackDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? DayFeedbackDto.fromJson(value) : null;

  final int rating;
  final Adherence adherence;
  final String body;
  final DateTime? createdAt;

  /// "★★★★ · Làm theo một phần · 'Bữa tối hơi nhiều dầu'".
  String get summary => [
        '★' * rating,
        adherence.longLabel,
        if (body.trim().isNotEmpty) '"${body.trim()}"',
      ].join(' · ');

  Map<String, dynamic> toRequestJson() =>
      {'rating': rating, 'adherence': adherence.apiValue, 'body': body.trim()};
}

class PlanDayDto {
  const PlanDayDto({
    required this.dayIndex,
    required this.date,
    this.status,
    this.chefNote,
    this.sentAt,
    this.meals = const [],
    this.feedback,
  });

  factory PlanDayDto.fromJson(Map<String, dynamic> json) => PlanDayDto(
        dayIndex: readInt(json['dayIndex']),
        date: readDate(json['date']),
        status: json['status'] == null
            ? null
            : PlanDayStatus.fromApi(json['status']),
        chefNote: json['chefNote'] as String?,
        sentAt: readDateTime(json['sentAt']),
        meals: _list(json['meals'], PlanMealDto.fromJson),
        feedback: DayFeedbackDto.fromJsonValue(json['feedback']),
      );

  final int dayIndex;
  final DateTime date;

  /// `null`: the chef has not started this day ("Chưa soạn").
  final PlanDayStatus? status;
  final String? chefNote;
  final DateTime? sentAt;
  final List<PlanMealDto> meals;
  final DayFeedbackDto? feedback;

  bool get isSent => status == PlanDayStatus.sent;

  PlanMealDto? mealFor(MealSlot slot) =>
      meals.where((m) => m.slot == slot).firstOrNull;

  /// Every slot of [pattern] has a dish.
  bool isComplete(Iterable<MealSlot> pattern) =>
      pattern.every((s) => mealFor(s) != null);

  /// "Ngày 1 · Thứ Hai 20/10".
  String get title =>
      'Ngày $dayIndex · ${weekdayLong(date)} ${formatDayMonth(date)}';

  int get calories => meals.fold(0, (sum, m) => sum + (m.recipe.calories ?? 0));
}

class MessageDto {
  const MessageDto({
    required this.id,
    required this.senderRole,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.offerId,
    this.offer,
    this.attachmentUrl,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) => MessageDto(
        id: json['id']?.toString() ?? '',
        senderId: json['senderId']?.toString(),
        senderRole: BookingParty.fromApi(json['senderRole']),
        kind: MessageKind.fromApi(json['kind']),
        body: json['body'] as String? ?? '',
        offerId: json['offerId']?.toString(),
        offer: OfferDto.fromJsonValue(json['offer']),
        attachmentUrl: json['attachmentUrl'] as String?,
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      );

  final String id;
  final String? senderId;
  final BookingParty senderRole;
  final MessageKind kind;
  final String body;
  final String? offerId;

  /// Joined offer of an Offer message (computed by BE).
  final OfferDto? offer;
  final String? attachmentUrl;
  final DateTime createdAt;
}

/// `memberHealth` from a health profile: exactly what the chef gets when the
/// member shares it (the booking form lists the same fields).
Map<String, dynamic> memberHealthFromProfile(HealthProfile p) => {
      'heightCm': p.heightCm,
      'weightKg': p.weightKg,
      'bmi': p.bmi,
      if (p.gender != null) 'gender': p.gender!.apiValue,
      if (p.age != null) 'age': p.age,
      if (p.dailyKcalTarget != null) 'dailyKcalTarget': p.dailyKcalTarget,
    };

/// The member's health profile as the chef sees it when it is shared.
class MemberHealthDto {
  const MemberHealthDto({
    this.heightCm,
    this.weightKg,
    this.bmi,
    this.gender,
    this.age,
    this.activityLevel,
    this.dailyKcalTarget,
  });

  factory MemberHealthDto.fromJson(Map<String, dynamic> json) =>
      MemberHealthDto(
        heightCm: _doubleOrNull(json['heightCm']),
        weightKg: _doubleOrNull(json['weightKg']),
        bmi: _doubleOrNull(json['bmi']),
        gender: json['gender'] as String?,
        age: _intOrNull(json['age']),
        activityLevel: json['activityLevel'] as String?,
        dailyKcalTarget: _intOrNull(json['dailyKcalTarget']),
      );

  static MemberHealthDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? MemberHealthDto.fromJson(value) : null;

  final double? heightCm;
  final double? weightKg;
  final double? bmi;

  /// `Male` | `Female` | `Other`.
  final String? gender;
  final int? age;
  final String? activityLevel;
  final int? dailyKcalTarget;

  String? get _genderLabel => gender == null
      ? null
      : switch (gender) {
          'Male' => 'Nam',
          'Female' => 'Nữ',
          _ => 'Khác',
        };

  // Same rounding as the member's "Hồ sơ sức khoẻ" (2.060, not 2.063).
  String? get _kcal => dailyKcalTarget == null
      ? null
      : '≈ ${Energy.formatKcal(dailyKcalTarget!)} kcal/ngày';

  /// "160 cm · 55 kg · BMI 21,5 · Nữ · 29 tuổi · ≈ 1.600 kcal/ngày".
  String get summary => [
        if (heightCm != null) '${formatDecimal(heightCm!, digits: 0)} cm',
        if (weightKg != null) '${formatDecimal(weightKg!, digits: 0)} kg',
        if (bmi != null) 'BMI ${formatDecimal(bmi!)}',
        if (_genderLabel != null) _genderLabel!,
        if (age != null) '$age tuổi',
        if (_kcal != null) _kcal!,
      ].join(' · ');

  /// The same fields as label + value rows (the booking form's share card).
  List<(String, String)> get rows => [
        if (heightCm != null)
          ('Chiều cao', '${formatDecimal(heightCm!, digits: 0)} cm'),
        if (weightKg != null)
          ('Cân nặng', '${formatDecimal(weightKg!, digits: 0)} kg'),
        if (bmi != null) ('BMI', formatDecimal(bmi!)),
        if (_genderLabel != null) ('Giới tính', _genderLabel!),
        if (age != null) ('Tuổi', '$age tuổi'),
        if (_kcal != null) ('Nhu cầu năng lượng', _kcal!),
      ];
}

class BookingDto {
  const BookingDto({
    required this.id,
    required this.member,
    required this.chef,
    required this.bookingType,
    required this.planDays,
    required this.startDate,
    required this.status,
    required this.createdAt,
    this.audience = BookingAudience.self,
    this.familySize,
    this.goal,
    this.allergies = const [],
    this.mealPattern = MealPattern.standard,
    this.budgetPerDay,
    this.needs = '',
    this.shareHealthProfile = true,
    this.deliveredDays = 0,
    this.currentOffer,
    this.contract,
    this.escrow,
    this.complaint,
    this.paymentOrderId,
    this.declineReason,
    this.cancelReason,
    this.memberHealth,
    this.completedAt,
    this.autoCompleted = false,
    this.updatedAt,
  });

  factory BookingDto.fromJson(Map<String, dynamic> json) => BookingDto(
        id: json['id']?.toString() ?? '',
        member: BookingPersonDto.fromJson(readMap(json['member'])),
        chef: BookingPersonDto.fromJson(readMap(json['chef'])),
        bookingType: BookingType.fromApi(json['bookingType']),
        planDays: readInt(json['planDays']),
        startDate: readDate(json['startDate']),
        audience: BookingAudience.fromApi(json['audience']),
        familySize: _intOrNull(json['familySize']),
        goal: json['goal'] as String?,
        allergies: readStringList(json['allergies']),
        mealPattern: MealPattern.fromApi(json['mealPattern']),
        budgetPerDay:
            json['budgetPerDay'] == null ? null : readInt(json['budgetPerDay']),
        needs: json['needs'] as String? ?? '',
        shareHealthProfile: json['shareHealthProfile'] as bool? ?? true,
        status: BookingStatus.fromApi(json['status']),
        deliveredDays: readInt(json['deliveredDays']),
        currentOffer: OfferDto.fromJsonValue(json['currentOffer']),
        contract: ContractDto.fromJsonValue(json['contract']),
        escrow: EscrowHoldDto.fromJsonValue(json['escrow']),
        complaint: ComplaintDto.fromJsonValue(json['complaint']),
        paymentOrderId: json['paymentOrderId']?.toString(),
        declineReason: json['declineReason'] as String?,
        cancelReason: json['cancelReason'] as String?,
        memberHealth: MemberHealthDto.fromJsonValue(json['memberHealth']),
        completedAt: readDateTime(json['completedAt']),
        autoCompleted: json['autoCompleted'] == true,
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        updatedAt: readDateTime(json['updatedAt']),
      );

  final String id;
  final BookingPersonDto member;
  final BookingPersonDto chef;
  final BookingType bookingType;
  final int planDays;
  final DateTime startDate;
  final BookingAudience audience;

  /// "Cho gia đình": number of people.
  final int? familySize;

  /// `null` for a family, or when the member did not share their profile.
  final String? goal;

  /// Allergy keys (`peanut`) or free text ("lá lốt"), see `allergenLabel`.
  final List<String> allergies;
  final List<MealSlot> mealPattern;
  final int? budgetPerDay;
  final String needs;
  final bool shareHealthProfile;
  final BookingStatus status;

  /// Plan days with status Sent.
  final int deliveredDays;
  final OfferDto? currentOffer;
  final ContractDto? contract;
  final EscrowHoldDto? escrow;
  final ComplaintDto? complaint;
  final String? paymentOrderId;
  final String? declineReason;
  final String? cancelReason;
  final MemberHealthDto? memberHealth;

  /// The contract is completed: the hold runs from here.
  final DateTime? completedAt;

  /// The system completed it because the chef didn't confirm in time.
  final bool autoCompleted;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isFamily => audience == BookingAudience.family;

  /// "Gia đình · 4 người" / "Cho tôi".
  String get audienceLabel => !isFamily
      ? audience.label
      : familySize == null
          ? 'Gia đình'
          : 'Gia đình · $familySize người';

  bool get fullyDelivered => deliveredDays >= planDays;

  /// Chef: every day is delivered, the plan has reached its last day and the
  /// contract isn't completed yet.
  bool canConfirmCompletion(DateTime now) =>
      status == BookingStatus.active &&
      completedAt == null &&
      complaint == null &&
      escrow?.status == EscrowStatus.held &&
      fullyDelivered &&
      planReachedEnd(endDate, now);

  /// Past [autoCompleteAt] with days still missing: it doesn't complete by
  /// itself, the money stays held and the member is asked to complain.
  bool overdueUndelivered(DateTime now) =>
      status == BookingStatus.active &&
      completedAt == null &&
      complaint == null &&
      escrow?.status == EscrowStatus.held &&
      !fullyDelivered &&
      !now.isBefore(autoCompleteAt(endDate));

  /// Every day is in, but the last ones went out after [autoCompleteAt] (one sent
  /// in time would have completed by itself): waits on the chef's confirmation, a
  /// complaint, or an admin.
  bool deliveredAfterAutoComplete(DateTime now) =>
      status == BookingStatus.active &&
      completedAt == null &&
      complaint == null &&
      escrow?.status == EscrowStatus.held &&
      fullyDelivered &&
      !now.isBefore(autoCompleteAt(endDate));

  /// An admin decided the hold with no complaint: past [autoCompleteAt] it could
  /// not move on its own. A member's own cancellation leaves `resolvedBy` null.
  bool get isAdminResolved =>
      complaint == null && (escrow?.resolvedBy?.isNotEmpty ?? false);

  /// Member: paid, nothing delivered yet, so the whole price can come back to
  /// the wallet.
  bool get canCancelPaid =>
      status == BookingStatus.active &&
      complaint == null &&
      escrow?.status == EscrowStatus.held &&
      deliveredDays == 0;

  /// Contract price once agreed, otherwise the current offer's.
  int? get price => contract?.price ?? currentOffer?.price;

  DateTime get endDate => contract?.endDate ?? planEndDate(startDate, planDays);

  /// The latest offer, when it still waits for an answer.
  OfferDto? get openOffer =>
      currentOffer != null && currentOffer!.isOpen ? currentOffer : null;

  /// Which side [userId] is on; `null` when neither.
  BookingParty? partyOf(String? userId) {
    if (userId == null) return null;
    if (chef.id == userId) return BookingParty.chef;
    if (member.id == userId) return BookingParty.member;
    return null;
  }

  /// Member can file a complaint: paid, escrow still Held, before releaseAt
  /// (there is none until the contract is completed), no complaint yet.
  bool canComplain(DateTime now) {
    final releaseAt = escrow?.releaseAt;
    return complaint == null &&
        escrow?.status == EscrowStatus.held &&
        (releaseAt == null || now.isBefore(releaseAt)) &&
        (status == BookingStatus.active || status == BookingStatus.ended);
  }
}

/// POST /bookings.
class CreateBookingRequestDto {
  const CreateBookingRequestDto({
    required this.chefId,
    required this.bookingType,
    required this.planDays,
    required this.startDate,
    required this.goal,
    required this.allergies,
    required this.mealPattern,
    required this.needs,
    this.audience = BookingAudience.self,
    this.familySize,
    this.budgetPerDay,
    this.shareHealthProfile = true,
    this.healthSnapshot,
  });

  final String chefId;
  final BookingType bookingType;
  final int planDays;
  final DateTime startDate;
  final BookingAudience audience;
  final int? familySize;

  /// The form's goal; only sent when [sendsPersonalProfile] (see [sentGoal]).
  final String? goal;
  final List<String> allergies;
  final List<MealSlot> mealPattern;
  final int? budgetPerDay;
  final String needs;
  final bool shareHealthProfile;

  /// What the share card showed, for the mock server only (never on the wire:
  /// the real BE reads the member's profile itself). In a hybrid build the
  /// health profile lives on the BE while the bookings are mock.
  final Map<String, dynamic>? healthSnapshot;

  bool get isFamily => audience == BookingAudience.family;

  /// A family request sends no personal metrics, whatever the form holds.
  bool get sendsPersonalProfile => !isFamily && shareHealthProfile;

  String? get sentGoal => sendsPersonalProfile ? goal : null;

  Map<String, dynamic> toJson() => {
        'chefId': apiId(chefId),
        'bookingType': bookingType.apiValue,
        'planDays': planDays,
        'startDate': toApiDate(startDate),
        'audience': audience.apiValue,
        if (isFamily) 'familySize': familySize,
        if (sentGoal != null) 'goal': sentGoal,
        'allergies': allergies,
        'mealPattern': MealPattern.toApi(mealPattern),
        'budgetPerDay': budgetPerDay,
        'needs': needs.trim(),
        'shareHealthProfile': sendsPersonalProfile,
      };
}

/// POST /bookings/{id}/offers.
class OfferRequestDto {
  const OfferRequestDto({
    required this.price,
    required this.planDays,
    required this.bookingType,
    required this.startDate,
    this.note = '',
  });

  final int price;
  final int planDays;
  final BookingType bookingType;
  final DateTime startDate;
  final String note;

  Map<String, dynamic> toJson() => {
        'price': price,
        'planDays': planDays,
        'bookingType': bookingType.apiValue,
        'startDate': toApiDate(startDate),
        'note': note.trim(),
      };
}

/// POST /bookings/{id}/messages.
class SendMessageRequestDto {
  const SendMessageRequestDto({required this.body, this.attachmentUrl});

  final String body;
  final String? attachmentUrl;

  Map<String, dynamic> toJson() => {
        'body': body.trim(),
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      };
}

/// POST /bookings/{id}/complaint.
class ComplaintRequestDto {
  const ComplaintRequestDto({
    required this.reason,
    required this.description,
    required this.requestedOutcome,
    required this.evidence,
    this.requestedAmount,
  });

  final ComplaintReason reason;
  final String description;
  final RequestedOutcome requestedOutcome;

  /// PartialRefund only.
  final int? requestedAmount;
  final List<EvidenceDto> evidence;

  Map<String, dynamic> toJson() => {
        'reason': reason.apiValue,
        'description': description.trim(),
        'requestedOutcome': requestedOutcome.apiValue,
        if (requestedOutcome == RequestedOutcome.partialRefund)
          'requestedAmount': requestedAmount,
        'evidence': evidence.map((e) => e.toRequestJson()).toList(),
      };
}

/// PUT /chefs/me/bookings/{id}/plan/days/{dayIndex} (a draft).
class PlanDayRequestDto {
  const PlanDayRequestDto({required this.meals, this.chefNote});

  final List<PlanMealDto> meals;
  final String? chefNote;

  Map<String, dynamic> toJson() => {
        'chefNote':
            (chefNote?.trim().isEmpty ?? true) ? null : chefNote!.trim(),
        'meals': [
          for (final m in meals)
            {
              'slot': m.slot.apiValue,
              if (m.recipe.id.isNotEmpty) 'recipeId': apiId(m.recipe.id),
              'recipe': m.recipe.toJson(),
              if (m.note != null && m.note!.trim().isNotEmpty)
                'note': m.note!.trim(),
            },
        ],
      };
}

/// POST /chefs/me/bookings/{id}/complaint/response.
class ComplaintResponseRequestDto {
  const ComplaintResponseRequestDto(
      {required this.text, this.links = const []});

  final String text;
  final List<EvidenceDto> links;

  Map<String, dynamic> toJson() => {
        'text': text.trim(),
        'links': links.map((e) => e.toRequestJson()).toList(),
      };
}
