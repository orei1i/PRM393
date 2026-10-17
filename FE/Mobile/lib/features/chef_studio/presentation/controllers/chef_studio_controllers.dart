// lib/features/chef_studio/presentation/controllers/chef_studio_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_studio_api_service.dart';
import '../../data/chef_wallet_api_service.dart';
import '../../data/models/chef_studio_models.dart';
import '../../data/models/wallet_models.dart';

/// Every chef-studio list refetches when the account changes (sign-out,
/// Minh Anh ↔ Tâm) or after any booking or payment change (a member paid,
/// an escrow was released…). Screens sit behind `ChefOnlyGate`, so these
/// never run for a member.
void _watchScope(Ref ref) {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider);
}

/// `null` when the chef has no profile yet (404).
final chefStudioProfileProvider =
    FutureProvider.autoDispose<ChefProfileDto?>((ref) async {
  _watchScope(ref);
  try {
    return await ref.watch(chefStudioApiProvider).getMyProfile();
  } on ApiException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
});

final knowledgeDocsProvider =
    FutureProvider.autoDispose<List<KnowledgeDocDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(chefStudioApiProvider).myKnowledgeDocs();
});

final chefWalletProvider = FutureProvider.autoDispose<WalletDto>((ref) async {
  _watchScope(ref);
  return ref.watch(chefWalletApiProvider).getWallet();
});

/// Ledger of one month (`yyyy-MM`), or every month for null.
final walletTransactionsProvider = FutureProvider.autoDispose
    .family<List<WalletTransactionDto>, String?>((ref, month) async {
  _watchScope(ref);
  return ref.watch(chefWalletApiProvider).transactions(month: month);
});

final withdrawalsProvider =
    FutureProvider.autoDispose<List<WithdrawalDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(chefWalletApiProvider).withdrawals();
});
