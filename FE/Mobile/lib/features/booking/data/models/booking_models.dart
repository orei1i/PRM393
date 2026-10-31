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
//   "goal": "lose_weight", "allergies": ["peanut"], "mealPattern": ["breakfast","lunch","dinner"],
//   "budgetPerDay": 80000, "needs": "…", "shareHealthProfile": true,
//   "status": "Negotiating", "deliveredDays": 0,
//   "currentOffer": OfferDto | null, "contract": ContractDto | null,
//   "escrow": EscrowHoldDto | null, "complaint": ComplaintDto | null,
//   "paymentOrderId": "ord_601" | null, "declineReason": null, "cancelReason": null,
//   "memberHealth": { "heightCm": 160, "weightKg": 55, "bmi": 21.5, "gender": "Female",
//                     "age": 29, "activityLevel": "light", "dailyKcalTarget": 1600 } | null,
//   "createdAt": "2026-10-16T03:00:00Z", "updatedAt": "…" }
//   memberHealth (mobile addition, computed by BE): sent only when shareHealthProfile
//   is true, to the two parties. The web console ignores it.
//
// OfferDto     { "id": "of_b_ma_tam_nego_1", "proposedBy": "chef" | "member", "price": 1500000,
//                "planDays": 10, "bookingType": "DailyFeedback", "startDate": "2026-10-20",
//                "note": "…", "status": "Open", "createdAt": "…", "respondedAt": null }
// ContractDto  { "id": "ct_…", "bookingId", "offerId", "price": 1500000, "planDays": 10,
//                "bookingType": "DailyFeedback", "startDate": "2026-10-20", "endDate": "2026-10-29",
//                "deliveryDueAt": "…", "dailySendCutoff": "06:00", "feedbackCutoff": "21:00",
//                "scopeText": "…", "feeRate": 0.1, "holdDays": 3, "paymentDueAt": "…", "createdAt": "…" }
// EscrowHoldDto { "id": "eh_604", "bookingId": "b_tram_tam", "paymentId": "pay_…", "amount": 1050000,
//                 "status": "Held" | "Frozen" | "Released" | "Refunded" | "PartiallyRefunded",
//                 "heldAt": "…", "releaseAt": "2026-10-19T16:59:00.000Z", "releasedAt": null,
//                 "releasedAmount": 0, "feeAmount": 0, "refundedAmount": 0,
//                 "resolvedBy": null, "resolutionNote": null }
//   releaseAt = endDate 23:59 Asia/Ho_Chi_Minh + 3 days. Released: net 90 % to the chef wallet.
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
// POST /bookings { chefId, bookingType, planDays, startDate, goal, allergies, mealPattern,
//                  budgetPerDay?, needs, shareHealthProfile } → BookingDto (Requested)
//      409 self_booking, 409 not_accepting, 400 validation, 401 guest
// POST /bookings/{id}/messages { body, attachmentUrl? } → MessageDto ; GET ?after= → [MessageDto]
// POST /bookings/{id}/offers { price, planDays, bookingType, startDate, note } → BookingDto
// POST /bookings/{id}/offers/{offerId}/accept|reject → BookingDto
//      accept: contract created, AwaitingPayment,
//      paymentDueAt = min(now + 48 h, startDate 00:00 VN)
// POST /bookings/{id}/cancel { reason } ; POST /chefs/me/bookings/{id}/decline { reason }
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
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';

int? _intOrNull(Object? value) => value == null ? null : readInt(value);

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

  /// endDate 23:59 VN + [holdDays].
  DateTime get releaseAt => escrowReleaseAt(endDate, holdDays: holdDays);
}

class EscrowHoldDto {
  const EscrowHoldDto({
    required this.id,
    required this.amount,
    required this.status,
    required this.heldAt,
    required this.releaseAt,
    this.bookingId = '',
    this.paymentId = '',
    this.releasedAt,
    this.releasedAmount = 0,
    this.feeAmount = 0,
    this.refundedAmount = 0,
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
        releaseAt: readDateTime(json['releaseAt']) ?? DateTime.now(),
        releasedAt: readDateTime(json['releasedAt']),
        releasedAmount: readInt(json['releasedAmount']),
        feeAmount: readInt(json['feeAmount']),
        refundedAmount: readInt(json['refundedAmount']),
        resolvedBy: json['resolvedBy'] as String?,
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
  final DateTime releaseAt;
  final DateTime? releasedAt;

  /// Gross that went to the chef (before the fee).
  final int releasedAmount;
  final int feeAmount;

  /// Sent back to the member's original payment method.
  final int refundedAmount;
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
        decidedBy: json['decidedBy'] as String?,
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
      instructions: json['instructions'] as String?,
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

  /// "160 cm · 55 kg · BMI 21,5 · Nữ · 29 tuổi · ≈ 1.600 kcal/ngày".
  String get summary => [
        if (heightCm != null) '${formatDecimal(heightCm!, digits: 0)} cm',
        if (weightKg != null) '${formatDecimal(weightKg!, digits: 0)} kg',
        if (bmi != null) 'BMI ${formatDecimal(bmi!)}',
        if (gender != null)
          switch (gender) {
            'Male' => 'Nam',
            'Female' => 'Nữ',
            _ => 'Khác',
          },
        if (age != null) '$age tuổi',
        // Same rounding as the member's "Hồ sơ sức khoẻ" (2.060, not 2.063).
        if (dailyKcalTarget != null)
          '≈ ${Energy.formatKcal(dailyKcalTarget!)} kcal/ngày',
      ].join(' · ');
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
    this.goal = 'maintain',
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
    this.updatedAt,
  });

  factory BookingDto.fromJson(Map<String, dynamic> json) => BookingDto(
        id: json['id']?.toString() ?? '',
        member: BookingPersonDto.fromJson(readMap(json['member'])),
        chef: BookingPersonDto.fromJson(readMap(json['chef'])),
        bookingType: BookingType.fromApi(json['bookingType']),
        planDays: readInt(json['planDays']),
        startDate: readDate(json['startDate']),
        goal: json['goal'] as String? ?? 'maintain',
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
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        updatedAt: readDateTime(json['updatedAt']),
      );

  final String id;
  final BookingPersonDto member;
  final BookingPersonDto chef;
  final BookingType bookingType;
  final int planDays;
  final DateTime startDate;
  final String goal;

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
  final DateTime createdAt;
  final DateTime? updatedAt;

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

  /// Member can file a complaint: paid, escrow still Held, before releaseAt,
  /// no complaint yet.
  bool canComplain(DateTime now) =>
      complaint == null &&
      escrow != null &&
      escrow!.status == EscrowStatus.held &&
      now.isBefore(escrow!.releaseAt) &&
      (status == BookingStatus.active || status == BookingStatus.ended);
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
    this.budgetPerDay,
    this.shareHealthProfile = true,
  });

  final String chefId;
  final BookingType bookingType;
  final int planDays;
  final DateTime startDate;
  final String goal;
  final List<String> allergies;
  final List<MealSlot> mealPattern;
  final int? budgetPerDay;
  final String needs;
  final bool shareHealthProfile;

  Map<String, dynamic> toJson() => {
        'chefId': apiId(chefId),
        'bookingType': bookingType.apiValue,
        'planDays': planDays,
        'startDate': toApiDate(startDate),
        'goal': goal,
        'allergies': allergies,
        'mealPattern': MealPattern.toApi(mealPattern),
        'budgetPerDay': budgetPerDay,
        'needs': needs.trim(),
        'shareHealthProfile': shareHealthProfile,
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
