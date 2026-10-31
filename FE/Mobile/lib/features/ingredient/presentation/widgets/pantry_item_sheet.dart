// lib/features/ingredient/presentation/widgets/pantry_item_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/pantry_controller.dart';

/// "Sửa số lượng & hạn dùng" of a fridge item. A failure stays in the sheet
/// with the input kept. The server keeps a date once set, so it can only be
/// changed, not removed.
class PantryItemSheet extends ConsumerStatefulWidget {
  const PantryItemSheet({super.key, required this.item});

  final PantryItem item;

  static Future<void> show(BuildContext context, PantryItem item) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => PantryItemSheet(item: item),
      );

  @override
  ConsumerState<PantryItemSheet> createState() => _PantryItemSheetState();
}

class _PantryItemSheetState extends ConsumerState<PantryItemSheet> {
  final _form = GlobalKey<FormState>();
  late final _quantity = TextEditingController(
      text: _plain(widget.item.quantity ?? 1).replaceAll('.', ','));
  late final _unit = TextEditingController(text: widget.item.unit ?? 'phần');
  late DateTime? _expiry = widget.item.expiryDate?.toLocal();
  bool _saving = false;
  String? _error;

  static String _plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  double? get _parsedQuantity =>
      double.tryParse(_quantity.text.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(ref.read(plannerClockProvider)());
    final initial = _expiry ?? today;
    final first = initial.isBefore(today) ? initial : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final expiry = _expiry;
    // Only a changed date is sent: an unchanged one must not shift by a day
    // on the way through the time zones.
    final before = widget.item.expiryDate?.toLocal();
    final dateChanged =
        expiry != null && (before == null || !isSameDay(before, expiry));
    try {
      await ref.read(pantryControllerProvider.notifier).updateItem(
            widget.item,
            quantity: _parsedQuantity!,
            unit: _unit.text.trim(),
            expiryDate: dateChanged ? expiry : null,
          );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final expiry = _expiry;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sửa số lượng & hạn dùng',
                    style: context.textStyles.titleLarge),
                const SizedBox(height: 4),
                Text(widget.item.ingredient,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: vl.muted)),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          LengthLimitingTextInputFormatter(7),
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Số lượng'),
                        validator: (_) => (_parsedQuantity ?? 0) > 0
                            ? null
                            : 'Nhập số lớn hơn 0',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(20),
                        ],
                        decoration: const InputDecoration(labelText: 'Đơn vị'),
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Nhập đơn vị' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(expiry == null
                      ? 'Chọn hạn dùng'
                      : 'Hạn dùng: ${formatDayMonth(expiry)}/${expiry.year}'),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error,
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.colors.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
