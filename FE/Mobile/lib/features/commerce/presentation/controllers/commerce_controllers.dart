// lib/features/commerce/presentation/controllers/commerce_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../chef_studio/data/models/wallet_models.dart';
import '../../data/commerce_api_service.dart';
import '../../data/member_wallet_api_service.dart';
import '../../data/models/order_model.dart';

/// Bumped after any booking, payment or wallet change (member or chef).
/// Every list built from that data watches it and refetches, so "Lịch sử tư
/// vấn", "Yêu cầu tư vấn" and the wallet never show stale states.
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

final orderProvider =
    FutureProvider.autoDispose.family<OrderDto, String>((ref, id) async {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider);
  return ref.watch(commerceApiProvider).getOrder(id);
});

void _watchScope(Ref ref) {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider);
}

/// "Ví của tôi" of a member: balance (and the wallet option of the payment
/// screen).
final memberWalletProvider = FutureProvider.autoDispose<WalletDto>((ref) async {
  _watchScope(ref);
  return ref.watch(memberWalletApiProvider).getWallet();
});

final memberWalletTransactionsProvider =
    FutureProvider.autoDispose<List<WalletTransactionDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(memberWalletApiProvider).transactions();
});

final memberWithdrawalsProvider =
    FutureProvider.autoDispose<List<WithdrawalDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(memberWalletApiProvider).withdrawals();
});
