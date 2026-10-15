// lib/features/meal_planner/presentation/screens/user_recipe_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../data/models/meal_plan_model.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/meal_plan_controller.dart';

/// "Tạo công thức mới": name, kcal, ingredients with quantity/unit and steps.
/// Saved to "Công thức của tôi" for reuse; pops the saved [Recipe].
class UserRecipeFormScreen extends ConsumerStatefulWidget {
  const UserRecipeFormScreen({super.key});

  static Route<Recipe> route() => MaterialPageRoute<Recipe>(
        fullscreenDialog: true,
        builder: (_) => const UserRecipeFormScreen(),
      );

  @override
  ConsumerState<UserRecipeFormScreen> createState() =>
      _UserRecipeFormScreenState();
}

class _IngredientRow {
  final name = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController();

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
  }
}

class _UserRecipeFormScreenState extends ConsumerState<UserRecipeFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _minutes = TextEditingController();
  final _servings = TextEditingController(text: '1');
  final List<_IngredientRow> _ingredients = [_IngredientRow()];
  final List<TextEditingController> _steps = [TextEditingController()];
  bool _saving = false;

  /// After a refused "Lưu", every edit re-checks the form, so a message
  /// clears as soon as its value is valid.
  bool _attempted = false;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _minutes, _servings, ..._steps]) {
      c.dispose();
    }
    for (final row in _ingredients) {
      row.dispose();
    }
    super.dispose();
  }

  /// After the frame, once the removed fields have let go of them.
  void _disposeLater(VoidCallback dispose) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => dispose());

  static double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  String? _range(String? v, int min, int max, String message,
      {bool optional = false}) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return optional ? null : message;
    final n = int.tryParse(text);
    return n == null || n < min || n > max ? message : null;
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _saving = true);
    try {
      final recipe =
          await ref.read(mealPlanControllerProvider.notifier).createMyRecipe(
                CreateRecipeRequestDto(
                  name: _name.text.trim(),
                  calories: int.parse(_kcal.text.trim()),
                  prepMinutes: int.tryParse(_minutes.text.trim()),
                  servings: int.tryParse(_servings.text.trim()),
                  ingredients: [
                    for (final row in _ingredients)
                      RecipeIngredientInput(
                        name: row.name.text.trim(),
                        quantity: _number(row.quantity.text) ?? 0,
                        unit: row.unit.text.trim(),
                      ),
                  ],
                  steps: [
                    for (final s in _steps)
                      if (s.text.trim().isNotEmpty) s.text.trim(),
                  ],
                ),
              );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Đã lưu vào Công thức của tôi')));
      Navigator.of(context).pop(recipe);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Công thức của tôi'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        autovalidateMode: _attempted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            TextFormField(
              controller: _name,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              validator: (v) => (v?.trim().length ?? 0) < 2
                  ? 'Nhập tên món (ít nhất 2 ký tự).'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Tên món',
                hintText: 'VD: Gỏi cuốn chay nhà làm',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _kcal,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) =>
                  _range(v, 50, 3000, 'Năng lượng từ 50 đến 3000 kcal.'),
              decoration: const InputDecoration(
                labelText: 'Năng lượng mỗi phần (kcal)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) =>
                        _range(v, 1, 600, '1–600 phút', optional: true),
                    decoration: const InputDecoration(
                      labelText: 'Thời gian (phút)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: _servings,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) =>
                        _range(v, 1, 20, '1–20 phần', optional: true),
                    decoration: const InputDecoration(
                      labelText: 'Số phần ăn',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Nguyên liệu', style: context.textStyles.titleMedium),
            const SizedBox(height: 4),
            Text('Ghi định lượng cho số phần ở trên, VD: 200 g, 2 quả.',
                style: muted),
            const SizedBox(height: 10),
            for (final (i, row) in _ingredients.indexed)
              _IngredientFields(
                key: ObjectKey(row),
                row: row,
                index: i,
                onRemove: _ingredients.length == 1
                    ? null
                    : () {
                        setState(() => _ingredients.remove(row));
                        _disposeLater(row.dispose);
                      },
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _ingredients.add(_IngredientRow())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Thêm nguyên liệu'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Cách làm', style: context.textStyles.titleMedium),
            const SizedBox(height: 10),
            for (final (i, step) in _steps.indexed)
              Padding(
                key: ObjectKey(step),
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: step,
                        minLines: 1,
                        maxLines: 4,
                        validator: (v) => i == 0 && (v?.trim().isEmpty ?? true)
                            ? 'Nhập ít nhất 1 bước.'
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Bước ${i + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (_steps.length > 1)
                      IconButton(
                        tooltip: 'Bỏ bước ${i + 1}',
                        onPressed: () {
                          setState(() => _steps.remove(step));
                          _disposeLater(step.dispose);
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _steps.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Thêm bước'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Công thức được lưu riêng cho bạn và kiểm tra dị ứng theo nguyên liệu.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientFields extends StatelessWidget {
  const _IngredientFields({
    super.key,
    required this.row,
    required this.index,
    required this.onRemove,
  });

  final _IngredientRow row;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.name,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Nhập tên nguyên liệu.'
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Nguyên liệu ${index + 1}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Bỏ nguyên liệu ${index + 1}',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.quantity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  validator: (v) {
                    final n =
                        double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                    return n == null || n <= 0 ? 'Nhập số lượng.' : null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Số lượng',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.unit,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Nhập đơn vị.' : null,
                  decoration: const InputDecoration(
                    labelText: 'Đơn vị',
                    hintText: 'g, ml, quả…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
