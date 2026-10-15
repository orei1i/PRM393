// lib/features/commerce/presentation/controllers/commerce_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../data/commerce_api_service.dart';
import '../../data/models/consultation_model.dart';
import '../../data/models/order_model.dart';

/// Bumped after any order, payment or consultation change (buyer or chef).
/// Every list built from that data watches it and refetches, so "Đơn hàng
/// của tôi", "Lịch tư vấn" and the chef's bookings never show stale states.
final commerceRevisionProvider =
    NotifierProvider<CommerceRevision, int>(CommerceRevision.new);

class CommerceRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Who the per-user lists belong to. Signing out or switching accounts
/// (Minh Anh ↔ Tâm) changes it, which refetches every list that watches it.
final commerceAccountProvider =
    Provider<({bool guest, String? userId, String? token})>((ref) {
  return ref.watch(sessionControllerProvider.select(
      (s) => (guest: s.isGuest, userId: s.userId, token: s.accessToken)));
});

final myOrdersProvider = FutureProvider<List<OrderDto>>((ref) async {
  final account = ref.watch(commerceAccountProvider);
  ref.watch(commerceRevisionProvider);
  if (account.guest) return const [];
  return ref.watch(commerceApiProvider).myOrders();
});

/// The member's own consultations (Tôi › Lịch tư vấn, Chuyên gia tab).
final myConsultationsProvider =
    FutureProvider<List<ConsultationDto>>((ref) async {
  final account = ref.watch(commerceAccountProvider);
  ref.watch(commerceRevisionProvider);
  if (account.guest) return const [];
  return ref.watch(commerceApiProvider).myConsultations();
});

final orderProvider =
    FutureProvider.autoDispose.family<OrderDto, String>((ref, id) async {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider);
  return ref.watch(commerceApiProvider).getOrder(id);
});

final serviceContentProvider = FutureProvider.autoDispose
    .family<ServiceContentDto, String>((ref, serviceId) async {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider);
  return ref.watch(commerceApiProvider).getServiceContent(serviceId);
});

/// Services the member can open right now (paid package, Active grant):
/// the chef profile shows "Mở nội dung" instead of "Mua gói" for these.
final ownedServiceIdsProvider = Provider<Set<String>>((ref) {
  final orders = ref.watch(myOrdersProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return {
    for (final o in orders)
      if (o.canOpenContent(now)) o.serviceId
  };
});
