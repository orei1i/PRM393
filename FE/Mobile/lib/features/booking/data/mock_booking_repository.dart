// lib/features/booking/data/mock_booking_repository.dart
import '../../../core/network/api_exception.dart';
import '../../../core/session/mock_accounts.dart';
import '../../../core/session/user_role.dart';
import '../../../core/utils/mock_delay.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import '../../commerce/data/models/order_model.dart';
import '../../meal_planner/data/mock_meal_planner_repository.dart';
import '../domain/booking_enums.dart';
import '../domain/booking_rules.dart';
import 'booking_api_service.dart';
import 'mock/mock_booking_db.dart';
import 'models/booking_models.dart';

/// Booking flows on [MockBookingDb]. Errors like the real server: 401 for
/// guests, 404 for someone else's booking, 403 for the wrong party, 400 for
/// invalid input, 409 for a state that doesn't allow the action.
/// Triggers: `#fail` in the needs, a message, an offer note, a reason, a
/// day note or a complaint description → 503; `#expire` in the needs → the
/// payment window is 30 s.
class MockBookingRepository implements BookingApiService {
  MockBookingRepository({
    required this.currentUserId,
    required this.currentUserName,
    required this.currentRole,
  });

  final String? Function() currentUserId;
  final String Function() currentUserName;
  final UserRole Function() currentRole;

  MockBookingDb get _db => MockBookingDb.instance;

  String _me() =>
      currentUserId() ??
      (throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.'));

  static void _check(String? error) {
    if (error != null) throw mockError(400, error, 'validation');
  }

  static void _failIf(String? text, String what) {
    if (hasFailTrigger(text)) {
      throw mockError(503, 'Máy chủ đang bận, chưa $what. Thử lại sau.');
    }
  }

  /// The booking, if [me] is one of its two parties.
  (MockBookingRow, BookingParty) _mine(String id) {
    final me = _me();
    _db.settle();
    final row = _db.find(id);
    final party = row == null
        ? null
        : row.memberId == me
            ? BookingParty.member
            : row.chefUserId == me
                ? BookingParty.chef
                : null;
    if (row == null || party == null) {
      throw mockError(404, 'Không tìm thấy yêu cầu đặt chuyên gia.');
    }
    return (row, party);
  }

  MockBookingRow _as(String id, BookingParty expected) {
    final (row, party) = _mine(id);
    if (party != expected) {
      throw mockError(
          403,
          expected == BookingParty.chef
              ? 'Chỉ chuyên gia của yêu cầu này làm được thao tác này.'
              : 'Chỉ thành viên đặt yêu cầu này làm được thao tác này.',
          'wrong_party');
    }
    return row;
  }

  BookingDto _dto(MockBookingRow row) =>
      BookingDto.fromJson(_db.bookingJson(row));

  PlanDayDto _day(MockPlanDayRow day) => PlanDayDto.fromJson(day.toJson());

  void _validateTerms(
      {required int planDays, required int price, required DateTime start}) {
    _check(BookingRules.planDays(planDays));
    _check(BookingRules.price(price));
    _check(BookingRules.startDate(start, _db.today));
  }

  // ---- member & shared ----------------------------------------------------

  @override
  Future<BookingDto> createBooking(CreateBookingRequestDto request) async {
    await mockDelay(700);
    final me = _me();
    _failIf(request.needs, 'gửi được yêu cầu');
    _check(BookingRules.planDays(request.planDays));
    _check(BookingRules.startDate(request.startDate, _db.today));
    _check(BookingRules.needs(request.needs));
    _check(BookingRules.budget(request.budgetPerDay));
    if (request.mealPattern.isEmpty) _check('Chọn ít nhất 1 bữa.');
    final chef = _db.commerce.chef(request.chefId);
    if (chef.userId == me) {
      throw mockError(409, 'Bạn không thể tự đặt chính mình.', 'self_booking');
    }
    if (!chef.acceptingBookings) {
      throw mockError(
          409, 'Chuyên gia đang tạm ngưng nhận yêu cầu.', 'not_accepting');
    }
    if (request.planDays < chef.minPlanDays ||
        request.planDays > chef.maxPlanDays) {
      _check('${chef.fullName} nhận kế hoạch từ ${chef.minPlanDays} đến '
          '${chef.maxPlanDays} ngày.');
    }
    Map<String, dynamic>? health;
    if (request.shareHealthProfile) {
      try {
        // Nothing to share before the member sets a profile up.
        final profile =
            await MockMealPlannerRepository(userId: me).getHealthProfile();
        health = profile == null
            ? null
            : MockBookingDb.memberHealthJson(profile.toEntity());
      } on ApiException {
        health = null;
      }
    }
    final row = _db.create(
      memberId: me,
      memberName: currentUserName(),
      memberEmail:
          seededAccounts.where((a) => a.userId == me).firstOrNull?.email ?? '',
      chef: chef,
      request: request,
      memberHealth: health,
    );
    return _dto(row);
  }

  @override
  Future<List<BookingDto>> myBookings() async {
    await mockDelay(500);
    final me = _me();
    if (MockCommerceDb.emptyScenario()) return const [];
    _db.settle();
    final list = _db.bookings.where((b) => b.memberId == me).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.map(_dto).toList();
  }

  @override
  Future<BookingDto> getBooking(String id) async {
    await mockDelay(350);
    return _dto(_mine(id).$1);
  }

  @override
  Future<List<MessageDto>> messages(String id, {DateTime? after}) async {
    await mockDelay(200);
    final (row, _) = _mine(id);
    return [
      for (final m in row.messages)
        if (after == null || m.createdAt.isAfter(after))
          MessageDto.fromJson(m.toJson()),
    ];
  }

  @override
  Future<MessageDto> sendMessage(
      String id, SendMessageRequestDto request) async {
    await mockDelay(400);
    final (row, party) = _mine(id);
    if (request.attachmentUrl == null) {
      _check(BookingRules.message(request.body));
    }
    _failIf(request.body, 'gửi được tin nhắn');
    if (const {
      BookingStatus.declined,
      BookingStatus.cancelled,
      BookingStatus.expired,
    }.contains(row.status)) {
      throw mockError(
          409, 'Yêu cầu đã đóng, không nhắn thêm được.', 'invalid_status');
    }
    final message = _db.say(row, party, request.body.trim(),
        attachmentUrl: request.attachmentUrl);
    row.updatedAt = message.createdAt;
    return MessageDto.fromJson(message.toJson());
  }

  @override
  Future<BookingDto> sendOffer(String id, OfferRequestDto request) async {
    await mockDelay(600);
    final (row, party) = _mine(id);
    _validateTerms(
        planDays: request.planDays,
        price: request.price,
        start: request.startDate);
    _check(BookingRules.offerNote(request.note));
    _failIf(request.note, 'gửi được đề xuất');
    _db.addOffer(row, party, request);
    return _dto(row);
  }

  @override
  Future<BookingDto> respondToOffer(String id, String offerId,
      {required bool accept}) async {
    await mockDelay(600);
    final (row, party) = _mine(id);
    _db.respond(row, offerId, party, accept: accept);
    return _dto(row);
  }

  @override
  Future<BookingDto> cancel(String id, String reason) async {
    await mockDelay(500);
    final row = _as(id, BookingParty.member);
    _check(BookingRules.cancelReason(reason));
    _failIf(reason, 'huỷ được yêu cầu');
    _db.cancel(row, reason);
    return _dto(row);
  }

  @override
  Future<OrderDto> startPayment(String id) async {
    await mockDelay(600);
    final row = _as(id, BookingParty.member);
    final order = _db.startPayment(row);
    return OrderDto.fromJson(_db.commerce.orderJson(order));
  }

  @override
  Future<List<PlanDayDto>> plan(String id) async {
    await mockDelay(400);
    final (row, party) = _mine(id);
    // The member only sees what was sent; the chef sees drafts too.
    return [
      for (final d in row.days)
        if (party == BookingParty.chef || d.isSent) _day(d),
    ];
  }

  @override
  Future<PlanDayDto> sendDayFeedback(
      String id, int dayIndex, DayFeedbackDto feedback) async {
    await mockDelay(500);
    final row = _as(id, BookingParty.member);
    if (feedback.rating < 1 || feedback.rating > 5) {
      _check('Chọn từ 1 đến 5 sao.');
    }
    if (feedback.body.trim().length > BookingRules.maxFeedbackBody) {
      _check('Góp ý tối đa ${BookingRules.maxFeedbackBody} ký tự.');
    }
    _failIf(feedback.body, 'gửi được phản hồi');
    return _day(_db.feedback(row, dayIndex, feedback));
  }

  @override
  Future<BookingDto> fileComplaint(
      String id, ComplaintRequestDto request) async {
    await mockDelay(800);
    final row = _as(id, BookingParty.member);
    _check(BookingRules.complaintDescription(request.description));
    _check(BookingRules.evidence(
        request.reason, request.evidence.map((e) => e.kind)));
    for (final e in request.evidence) {
      if (!BookingRules.isHttpUrl(e.url)) {
        _check('Liên kết bằng chứng phải bắt đầu bằng http:// hoặc https://');
      }
    }
    final price = row.contract?.price ?? 0;
    if (request.requestedOutcome == RequestedOutcome.partialRefund) {
      _check(BookingRules.partialRefund(request.requestedAmount, price));
    }
    _failIf(request.description, 'gửi được khiếu nại');
    _db.fileComplaint(row, request);
    return _dto(row);
  }

  // ---- chef ---------------------------------------------------------------

  @override
  Future<List<BookingDto>> chefInbox() async {
    await mockDelay(500);
    final me = _me();
    if (currentRole() != UserRole.chef) {
      throw mockError(403, 'Chỉ dành cho chuyên gia.', 'not_chef');
    }
    if (MockCommerceDb.emptyScenario()) return const [];
    _db.settle();
    final list = _db.bookings.where((b) => b.chefUserId == me).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.map(_dto).toList();
  }

  @override
  Future<BookingDto> decline(String id, String reason) async {
    await mockDelay(500);
    final row = _as(id, BookingParty.chef);
    _check(BookingRules.declineReason(reason));
    _failIf(reason, 'gửi được phản hồi');
    _db.decline(row, reason);
    return _dto(row);
  }

  @override
  Future<PlanDayDto> savePlanDay(
      String id, int dayIndex, PlanDayRequestDto request) async {
    await mockDelay(500);
    final row = _as(id, BookingParty.chef);
    for (final m in request.meals) {
      _check(BookingRules.dishName(m.recipe.name));
      _failIf(m.recipe.name, 'lưu được kế hoạch');
    }
    _failIf(request.chefNote, 'lưu được kế hoạch');
    return _day(_db.saveDay(row, dayIndex, request));
  }

  @override
  Future<PlanDayDto> sendPlanDay(String id, int dayIndex) async {
    await mockDelay(600);
    final row = _as(id, BookingParty.chef);
    return _day(_db.sendDay(row, dayIndex));
  }

  @override
  Future<List<PlanDayDto>> sendWholePlan(String id) async {
    await mockDelay(800);
    final row = _as(id, BookingParty.chef);
    return _db.sendAll(row).map(_day).toList();
  }

  @override
  Future<ComplaintDto> respondToComplaint(
      String id, ComplaintResponseRequestDto request) async {
    await mockDelay(600);
    final row = _as(id, BookingParty.chef);
    _check(BookingRules.chefResponse(request.text));
    for (final e in request.links) {
      if (!BookingRules.isHttpUrl(e.url)) {
        _check('Liên kết phải bắt đầu bằng http:// hoặc https://');
      }
    }
    _failIf(request.text, 'gửi được phản hồi');
    final complaint = _db.respondToComplaint(row, request);
    return ComplaintDto.fromJson(complaint.toJson());
  }
}
