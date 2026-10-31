// lib/features/booking/data/booking_api_service.dart
//
// Chef meal-plan bookings (plan D15). Request / response samples sit at the
// top of `models/booking_models.dart`.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/mock_persona.dart';
import '../../../core/session/session_controller.dart';
import '../../commerce/data/models/order_model.dart';
import 'mock_booking_repository.dart';
import 'models/booking_models.dart';

/// Member side (request, negotiate, pay, receive, give feedback, complain)
/// and chef side (inbox, decline, compose and send plan days, answer a
/// complaint) of a booking. Every booking call needs a signed-in user (401
/// otherwise); chef calls need the Chef role (403).
abstract interface class BookingApiService {
  // ---- member & shared ----------------------------------------------------

  /// Starts a booking in `Requested`. 409 `self_booking`, 409
  /// `not_accepting`, 400 on invalid input, 503 for `#fail` in the needs.
  Future<BookingDto> createBooking(CreateBookingRequestDto request);

  /// "Lịch sử tư vấn": the bookings I made as a member, newest first.
  Future<List<BookingDto>> myBookings();

  /// Either party.
  Future<BookingDto> getBooking(String id);

  /// The chat, oldest first; [after] returns only newer messages (polled).
  Future<List<MessageDto>> messages(String id, {DateTime? after});

  Future<MessageDto> sendMessage(String id, SendMessageRequestDto request);

  /// A price offer or counter-offer; the previous open offer is superseded.
  Future<BookingDto> sendOffer(String id, OfferRequestDto request);

  /// Only the other party can answer, and only the latest open offer.
  /// Accepting creates the contract (payment due in 48 h).
  Future<BookingDto> respondToOffer(String id, String offerId,
      {required bool accept});

  /// Member, before payment.
  Future<BookingDto> cancel(String id, String reason);

  /// The PaymentOS order funding the escrow, with an open QR.
  Future<OrderDto> startPayment(String id);

  /// Every plan day (sent ones for the member; drafts too for the chef).
  Future<List<PlanDayDto>> plan(String id);

  /// DailyFeedback, a sent day only.
  Future<PlanDayDto> sendDayFeedback(
      String id, int dayIndex, DayFeedbackDto feedback);

  /// Member, from payment until releaseAt. Freezes the escrow.
  Future<BookingDto> fileComplaint(String id, ComplaintRequestDto request);

  // ---- chef ---------------------------------------------------------------

  /// "Yêu cầu tư vấn": every booking made with me, newest activity first.
  Future<List<BookingDto>> chefInbox();

  /// Before payment, reason ≥ 10 characters.
  Future<BookingDto> decline(String id, String reason);

  Future<PlanDayDto> savePlanDay(
      String id, int dayIndex, PlanDayRequestDto request);

  /// DailyFeedback: one complete day, in order.
  Future<PlanDayDto> sendPlanDay(String id, int dayIndex);

  /// OneShot: every day, once all are complete.
  Future<List<PlanDayDto>> sendWholePlan(String id);

  Future<ComplaintDto> respondToComplaint(
      String id, ComplaintResponseRequestDto request);
}

class RemoteBookingApiService implements BookingApiService {
  RemoteBookingApiService(this._dio);

  final Dio _dio;

  List<T> _list<T>(List<dynamic>? data, T Function(Map<String, dynamic>) f) =>
      (data ?? const []).whereType<Map<String, dynamic>>().map(f).toList();

  Future<BookingDto> _postBooking(String path, [Object? body]) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(path, data: body);
        return BookingDto.fromJson(res.data!);
      });

  @override
  Future<BookingDto> createBooking(CreateBookingRequestDto request) =>
      _postBooking(ApiEndpoints.bookings, request.toJson());

  @override
  Future<List<BookingDto>> myBookings() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myBookings);
        return _list(res.data, BookingDto.fromJson);
      });

  @override
  Future<BookingDto> getBooking(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.booking(id));
        return BookingDto.fromJson(res.data!);
      });

  @override
  Future<List<MessageDto>> messages(String id, {DateTime? after}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(
            ApiEndpoints.bookingMessages(id),
            queryParameters: {
              if (after != null) 'after': after.toUtc().toIso8601String(),
            });
        return _list(res.data, MessageDto.fromJson);
      });

  @override
  Future<MessageDto> sendMessage(String id, SendMessageRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.bookingMessages(id),
            data: request.toJson());
        return MessageDto.fromJson(res.data!);
      });

  @override
  Future<BookingDto> sendOffer(String id, OfferRequestDto request) =>
      _postBooking(ApiEndpoints.bookingOffers(id), request.toJson());

  @override
  Future<BookingDto> respondToOffer(String id, String offerId,
          {required bool accept}) =>
      _postBooking(ApiEndpoints.bookingOfferAction(
          id, offerId, accept ? 'accept' : 'reject'));

  @override
  Future<BookingDto> cancel(String id, String reason) =>
      _postBooking(ApiEndpoints.bookingCancel(id), {'reason': reason.trim()});

  @override
  Future<OrderDto> startPayment(String id) => guardApi(() async {
        final res = await _dio
            .post<Map<String, dynamic>>(ApiEndpoints.bookingPayments(id));
        return OrderDto.fromJson(res.data!);
      });

  @override
  Future<List<PlanDayDto>> plan(String id) => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.bookingPlan(id));
        return _list(res.data, PlanDayDto.fromJson);
      });

  @override
  Future<PlanDayDto> sendDayFeedback(
          String id, int dayIndex, DayFeedbackDto feedback) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.bookingDayFeedback(id, dayIndex),
            data: feedback.toRequestJson());
        return PlanDayDto.fromJson(res.data!);
      });

  @override
  Future<BookingDto> fileComplaint(String id, ComplaintRequestDto request) =>
      _postBooking(ApiEndpoints.bookingComplaint(id), request.toJson());

  @override
  Future<List<BookingDto>> chefInbox() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myChefBookings);
        return _list(res.data, BookingDto.fromJson);
      });

  @override
  Future<BookingDto> decline(String id, String reason) => _postBooking(
      ApiEndpoints.chefBookingDecline(id), {'reason': reason.trim()});

  @override
  Future<PlanDayDto> savePlanDay(
          String id, int dayIndex, PlanDayRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.chefPlanDay(id, dayIndex),
            data: request.toJson());
        return PlanDayDto.fromJson(res.data!);
      });

  @override
  Future<PlanDayDto> sendPlanDay(String id, int dayIndex) => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.chefPlanDaySend(id, dayIndex));
        return PlanDayDto.fromJson(res.data!);
      });

  @override
  Future<List<PlanDayDto>> sendWholePlan(String id) => guardApi(() async {
        final res =
            await _dio.post<List<dynamic>>(ApiEndpoints.chefPlanSendAll(id));
        return _list(res.data, PlanDayDto.fromJson);
      });

  @override
  Future<ComplaintDto> respondToComplaint(
          String id, ComplaintResponseRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
            ApiEndpoints.chefComplaintResponse(id),
            data: request.toJson());
        return ComplaintDto.fromJson(res.data!);
      });
}

final bookingApiProvider = Provider<BookingApiService>((ref) {
  if (BackendModules.isMock(BackendModule.bookings)) {
    return MockBookingRepository(
      currentUserId: () => mockPersonaId(ref.read(sessionControllerProvider)),
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Bạn',
      currentRole: () => ref.read(sessionControllerProvider).role,
    );
  }
  return RemoteBookingApiService(ref.watch(dioProvider));
});
