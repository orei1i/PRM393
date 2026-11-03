// lib/features/recipe/presentation/widgets/substitute_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/utils/text_search.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/pantry_controller.dart';
import '../../../scanner/domain/vegan_check.dart';
import '../../domain/entities/recipe_detail.dart';
import '../../domain/recipe_customization.dart';
import '../../domain/recipe_scaling.dart';
import 'recipe_ingredient_row.dart';

/// What the cook picked in the substitute sheet: a substitute key, [custom]
/// (typed in or from the fridge), or neither for "Giữ nguyên".
class SubstituteChoice {
  const SubstituteChoice(this.substituteKey, {this.custom});

  final String? substituteKey;
  final RecipeSubstitute? custom;
}

/// "Đổi {tên}" (a "Thành phần chính": "Đổi {vai trò} — giữ đúng món"): the
/// original, every listed substitute with its amount for the servings cooked,
/// its energy change per serving and allergy tags, what is in the member's
/// fridge, and a typed-in ingredient. Listed options that avoid the member's
/// allergies come first. `null` when dismissed.
Future<SubstituteChoice?> showSubstituteSheet(
  BuildContext context, {
  required String recipeName,
  required RecipeIngredient row,
  required String? currentKey,
  RecipeSubstitute? currentCustom,
  required double factor,
  required int baseServings,
  List<String> userAllergies = const [],
}) =>
    showModalBottomSheet<SubstituteChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SubstituteSheet(
        recipeName: recipeName,
        row: row,
        currentKey: currentKey,
        currentCustom: currentCustom,
        factor: factor,
        baseServings: baseServings,
        userAllergies: userAllergies,
      ),
    );

const _keep = '';
const _manual = '__manual';
const _pantryPrefix = 'pantry:';

class _SubstituteSheet extends ConsumerStatefulWidget {
  const _SubstituteSheet({
    required this.recipeName,
    required this.row,
    required this.currentKey,
    required this.currentCustom,
    required this.factor,
    required this.baseServings,
    required this.userAllergies,
  });

  final String recipeName;
  final RecipeIngredient row;
  final String? currentKey;
  final RecipeSubstitute? currentCustom;
  final double factor;
  final int baseServings;
  final List<String> userAllergies;

  @override
  ConsumerState<_SubstituteSheet> createState() => _SubstituteSheetState();
}

class _SubstituteSheetState extends ConsumerState<_SubstituteSheet> {
  late final _custom = widget.currentCustom;
  late String _selected = switch (_custom) {
    null => widget.currentKey ?? _keep,
    final c when c.key.startsWith(_pantryPrefix) => c.key,
    _ => _manual,
  };
  late final double _portion = portionFactor(widget.factor, widget.row.role);
  late final _name =
      TextEditingController(text: _selected == _manual ? _custom?.name : null);
  late final ScaledAmount _prefill = _selected == _manual
      ? scaleAmount(_custom?.quantity, _custom?.unit ?? '', _portion)
      : scaleAmount(widget.row.quantity, widget.row.unit, _portion);
  late final _quantity = TextEditingController(
      text:
          _prefill.quantity == null ? '' : formatQuantity(_prefill.quantity!));
  late final _unit = TextEditingController(text: _prefill.unit);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  String _amount(double? q, String unit) => scaleAmount(q, unit, _portion).text;

  String _energy(RecipeSubstitute sub) {
    final d = substituteKcalDelta(widget.row, sub, widget.baseServings);
    if (d == null) return 'Chưa rõ năng lượng';
    if (d == 0) return 'Không đổi năng lượng';
    return '${d > 0 ? '+' : '−'}${formatInt(d.abs())} kcal/phần';
  }

  /// [item] at the row's amount; its kcal only when the row is weighed in grams.
  RecipeSubstitute _fromFridge(PantryItem item) {
    final row = widget.row;
    final grams = gramsOf(row.quantity, row.unit);
    final per100g = item.caloriesPer100g;
    return RecipeSubstitute(
      key: '$_pantryPrefix${item.id}',
      name: item.ingredient,
      quantity: row.quantity,
      unit: row.unit,
      ingredientId: item.ingredientId,
      note: 'Có trong tủ lạnh của bạn',
      nutrition: grams == null || per100g == null
          ? null
          : IngredientNutrition(calories: grams * per100g / 100),
    );
  }

  /// The fridge without what the row and its listed options already offer.
  List<RecipeSubstitute> _fridgeOptions(List<PantryItem> items) {
    final row = widget.row;
    final listed = {
      foldVietnamese(row.name),
      for (final s in row.substitutes) foldVietnamese(s.name),
    };
    return [
      for (final item in items)
        if (!item.serverSaysNotVegan &&
            !listed.contains(foldVietnamese(item.ingredient)))
          _fromFridge(item),
    ];
  }

  void _apply(List<RecipeSubstitute> fridge) {
    final navigator = Navigator.of(context);
    if (_selected == _keep) {
      navigator.pop(const SubstituteChoice(null));
    } else if (_selected == _manual) {
      if (_typed() case final typed?) {
        navigator.pop(SubstituteChoice(typed.key, custom: typed));
      }
    } else if (_selected.startsWith(_pantryPrefix)) {
      final picked = fridge.where((s) => s.key == _selected).firstOrNull ??
          (_custom?.key == _selected ? _custom : null);
      navigator.pop(
          picked == null ? null : SubstituteChoice(picked.key, custom: picked));
    } else {
      navigator.pop(SubstituteChoice(_selected));
    }
  }

  /// The typed ingredient at the base servings; `null` with [_error] set when
  /// it can't be used. Anything of animal origin is refused, like the fridge.
  RecipeSubstitute? _typed() {
    final name = _name.text.trim();
    final text = _quantity.text.trim().replaceAll(',', '.');
    final quantity = text.isEmpty ? null : double.tryParse(text);
    final verdict = classifyVegan(name);
    final error = name.isEmpty
        ? 'Nhập tên nguyên liệu.'
        : !verdict.isVegan
            ? '${verdict.nonVeganReason} Hãy chọn nguyên liệu thuần chay.'
            : text.isNotEmpty && (quantity == null || quantity <= 0)
                ? 'Định lượng phải lớn hơn 0.'
                : null;
    setState(() => _error = error);
    if (error != null) return null;
    return RecipeSubstitute(
      key: 'tu_nhap_${widget.row.key}',
      name: name,
      quantity: quantity == null ? null : quantity / _portion,
      unit: _unit.text.trim(),
    );
  }

  Widget _option(RecipeSubstitute sub, SubstituteAllergyInfo info) =>
      RadioListTile<String>(
        value: sub.key,
        isThreeLine: true,
        title: Text('${sub.name} · ${_amount(sub.quantity, sub.unit)}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sub.note != null) Text(sub.note!),
            Text(_energy(sub),
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
            if (info.contains.isNotEmpty ||
                info.conflicts.isNotEmpty ||
                info.avoids.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final a in {
                    ...info.contains,
                    ...info.conflicts,
                  })
                    RecipeTag(
                      'Chứa ${allergenLabel(a).toLowerCase()}',
                      icon: info.conflicts.contains(a)
                          ? Icons.warning_amber_rounded
                          : null,
                      tone: info.conflicts.contains(a)
                          ? RecipeTagTone.caution
                          : RecipeTagTone.neutral,
                    ),
                  for (final a in info.avoids)
                    RecipeTag(
                      'Tránh được dị ứng '
                      '${allergenLabel(a).toLowerCase()}',
                      icon: Icons.check_circle_outline_rounded,
                      tone: RecipeTagTone.success,
                    ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Text(text,
            style: context.textStyles.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _muted(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Text(text,
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.muted)),
      );

  Widget _typedFields() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Tên nguyên liệu'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Định lượng'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Đơn vị'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final row = widget.row;
    final role = (row.role ?? 'thành phần chính').toLowerCase();
    final options = [
      for (final s in row.substitutes)
        (s, substituteAllergyInfo(row, s, widget.userAllergies)),
    ];
    // Safe options first (stable).
    final sorted = [
      ...options.where((o) => o.$2.isSafe),
      ...options.where((o) => !o.$2.isSafe),
    ];
    final title =
        row.isSignature ? 'Đổi $role — giữ đúng món' : 'Đổi ${row.name}';
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    final pantry = isGuest ? null : ref.watch(pantryControllerProvider);
    final fridge = _fridgeOptions(pantry?.valueOrNull ?? const []);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(title,
                  style: context.textStyles.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (row.isSignature)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  '«${row.role ?? row.name}» là thành phần chính của '
                  '${widget.recipeName}. Nên đổi sang loại $role khác; nguyên '
                  'liệu khác có thể làm món đổi vị.',
                  style:
                      context.textStyles.bodyMedium?.copyWith(color: vl.muted),
                ),
              ),
            Flexible(
              child: RadioGroup<String>(
                groupValue: _selected,
                onChanged: (v) => setState(() {
                  _selected = v ?? _keep;
                  _error = null;
                }),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    RadioListTile<String>(
                      value: _keep,
                      title: Text(
                          'Giữ nguyên: ${row.name} · ${_amount(row.quantity, row.unit)}'),
                    ),
                    for (final (sub, info) in sorted) _option(sub, info),
                    _heading('Từ tủ lạnh của bạn'),
                    if (pantry == null)
                      _muted('Đăng nhập để chọn từ tủ lạnh.')
                    else if (pantry.isLoading && !pantry.hasValue)
                      _muted('Đang tải tủ lạnh…')
                    else if (pantry.hasError && !pantry.hasValue)
                      _muted('Chưa tải được tủ lạnh.')
                    else if (fridge.isEmpty)
                      _muted('Tủ lạnh chưa có nguyên liệu nào khác.')
                    else
                      for (final sub in fridge)
                        _option(
                            sub,
                            substituteAllergyInfo(
                                row, sub, widget.userAllergies)),
                    _heading('Nguyên liệu khác'),
                    const RadioListTile<String>(
                      value: _manual,
                      title: Text('Tự nhập nguyên liệu'),
                    ),
                    if (_selected == _manual) _typedFields(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: () => _apply(fridge),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('Áp dụng'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lock on a "Thành phần chính": why it can't be left out and what it
/// can be swapped for. `true` when the cook taps "Đổi {vai trò}".
Future<bool> showSignatureLockSheet(
  BuildContext context, {
  required String recipeName,
  required RecipeIngredient row,
  required String currentName,
}) async {
  final picked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final vl = context.vl;
      final role = (row.role ?? 'thành phần chính').toLowerCase();
      final options = [
        if (currentName != row.name) row.name,
        for (final s in row.substitutes)
          if (s.name != currentName) s.name,
      ];
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: vl.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Thành phần chính',
                        style: context.textStyles.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '«$currentName» tạo nên phần $role — linh hồn của '
                '$recipeName. Bỏ đi thì món không còn là $recipeName, nên '
                'không thể bỏ.',
                style: context.textStyles.bodyLarge,
              ),
              const SizedBox(height: 12),
              if (options.isNotEmpty)
                Text('Bạn có thể đổi sang: ${options.join(', ')}.',
                    style: context.textStyles.bodyMedium),
              Text('Bạn cũng có thể lấy từ tủ lạnh hoặc tự nhập.',
                  style: context.textStyles.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: Text('Đổi $role'),
              ),
            ],
          ),
        ),
      );
    },
  );
  return picked ?? false;
}
