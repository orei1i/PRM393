// lib/features/chef_studio/presentation/screens/chef_wallet_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../booking/domain/booking_rules.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/wallet_models.dart';
import '../../domain/wallet_rules.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_only_gate.dart';
import 'bank_account_form_screen.dart';
import 'withdraw_screen.dart';

/// "Ví của tôi": balance (Có thể rút · Đang giữ · Tạm giữ do khiếu nại ·
/// Đã rút), bank account, withdrawal requests and the monthly ledger, one
/// row per paid booking that follows its escrow hold.
class ChefWalletScreen extends StatelessWidget {
  const ChefWalletScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefWalletScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ví của tôi')),
      body: DemoDataBanner.wrap(
        BackendModule.chefWallet,
        child: const ChefOnlyGate(child: _WalletBody()),
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
  /// `yyyy-MM`, null = every month.
  String? _month;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// While a withdrawal is "Đang xử lý", refresh every 5 s so the payout
  /// (or an admin decision) shows up without pulling.
  void _syncPoll(bool processing) {
    if (processing) {
      _poll ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        ref
          ..invalidate(chefWalletProvider)
          ..invalidate(withdrawalsProvider)
          ..invalidate(walletTransactionsProvider(_month));
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(withdrawalsProvider)
      ..invalidate(walletTransactionsProvider(_month))
      ..invalidate(chefWalletProvider);
    await ref.read(chefWalletProvider.future);
  }

  Future<void> _editAccount(BankAccountDto? current) async {
    final saved = await Navigator.of(context)
        .push(BankAccountFormScreen.route(initial: current));
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu tài khoản nhận tiền.')));
    }
  }

  Future<void> _withdraw(WalletDto wallet) async {
    final navigator = Navigator.of(context);
    var account = wallet.bankAccount;
    if (account == null) {
      account = await navigator.push(BankAccountFormScreen.route());
      if (account == null || !mounted) return;
    }
    final created = await navigator.push(
        WithdrawScreen.route(available: wallet.available, account: account));
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Đã gửi yêu cầu rút ${formatVnd(created.amount)} · ${created.status.label}')));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chefWalletProvider);
    final withdrawals =
        ref.watch(withdrawalsProvider).valueOrNull ?? const <WithdrawalDto>[];
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
            _BankCard(
                account: wallet.bankAccount,
                onEdit: () => _editAccount(wallet.bankAccount)),
            if (withdrawals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Yêu cầu rút tiền', style: context.textStyles.titleMedium),
              const SizedBox(height: 8),
              for (final w in withdrawals.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WithdrawalTile(item: w),
                ),
            ],
            const SizedBox(height: 16),
            Text('Lịch sử giao dịch', style: context.textStyles.titleMedium),
            const SizedBox(height: 8),
            _MonthChips(
                selected: _month,
                onSelected: (m) => setState(() => _month = m)),
            const SizedBox(height: 8),
            _Ledger(month: _month),
          ],
        ),
      ),
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error, onRetry: () => ref.invalidate(chefWalletProvider)),
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
    final percent = (wallet.feeRate * 100).round();
    Widget figure(String label, int value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatVnd(value),
                    style: context.textStyles.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Có thể rút',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatVnd(wallet.available),
                style: context.textStyles.headlineMedium?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure('Đang giữ', wallet.pending),
              const SizedBox(width: 12),
              figure('Tạm giữ do khiếu nại', wallet.frozen),
              const SizedBox(width: 12),
              figure('Đã rút', wallet.withdrawn),
            ],
          ),
          if (wallet.processing > 0) ...[
            const SizedBox(height: 6),
            Text('Đang xử lý rút ${formatVnd(wallet.processing)}',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: vl.onCautionContainer)),
          ],
          const SizedBox(height: 10),
          Text(
            'Phí nền tảng $percent% mỗi kế hoạch. Tiền thành viên trả được giữ đến '
            '${wallet.holdDays} ngày sau khi kế hoạch kết thúc, rồi chuyển vào "Có thể rút" nếu không có khiếu nại; '
            'khi có khiếu nại, tiền tạm giữ đến khi Ban quản trị quyết định.',
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

class _BankCard extends StatelessWidget {
  const _BankCard({required this.account, required this.onEdit});

  final BankAccountDto? account;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final a = account;
    return VLCard(
      onTap: onEdit,
      child: Row(
        children: [
          Icon(Icons.account_balance_outlined, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: a == null
                ? Text('Chưa có tài khoản nhận tiền',
                    style: context.textStyles.titleSmall)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a.bankName} ${a.masked}',
                          style: context.textStyles.titleSmall),
                      Text(a.accountHolder,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.vl.muted)),
                    ],
                  ),
          ),
          Text(a == null ? 'Thêm' : 'Sửa',
              style: context.textStyles.labelLarge?.copyWith(
                  color: context.colors.primary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

Widget _ledgerTag(BuildContext context, LedgerStatus status) {
  final vl = context.vl;
  final (Color bg, Color fg) = switch (status) {
    LedgerStatus.available || LedgerStatus.completed => (
        vl.successContainer,
        vl.onSuccessContainer
      ),
    LedgerStatus.held || LedgerStatus.processing => (
        vl.cautionContainer,
        vl.onCautionContainer
      ),
    LedgerStatus.frozen || LedgerStatus.rejected => (
        context.colors.errorContainer,
        context.colors.onErrorContainer
      ),
    LedgerStatus.reversed => (vl.aiContainer, vl.onAiContainer),
  };
  return StatusPill(label: status.label, background: bg, foreground: fg);
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.item});

  final WithdrawalDto item;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(formatVnd(item.amount),
                  style: context.textStyles.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              _ledgerTag(context, item.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${item.bankName} ${item.accountNumber} · ${formatStamp(item.createdAt)}',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
          if (item.reason != null) ...[
            const SizedBox(height: 4),
            Text(
                item.status == LedgerStatus.rejected
                    ? 'Lý do: ${item.reason}'
                    : item.reason!,
                style: context.textStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// "Tất cả" + the last 6 months; scrolls sideways at large text.
class _MonthChips extends StatelessWidget {
  const _MonthChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = <(String?, String)>[
      (null, 'Tất cả'),
      for (var i = 0; i < 6; i++)
        () {
          final d = DateTime(now.year, now.month - i);
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          return (key, 'Tháng ${d.month}/${d.year}');
        }(),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final maxChipWidth = math.max(0.0, constraints.maxWidth);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, (key, label)) in months.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChipWidth),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected == key,
                  onSelected: (_) => onSelected(key),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _Ledger extends ConsumerWidget {
  const _Ledger({required this.month});

  final String? month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(walletTransactionsProvider(month));
    return async.when(
      skipLoadingOnReload: true,
      data: (items) => items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  month == null
                      ? 'Chưa có giao dịch nào.'
                      : 'Không có giao dịch trong tháng này.',
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
                    _LedgerTile(item: items[i]),
                  ],
                ],
              ),
            ),
      error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(walletTransactionsProvider(month))),
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.item});

  final WalletTransactionDto item;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final t = item;
    final (IconData icon, Color color) = switch (t.type) {
      WalletEntryType.income => (Icons.south_west_rounded, vl.success),
      WalletEntryType.refund => (Icons.undo_rounded, vl.ai),
      WalletEntryType.withdrawal => (
          Icons.north_east_rounded,
          context.colors.primary
        ),
    };
    final title = switch (t.type) {
      WalletEntryType.withdrawal => 'Rút tiền về ${t.bankName ?? 'ngân hàng'}',
      _ => '${t.type.label} · ${t.planTitle ?? ''}',
    };
    final details = <String>[
      formatStamp(t.createdAt),
      if (t.transactionRef != null) 'Mã GD ${t.transactionRef}',
      if (t.memberName != null) t.memberName!,
    ].join(' · ');
    final holdNote = switch (t.status) {
      LedgerStatus.held when t.releaseAt != null =>
        'Giữ đến ${formatVnStamp(t.releaseAt!)} ($kEscrowHoldDays ngày sau khi kế hoạch kết thúc)',
      LedgerStatus.frozen =>
        'Tạm giữ do khiếu nại — chờ Ban quản trị quyết định',
      _ => null,
    };
    final sign = t.net >= 0 ? '+' : '−';
    final faded = t.status == LedgerStatus.rejected;

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
                Text(details,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: vl.muted)),
                if (t.gross != null && t.fee != null) ...[
                  const SizedBox(height: 2),
                  Text(
                      'Gộp ${formatVnd(t.gross!.abs())} · Phí ${formatVnd(t.fee!.abs())} · Thực nhận ${formatVnd(t.net.abs())}',
                      style: context.textStyles.bodySmall),
                ],
                if (holdNote != null) ...[
                  const SizedBox(height: 2),
                  Text(holdNote,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: vl.onCautionContainer)),
                ],
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
                    _ledgerTag(context, t.status),
                    Text('$sign${formatVnd(t.net.abs())}',
                        style: context.textStyles.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: faded
                              ? vl.muted
                              : t.net >= 0
                                  ? vl.onSuccessContainer
                                  : context.colors.onSurface,
                          decoration: faded ? TextDecoration.lineThrough : null,
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
