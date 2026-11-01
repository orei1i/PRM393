// lib/features/chef_studio/presentation/widgets/wallet_widgets.dart
//
// What the chef's and the member's wallets share: the bank account card, the
// status chip and a withdrawal with its mock approval.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/chef_wallet_api_service.dart';
import '../../data/models/wallet_models.dart';

class WalletBankCard extends StatelessWidget {
  const WalletBankCard(
      {super.key, required this.account, required this.onEdit});

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

Widget ledgerStatusTag(BuildContext context, LedgerStatus status) {
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

/// One withdrawal. While the wallet is mock, a request waiting for an admin has
/// "Mô phỏng duyệt" / "Mô phỏng từ chối" (the real approval is web `/payouts`).
class WalletWithdrawalTile extends ConsumerStatefulWidget {
  const WalletWithdrawalTile(
      {super.key, required this.item, required this.api});

  final WithdrawalDto item;
  final WalletWithdrawalApi api;

  @override
  ConsumerState<WalletWithdrawalTile> createState() =>
      _WalletWithdrawalTileState();
}

class _WalletWithdrawalTileState extends ConsumerState<WalletWithdrawalTile> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    setState(() => _busy = true);
    try {
      await widget.api.mockDecideWithdrawal(widget.item.id, approve: approve);
      if (!mounted) return;
      ref.read(commerceRevisionProvider.notifier).bump();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
              ledgerStatusTag(context, item.status),
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
          if (item.status == LedgerStatus.processing &&
              BackendModules.walletMockControls) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _decide(approve: true),
                  child: const Text('Mô phỏng duyệt'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _decide(approve: false),
                  child: const Text('Mô phỏng từ chối'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
