// lib/features/chef_studio/presentation/screens/withdraw_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/data/member_wallet_api_service.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_wallet_api_service.dart';
import '../../data/models/wallet_models.dart';
import '../../domain/wallet_rules.dart';
import '../widgets/chef_only_gate.dart';
import 'bank_account_form_screen.dart';

/// "Rút tiền": amount (≥ 100.000đ, ≤ the balance) to the saved bank account,
/// confirmed in a dialog, for a chef's or a member's wallet. An admin approves
/// every request. Pops the created withdrawal.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({
    super.key,
    required this.available,
    required this.account,
    this.owner = WalletOwner.chef,
  });

  final int available;
  final BankAccountDto account;
  final WalletOwner owner;

  static Route<WithdrawalDto> route({
    required int available,
    required BankAccountDto account,
    WalletOwner owner = WalletOwner.chef,
  }) =>
      MaterialPageRoute<WithdrawalDto>(
        fullscreenDialog: true,
        builder: (_) => WithdrawScreen(
            available: available, account: account, owner: owner),
      );

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late BankAccountDto _account = widget.account;
  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_amount.text.trim());

  String? _validate(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < kMinWithdrawal) {
      return 'Tối thiểu ${formatVnd(kMinWithdrawal)}.';
    }
    if (n > widget.available) {
      return 'Vượt quá số dư có thể rút (${formatVnd(widget.available)}).';
    }
    return null;
  }

  Future<void> _changeAccount() async {
    final saved = await Navigator.of(context).push(
        BankAccountFormScreen.route(initial: _account, owner: widget.owner));
    if (saved != null && mounted) setState(() => _account = saved);
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final amount = _value!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận rút tiền?'),
        content: Text(
            'Rút ${formatVnd(amount)} về ${_account.bankName} ${_account.masked} '
            '(${_account.accountHolder}).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      final WalletWithdrawalApi api = widget.owner == WalletOwner.chef
          ? ref.read(chefWalletApiProvider)
          : ref.read(memberWalletApiProvider);
      final created =
          await api.requestWithdrawal(WithdrawalRequestDto(amount: amount));
      ref.read(commerceRevisionProvider.notifier).bump();
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final value = _value;
    final enough = widget.available >= kMinWithdrawal;
    final form = _buildForm(vl, value, enough);
    return Scaffold(
      appBar: AppBar(title: const Text('Rút tiền')),
      body: widget.owner == WalletOwner.chef ? ChefOnlyGate(child: form) : form,
    );
  }

  Widget _buildForm(VLColors vl, int? value, bool enough) => Form(
        key: _form,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VLCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.owner == WalletOwner.chef
                            ? 'Có thể rút'
                            : 'Số dư ví',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: vl.muted)),
                    Text(formatVnd(widget.available),
                        style: context.textStyles.headlineSmall?.copyWith(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              VLCard(
                child: Row(
                  children: [
                    Icon(Icons.account_balance_outlined,
                        color: context.colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_account.bankName} ${_account.masked}',
                              style: context.textStyles.titleSmall),
                          Text(_account.accountHolder,
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted)),
                        ],
                      ),
                    ),
                    TextButton(
                        onPressed: _sending ? null : _changeAccount,
                        child: const Text('Đổi')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                enabled: enough,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Số tiền rút (đ)',
                  hintText: '$kMinWithdrawal',
                  helperText: value == null ? null : formatVnd(value),
                  border: const OutlineInputBorder(),
                  suffixIcon: TextButton(
                    onPressed: !enough
                        ? null
                        : () => setState(
                            () => _amount.text = widget.available.toString()),
                    child: const Text('Rút hết'),
                  ),
                ),
                validator: _validate,
              ),
              const SizedBox(height: 12),
              VLCard(
                color: vl.cautionContainer,
                borderColor: Colors.transparent,
                child: Text(
                  !enough
                      ? 'Cần ít nhất ${formatVnd(kMinWithdrawal)} trong ví để tạo yêu cầu.'
                      : 'Ban quản trị duyệt yêu cầu trong 1–2 ngày làm việc, rồi tiền về tài khoản của bạn.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: vl.onCautionContainer),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: !enough || _sending ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: Text(_sending ? 'Đang gửi…' : 'Tiếp tục'),
              ),
            ],
          ),
        ),
      );
}
