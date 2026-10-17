// lib/features/booking/presentation/controllers/booking_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_views.dart';

/// Every booking list and detail refetches when the account changes or after
/// any booking / payment change ([commerceRevisionProvider], bumped by every
/// action screen).
void _watchScope(Ref ref) {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider);
}

extension BookingRefresh on WidgetRef {
  /// Bumps the shared revision: lists, details and the wallet refetch.
  void bookingChanged() => read(commerceRevisionProvider.notifier).bump();
}

/// "Lịch sử tư vấn": the bookings I made (empty for guests).
final myBookingsProvider =
    FutureProvider.autoDispose<List<BookingDto>>((ref) async {
  _watchScope(ref);
  if (ref.watch(sessionControllerProvider.select((s) => s.isGuest))) {
    return const [];
  }
  return ref.watch(bookingApiProvider).myBookings();
});

/// "Yêu cầu tư vấn": bookings made with me (empty unless signed in as Chef).
final chefInboxProvider =
    FutureProvider.autoDispose<List<BookingDto>>((ref) async {
  _watchScope(ref);
  if (!ref.watch(sessionControllerProvider.select((s) => s.isChef))) {
    return const [];
  }
  return ref.watch(bookingApiProvider).chefInbox();
});

/// KPIs and the badge of Tôi › Chuyên gia; `null` while loading or for
/// members.
final chefBookingStatsProvider = Provider.autoDispose<ChefBookingStats?>((ref) {
  final inbox = ref.watch(chefInboxProvider).valueOrNull;
  return inbox == null ? null : chefBookingStats(inbox, DateTime.now());
});

final bookingProvider =
    FutureProvider.autoDispose.family<BookingDto, String>((ref, id) async {
  _watchScope(ref);
  return ref.watch(bookingApiProvider).getBooking(id);
});

/// The chat, oldest first. Polled by the booking screen every 5 s.
final bookingMessagesProvider = FutureProvider.autoDispose
    .family<List<MessageDto>, String>((ref, id) async {
  _watchScope(ref);
  return ref.watch(bookingApiProvider).messages(id);
});

/// Plan days (sent ones for the member, drafts too for the chef).
final bookingPlanProvider = FutureProvider.autoDispose
    .family<List<PlanDayDto>, String>((ref, id) async {
  _watchScope(ref);
  return ref.watch(bookingApiProvider).plan(id);
});
