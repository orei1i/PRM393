// lib/features/recipe/presentation/widgets/substitute_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../domain/entities/recipe_detail.dart';
import '../../domain/recipe_customization.dart';
import '../../domain/recipe_scaling.dart';
import 'recipe_ingredient_row.dart';

/// What the cook picked in the substitute sheet: a substitute key, or
/// `null` for "Giữ nguyên".
class SubstituteChoice {
  const SubstituteChoice(this.substituteKey);

  final String? substituteKey;
}

/// "Đổi {tên}" (a "Thành phần chính": "Đổi {vai trò} — giữ đúng món"): the
/// original and every listed substitute with its amount for the servings
/// cooked, its energy change per serving and allergy tags. Options that
/// avoid the member's allergies come first. `null` when dismissed.
Future<SubstituteChoice?> showSubstituteSheet(
  BuildContext context, {
  required String recipeName,
  required RecipeIngredient row,
  required String? currentKey,
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
        factor: factor,
        baseServings: baseServings,
        userAllergies: userAllergies,
      ),
    );

const _keep = '';

class _SubstituteSheet extends StatefulWidget {
  const _SubstituteSheet({
    required this.recipeName,
    required this.row,
    required this.currentKey,
    required this.factor,
    required this.baseServings,
    required this.userAllergies,
  });

  final String recipeName;
  final RecipeIngredient row;
  final String? currentKey;
  final double factor;
  final int baseServings;
  final List<String> userAllergies;

  @override
  State<_SubstituteSheet> createState() => _SubstituteSheetState();
}

class _SubstituteSheetState extends State<_SubstituteSheet> {
  late String _selected = widget.currentKey ?? _keep;

  String _amount(double? q, String unit) =>
      scaleAmount(q, unit, widget.factor).text;

  String _energy(RecipeSubstitute sub) {
    final d = substituteKcalDelta(widget.row, sub, widget.baseServings);
    if (d == null) return 'Chưa rõ năng lượng';
    if (d == 0) return 'Không đổi năng lượng';
    return '${d > 0 ? '+' : '−'}${formatInt(d.abs())} kcal/phần';
  }

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

    return SafeArea(
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
                '${widget.recipeName} nên chỉ đổi được sang loại $role khác.',
                style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
              ),
            ),
          Flexible(
            child: RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v ?? _keep),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  RadioListTile<String>(
                    value: _keep,
                    title: Text(
                        'Giữ nguyên: ${row.name} · ${_amount(row.quantity, row.unit)}'),
                  ),
                  for (final (sub, info) in sorted)
                    RadioListTile<String>(
                      value: sub.key,
                      isThreeLine: true,
                      title: Text(
                          '${sub.name} · ${_amount(sub.quantity, sub.unit)}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sub.note != null) Text(sub.note!),
                          Text(_energy(sub),
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted)),
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
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop(SubstituteChoice(_selected == _keep ? null : _selected)),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Áp dụng'),
            ),
          ),
        ],
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
              if (options.isNotEmpty) ...[
                Text('Bạn có thể đổi sang: ${options.join(', ')}.',
                    style: context.textStyles.bodyMedium),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: Text('Đổi $role'),
                ),
              ] else ...[
                Text('Chưa có lựa chọn thay thế cho thành phần này.',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: vl.muted)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: const Text('Đã hiểu'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  return picked ?? false;
}
