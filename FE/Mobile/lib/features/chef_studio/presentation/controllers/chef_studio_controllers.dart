// lib/features/chef_studio/presentation/controllers/chef_studio_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../chef/data/models/service_model.dart';
import '../../../commerce/data/models/consultation_model.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_studio_api_service.dart';
import '../../data/chef_wallet_api_service.dart';
import '../../data/models/chef_studio_models.dart';
import '../../data/models/wallet_models.dart';

/// Every chef-studio list refetches when the account changes (sign-out,
/// Minh Anh ↔ Tâm) or after any commerce change (a buyer paid, the chef
/// confirmed…). Screens sit behind `ChefOnlyGate`, so these never run for a
/// member.
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

final chefServicesProvider =
    FutureProvider.autoDispose<List<ServiceDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(chefStudioApiProvider).myServices();
});

final chefConsultationsProvider =
    FutureProvider.autoDispose<List<ConsultationDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(chefStudioApiProvider).myConsultations();
});

final chefOrdersProvider =
    FutureProvider.autoDispose<List<OrderDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(chefStudioApiProvider).myOrders();
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

class ChefDashboard {
  const ChefDashboard({
    required this.profile,
    required this.pendingCount,
    required this.todayCount,
    required this.monthRevenue,
    required this.pendingDocs,
    this.available,
    this.next,
  });

  /// `null`: no chef profile yet.
  final ChefProfileDto? profile;

  /// Consultations waiting for the chef to confirm.
  final int pendingCount;

  /// Confirmed or in progress, today.
  final int todayCount;

  /// Paid orders for my services, paid this month (VND).
  final int monthRevenue;
  final int pendingDocs;

  /// "Có thể rút" in the wallet; null when the wallet didn't load (the
  /// dashboard still shows, the tile just has no amount).
  final int? available;

  /// The next confirmed / in-progress / pending appointment.
  final ConsultationDto? next;
}

final chefDashboardProvider =
    FutureProvider.autoDispose<ChefDashboard>((ref) async {
  _watchScope(ref);
  final api = ref.watch(chefStudioApiProvider);
  final now = DateTime.now();
  ChefProfileDto? profile;
  try {
    profile = await api.getMyProfile();
  } on ApiException catch (e) {
    if (e.statusCode != 404) rethrow;
    return const ChefDashboard(
        profile: null,
        pendingCount: 0,
        todayCount: 0,
        monthRevenue: 0,
        pendingDocs: 0);
  }
  Future<int?> available() async {
    try {
      return (await ref.read(chefWalletApiProvider).getWallet()).available;
    } on ApiException {
      return null;
    }
  }

  final (consultations, orders, docs, wallet) = await (
    api.myConsultations(),
    api.myOrders(),
    api.myKnowledgeDocs(),
    available(),
  ).wait;

  bool isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;
  final open = consultations
      .where((c) =>
          (c.status == ConsultationStatus.pending ||
              c.status == ConsultationStatus.confirmed ||
              c.status == ConsultationStatus.inProgress) &&
          c.endAt.isAfter(now))
      .toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  final revenue = orders.where((o) {
    final paidAt = o.payment?.paidAt;
    return o.status == OrderStatus.paid &&
        paidAt != null &&
        paidAt.year == now.year &&
        paidAt.month == now.month;
  }).fold<int>(0, (sum, o) => sum + o.amount);

  return ChefDashboard(
    profile: profile,
    pendingCount: consultations
        .where((c) => c.status == ConsultationStatus.pending)
        .length,
    todayCount: consultations
        .where((c) =>
            (c.status == ConsultationStatus.confirmed ||
                c.status == ConsultationStatus.inProgress) &&
            isToday(c.startAt))
        .length,
    monthRevenue: revenue,
    pendingDocs:
        docs.where((d) => d.status == KnowledgeDocStatus.pending).length,
    available: wallet,
    next: open.firstOrNull,
  );
});
