// lib/features/commerce/presentation/screens/member_wallet_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef_studio/data/models/wallet_models.dart';
import '../../../chef_studio/domain/wallet_rules.dart';
import '../../../chef_studio/presentation/screens/bank_account_form_screen.dart';
import '../../../chef_studio/presentation/screens/withdraw_screen.dart';
import '../../../chef_studio/presentation/widgets/wallet_widgets.dart';
import '../../data/member_wallet_api_service.dart';
import '../controllers/commerce_controllers.dart';
import '../widgets/commerce_ui.dart';

/// Tôi › "Ví của tôi" (member): the balance, refunds and payments, and
/// withdrawals to a bank account, which an admin approves. A user has one
/// wallet: a chef sees theirs with its earnings in Tôi › Chuyên gia.
class MemberWalletScreen extends StatelessWidget {
  const MemberWalletScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const MemberWalletScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ví của tôi')),
      body: DemoDataBanner.wrap(
        BackendModule.chefWallet,
        child: const _WalletBody(),
      ),
    );
  }
}

class _WalletBody extends ConsumerStatefulWidget {
  const _WalletBody();

  @override
  ConsumerState<_WalletBody> createState() => _WalletBodyState();
}

class _WalletBodyState extends ConsumerState<_WalletBody> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// While a withdrawal waits for an admin, refresh every 5 s so the decision
  /// shows up without pulling.
  void _syncPoll(bool processing) {
    if (processing) {
      _poll ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) _invalidate();
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _invalidate() {
    ref
      ..invalidate(memberWalletProvider)
      ..invalidate(memberWithdrawalsProvider)
      ..invalidate(memberWalletTransactionsProvider);
  }

  Future<void> _refresh() async {
    _invalidate();
    await ref.read(memberWalletProvider.future);
  }

  Future<void> _editAccount(BankAccountDto? current) async {
    final saved = await Navigator.of(context).push(BankAccountFormScreen.route(
        initial: current, owner: WalletOwner.member));
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu tài khoản nhận tiền.')));
    }
  }

  Future<void> _withdraw(WalletDto wallet) async {
    final navigator = Navigator.of(context);
    var account = wallet.bankAccount;
    if (account == null) {
      account = await navigator
          .push(BankAccountFormScreen.route(owner: WalletOwner.member));
      if (account == null || !mounted) return;
    }
    final created = await navigator.push(WithdrawScreen.route(
        available: wallet.available,
        account: account,
        owner: WalletOwner.member));
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Đã gửi yêu cầu rút ${formatVnd(created.amount)} · ${created.status.label}')));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(memberWalletProvider);
    final withdrawals = ref.watch(memberWithdrawalsProvider).valueOrNull ??
        const <WithdrawalDto>[];
    _syncPoll(withdrawals.any((w) => w.status == LedgerStatus.processing));
    return async.when(
      skipLoadingOnReload: true,
      data: (wallet) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            _BalanceCard(wallet: wallet, onWithdraw: () => _withdraw(wallet)),
            const SizedBox(height: 12),
            WalletBankCard(
                account: wallet.bankAccount,
                onEdit: () => _editAccount(wallet.bankAccount)),
            if (withdrawals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Yêu cầu rút tiền', style: context.textStyles.titleMedium),
              const SizedBox(height: 8),
              for (final w in withdrawals.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WalletWithdrawalTile(
                    item: w,
                    api: ref.read(memberWalletApiProvider),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text('Lịch sử giao dịch', style: context.textStyles.titleMedium),
            const SizedBox(height: 8),
            const _History(),
          ],
        ),
      ),
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(memberWalletProvider)),
        ),
      ),
      loading: () => const ListSkeleton(height: 120),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet, required this.onWithdraw});

  final WalletDto wallet;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Số dư ví',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatVnd(wallet.available),
                style: context.textStyles.headlineMedium?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800)),
          ),
          if (wallet.processing > 0) ...[
            const SizedBox(height: 6),
            Text('Đang chờ duyệt rút ${formatVnd(wallet.processing)}',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: vl.onCautionContainer)),
          ],
          if (wallet.withdrawn > 0) ...[
            const SizedBox(height: 2),
            Text('Đã rút ${formatVnd(wallet.withdrawn)}',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
          const SizedBox(height: 10),
          Text(
            'Tiền hoàn từ yêu cầu đã huỷ hoặc khiếu nại vào ví này. Bạn dùng để '
            'thanh toán kế hoạch tiếp theo hoặc rút về ngân hàng (tối thiểu '
            '${formatVnd(kMinWithdrawal)}, Ban quản trị duyệt).',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: wallet.available >= kMinWithdrawal ? onWithdraw : null,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Rút tiền'),
          ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memberWalletTransactionsProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (items) => items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Chưa có giao dịch nào.',
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted)),
            )
          : VLCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    _HistoryTile(item: items[i]),
                  ],
                ],
              ),
            ),
      error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(memberWalletTransactionsProvider)),
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final WalletTransactionDto item;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final t = item;
    final (IconData icon, Color color) = switch (t.type) {
      WalletEntryType.refund => (Icons.south_west_rounded, vl.success),
      WalletEntryType.payment => (
          Icons.receipt_long_outlined,
          context.colors.primary
        ),
      _ => (Icons.north_east_rounded, context.colors.primary),
    };
    final title = switch (t.type) {
      WalletEntryType.withdrawal => 'Rút tiền về ${t.bankName ?? 'ngân hàng'}',
      _ when t.planTitle != null => '${t.type.label} · ${t.planTitle}',
      _ => t.type.label,
    };
    final rejected = t.status == LedgerStatus.rejected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.titleSmall),
                const SizedBox(height: 2),
                Text(
                    [
                      formatStamp(t.createdAt),
                      if (t.transactionRef != null) 'Mã GD ${t.transactionRef}',
                    ].join(' · '),
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: vl.muted)),
                if (t.note != null) ...[
                  const SizedBox(height: 2),
                  Text(t.note!, style: context.textStyles.bodySmall),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (t.type == WalletEntryType.withdrawal)
                      ledgerStatusTag(context, t.status),
                    Text('${t.net >= 0 ? '+' : '−'}${formatVnd(t.net.abs())}',
                        style: context.textStyles.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: rejected
                              ? vl.muted
                              : t.net >= 0
                                  ? vl.onSuccessContainer
                                  : context.colors.onSurface,
                          decoration:
                              rejected ? TextDecoration.lineThrough : null,
                        )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
