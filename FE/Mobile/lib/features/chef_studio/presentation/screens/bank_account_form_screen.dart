// lib/features/chef_studio/presentation/screens/bank_account_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_wallet_api_service.dart';
import '../../data/models/wallet_models.dart';
import '../../domain/wallet_rules.dart';
import '../widgets/chef_only_gate.dart';

/// "Tài khoản nhận tiền": where withdrawals go. Pops the saved account.
class BankAccountFormScreen extends ConsumerStatefulWidget {
  const BankAccountFormScreen({super.key, this.initial});

  final BankAccountDto? initial;

  static Route<BankAccountDto> route({BankAccountDto? initial}) =>
      MaterialPageRoute<BankAccountDto>(
        fullscreenDialog: true,
        builder: (_) => BankAccountFormScreen(initial: initial),
      );

  @override
  ConsumerState<BankAccountFormScreen> createState() =>
      _BankAccountFormScreenState();
}

class _BankAccountFormScreenState extends ConsumerState<BankAccountFormScreen> {
  final _form = GlobalKey<FormState>();
  late String? _bank = widget.initial?.bankName;
  late final _number =
      TextEditingController(text: widget.initial?.accountNumber);
  late final _holder =
      TextEditingController(text: widget.initial?.accountHolder);
  bool _attempted = false;
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _form.currentState?.validate() ?? false;
    final bank = _bank;
    if (!valid || bank == null) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref.read(chefWalletApiProvider).saveBankAccount(
            BankAccountDto(
              bankName: bank,
              accountNumber: _number.text.trim(),
              accountHolder: _holder.text.trim(),
            ),
          );
      ref.read(commerceRevisionProvider.notifier).bump();
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = {...vietnamBanks, if (_bank != null) _bank!}.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản nhận tiền')),
      body: ChefOnlyGate(
        child: Form(
          key: _form,
          autovalidateMode: _attempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownMenu<String>(
                  initialSelection: _bank,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Ngân hàng'),
                  errorText:
                      _attempted && _bank == null ? 'Chọn ngân hàng.' : null,
                  dropdownMenuEntries: [
                    for (final b in banks)
                      DropdownMenuEntry(value: b, label: b),
                  ],
                  onSelected: (v) => setState(() => _bank = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _number,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 19,
                  decoration: const InputDecoration(
                    labelText: 'Số tài khoản',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => RegExp(r'^\d{6,19}$').hasMatch(v ?? '')
                      ? null
                      : 'Số tài khoản gồm 6–19 chữ số.',
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _holder,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Tên chủ tài khoản',
                    hintText: 'LE QUANG TAM',
                    helperText: 'Viết hoa, không dấu, đúng như ngân hàng ghi.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v ?? '').trim().length < 3
                      ? 'Nhập tên chủ tài khoản.'
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tiền rút chỉ chuyển vào tài khoản đứng tên bạn. Tên chủ tài khoản phải khớp với hồ sơ chuyên gia.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu tài khoản'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
