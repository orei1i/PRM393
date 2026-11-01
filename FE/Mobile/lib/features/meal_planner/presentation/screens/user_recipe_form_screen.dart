// lib/features/meal_planner/presentation/screens/user_recipe_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../recipe/data/backend_recipe_items.dart';
import '../../../recipe/data/models/recipe_detail_model.dart';
import '../../../recipe/domain/entities/recipe_detail.dart';
import '../../../recipe/domain/recipe_customization.dart';
import '../../../recipe/presentation/widgets/recipe_ingredient_row.dart';
import '../../../recipe/presentation/widgets/substitute_sheet.dart';
import '../../data/meal_planner_api_service.dart';
import '../../data/models/meal_plan_model.dart';
import '../../domain/allergy_match.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/meal_plan_controller.dart';

/// "Tạo công thức mới": name, kcal, ingredients with quantity/unit and steps.
/// Saved to "Công thức của tôi" for reuse; pops the saved [Recipe].
///
/// With [existing] it edits that recipe. A row that came with a role and options
/// is swapped like on the recipe page ("Đổi nguyên liệu"; a "Thành phần chính"
/// stays within its role and can't be removed), which also re-estimates the
/// energy. Where the BE can't overwrite a recipe
/// ([BackendModules.myRecipeEdit]) the edit is saved as a new copy, and the form
/// says so.
class UserRecipeFormScreen extends ConsumerStatefulWidget {
  const UserRecipeFormScreen({super.key, this.existing});

  /// The recipe being edited; `null` for a new one.
  final RecipeDetail? existing;

  /// What opens the form on an own recipe.
  static String get editLabel =>
      BackendModules.myRecipeEdit ? 'Sửa công thức' : 'Sửa thành bản mới';

  /// At the top of the form when an edit can't overwrite the recipe.
  static const copyNote = 'Máy chủ chưa cho sửa công thức nên bản này sẽ được '
      'lưu thành một công thức mới. Bản cũ vẫn còn và chưa xoá được.';

  /// Under the kcal field after a swap.
  static const reestimatedNote =
      'Đã ước tính lại (≈) theo nguyên liệu mới. Bạn vẫn sửa được số này.';

  static Route<Recipe> route({RecipeDetail? existing}) =>
      MaterialPageRoute<Recipe>(
        fullscreenDialog: true,
        builder: (_) => UserRecipeFormScreen(existing: existing),
      );

  @override
  ConsumerState<UserRecipeFormScreen> createState() =>
      _UserRecipeFormScreenState();
}

/// 1000 → "1000", 0.5 → "0,5": as typed, without a thousands separator (which
/// would read back as a decimal point).
String _quantityText(double? quantity) => switch (quantity) {
      null => '',
      final q when q == q.roundToDouble() => '${q.round()}',
      final q => '$q'.replaceAll('.', ','),
    };

class _IngredientRow {
  _IngredientRow({this.original});

  factory _IngredientRow.of(RecipeIngredient row) {
    final structured = row.isSignature || row.substitutes.isNotEmpty;
    final form = _IngredientRow(original: row);
    form.structured = structured;
    form.name.text = row.name;
    form.quantity.text = _quantityText(row.quantity);
    form.unit.text = row.unit;
    form.amountOptional = row.quantity == null;
    return form;
  }

  /// The row of the recipe being edited; `null` for one added here.
  final RecipeIngredient? original;

  /// It has a role and options: picked from those, not typed.
  bool structured = false;

  /// The substitute chosen for [original].
  String? substituteKey;

  /// A text row saved without an amount needn't get one to be edited.
  bool amountOptional = false;

  final name = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController();

  bool get isSignature => structured && original!.isSignature;

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
  late final List<_IngredientRow> _ingredients;
  late final List<TextEditingController> _steps;

  /// Row keys of [_existing] taken out here.
  final _removed = <String>{};
  bool _saving = false;
  bool _reestimated = false;

  /// After a refused "Lưu", every edit re-checks the form, so a message
  /// clears as soon as its value is valid.
  bool _attempted = false;

  RecipeDetail? get _existing => widget.existing;

  /// Saving makes a new recipe instead of changing [_existing].
  bool get _savesAsCopy => _existing != null && !BackendModules.myRecipeEdit;

  @override
  void initState() {
    super.initState();
    final recipe = _existing;
    if (recipe == null) {
      _ingredients = [_IngredientRow()];
      _steps = [TextEditingController()];
      return;
    }
    _name.text = _savesAsCopy ? _copyName(recipe.name) : recipe.name;
    _kcal.text = recipe.caloriesCache?.toString() ?? '';
    _minutes.text = recipe.prepMinutes?.toString() ?? '';
    _servings.text = '${recipe.baseServings}';
    _ingredients = [for (final r in recipe.ingredients) _IngredientRow.of(r)];
    if (_ingredients.isEmpty) _ingredients.add(_IngredientRow());
    _steps = [
      for (final s in recipe.steps) TextEditingController(text: s),
      if (recipe.steps.isEmpty) TextEditingController(),
    ];
  }

  /// "Bún riêu (bản mới)": two recipes with one name can't be told apart.
  static String _copyName(String name) {
    const suffix = ' (bản mới)';
    if (name.endsWith(suffix)) return name;
    const room = 80 - suffix.length;
    return '${name.length > room ? name.substring(0, room) : name}$suffix';
  }

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

  /// [_existing] with the swaps and removals made here.
  CustomizedRecipe? get _custom {
    final recipe = _existing;
    if (recipe == null) return null;
    return CustomizedRecipe(
      recipe,
      RecipeCustomization(
        swaps: {
          for (final row in _ingredients)
            if (row.substituteKey case final key?) row.original!.key: key,
        },
        removed: _removed,
      ),
    );
  }

  void _reestimate() {
    final shown = _custom?.energy.shown;
    if (shown != null) _kcal.text = '$shown';
    _reestimated = true;
  }

  Future<void> _swap(_IngredientRow row) async {
    final original = row.original!;
    final allergies =
        ref.read(userAllergiesProvider).valueOrNull ?? const <String>[];
    final choice = await showSubstituteSheet(
      context,
      recipeName: _existing!.name,
      row: original,
      currentKey: row.substituteKey,
      factor: 1,
      baseServings: _existing!.baseServings,
      userAllergies: allergies,
    );
    if (choice == null || !mounted) return;
    setState(() => _pick(row, choice.substituteKey));
  }

  /// [key] for [row], or back to the row itself.
  void _pick(_IngredientRow row, String? key) {
    final original = row.original!;
    final sub = key == null ? null : original.substitute(key);
    row.substituteKey = sub?.key;
    row.name.text = sub?.name ?? original.name;
    row.quantity.text =
        _quantityText(sub == null ? original.quantity : sub.quantity);
    row.unit.text = sub?.unit ?? original.unit;
    _reestimate();
  }

  void _removeRow(_IngredientRow row) {
    setState(() {
      _ingredients.remove(row);
      if (row.original case final original?) {
        _removed.add(original.key);
        if (row.structured) _reestimate();
      }
    });
    _disposeLater(row.dispose);
  }

  /// What a store with roles keeps of [row]: its amount as typed, the
  /// nutrition following it.
  Map<String, Object?> _structuredRow(_IngredientRow row) {
    final original = row.original;
    final quantity = _number(row.quantity.text) ?? 0;
    final unit = row.unit.text.trim();
    if (original == null || !row.structured) {
      return {
        if (original != null) 'key': original.key,
        'name': row.name.text.trim(),
        'quantity': quantity,
        'unit': unit,
      };
    }
    final picked = switch (row.substituteKey) {
      final key? =>
        CustomizedRecipe.swappedRow(original, original.substitute(key)!),
      null => original,
    };
    final base = picked.quantity;
    final ratio =
        base != null && base > 0 && picked.unit == unit ? quantity / base : 1.0;
    final n = picked.nutrition;
    double? scale(double? v) =>
        v == null ? null : (v * ratio * 10).roundToDouble() / 10;
    return {
      ...recipeIngredientToJson(picked),
      'quantity': quantity,
      'unit': unit,
      if (n != null)
        'nutrition': nutritionToJson(IngredientNutrition(
          calories: scale(n.calories),
          proteinG: scale(n.proteinG),
          carbsG: scale(n.carbsG),
          fatG: scale(n.fatG),
          fiberG: scale(n.fiberG),
        )),
    };
  }

  CreateRecipeRequestDto _request() {
    final name = _name.text.trim();
    final recipe = _existing;
    final custom = _custom;
    final energy = custom?.energy;
    final inputs = [
      for (final row in _ingredients)
        RecipeIngredientInput(
          name: row.name.text.trim(),
          quantity: _number(row.quantity.text) ?? 0,
          unit: row.unit.text.trim(),
        ),
    ];
    final steps = [
      for (final s in _steps)
        if (s.text.trim().isNotEmpty) s.text.trim(),
    ];
    double? grams(double? v) => v?.roundToDouble();
    final origin = recipe?.basedOnName;
    return CreateRecipeRequestDto(
      name: name,
      calories: int.parse(_kcal.text.trim()),
      prepMinutes: int.tryParse(_minutes.text.trim()),
      servings: BackendModules.recipeServings
          ? int.tryParse(_servings.text.trim())
          : null,
      proteinG: grams(energy?.proteinG),
      carbsG: grams(energy?.carbsG),
      fatG: grams(energy?.fatG),
      fiberG: grams(energy?.fiberG),
      allergens: custom == null
          ? null
          : {
              ...custom.allergens,
              ...detectDishAllergens(name, inputs.map((i) => i.name)),
            }.toList(),
      ingredients: inputs,
      // The BE has nowhere else to keep where a saved variant came from.
      steps: [
        if (_savesAsCopy && recipe!.isFromBackend && origin != null)
          savedVariantNote(origin, recipe.baseServings),
        ...steps,
      ],
      structuredRows: recipe == null
          ? null
          : [for (final row in _ingredients) _structuredRow(row)],
      changeNotes: recipe == null || !recipe.isVariant
          ? null
          : [
              for (final c in [
                ...recipe.customizations,
                ...custom!.changeNotes()
              ])
                recipeChangeNoteToJson(c),
            ],
    );
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _saving = true);
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    final recipe = _existing;
    try {
      final saved = recipe != null && !_savesAsCopy
          ? await notifier.updateMyRecipe(recipe.id, _request())
          : await notifier.createMyRecipe(_request());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(recipe == null
                ? 'Đã lưu vào Công thức của tôi'
                : _savesAsCopy
                    ? 'Đã lưu thành công thức mới. Bản cũ vẫn còn.'
                    : 'Đã lưu thay đổi')));
      Navigator.of(context).pop(saved);
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
        title: Text(_existing == null
            ? 'Công thức của tôi'
            : UserRecipeFormScreen.editLabel),
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
            if (_savesAsCopy) ...[
              Text(UserRecipeFormScreen.copyNote,
                  style: context.textStyles.bodyMedium),
              const SizedBox(height: 12),
            ],
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
              decoration: InputDecoration(
                labelText: 'Năng lượng mỗi phần (kcal)',
                helperText:
                    _reestimated ? UserRecipeFormScreen.reestimatedNote : null,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
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
                // The BE has no such field: it would be dropped silently.
                if (BackendModules.recipeServings)
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
            Text(
                BackendModules.recipeServings
                    ? 'Ghi định lượng cho số phần ở trên, VD: 200 g, 2 quả.'
                    : 'Ghi định lượng cho cả công thức, VD: 200 g, 2 quả. Máy chủ chưa lưu số phần ăn.',
                style: muted),
            const SizedBox(height: 10),
            for (final (i, row) in _ingredients.indexed)
              _IngredientFields(
                key: ObjectKey(row),
                row: row,
                index: i,
                onSwap: row.structured && row.original!.substitutes.isNotEmpty
                    ? () => _swap(row)
                    : null,
                onUndoSwap: row.substituteKey == null
                    ? null
                    : () => setState(() => _pick(row, null)),
                // A "Thành phần chính" stays, as on the recipe page.
                onRemove: _ingredients.length == 1 || row.isSignature
                    ? null
                    : () => _removeRow(row),
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
    this.onSwap,
    this.onUndoSwap,
  });

  final _IngredientRow row;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback? onSwap;
  final VoidCallback? onUndoSwap;

  @override
  Widget build(BuildContext context) {
    final optional = row.amountOptional;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: row.structured
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(row.name.text,
                            style: context.textStyles.titleSmall),
                      )
                    : TextFormField(
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
          if (row.isSignature) ...[
            const SizedBox(height: 4),
            const RecipeTag('Thành phần chính', icon: Icons.star_rounded),
          ],
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
                    final text = (v ?? '').trim();
                    if (optional && text.isEmpty) return null;
                    final n = double.tryParse(text.replaceAll(',', '.'));
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
                  validator: (v) => !optional && (v?.trim().isEmpty ?? true)
                      ? 'Nhập đơn vị.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Đơn vị',
                    hintText: 'g, ml, quả…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (onSwap != null || onUndoSwap != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onSwap != null)
                  OutlinedButton.icon(
                    onPressed: onSwap,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text(RecipeIngredientRow.swapLabel),
                  ),
                if (onUndoSwap != null)
                  TextButton(
                    onPressed: onUndoSwap,
                    child: const Text('Hoàn tác'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
