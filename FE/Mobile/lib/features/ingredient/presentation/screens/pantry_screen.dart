// lib/features/ingredient/presentation/screens/pantry_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../../meal_planner/presentation/controllers/pantry_controller.dart';
import '../../../scanner/domain/scan_mode.dart';
import '../../../scanner/domain/vegan_check.dart';
import '../../../scanner/presentation/screens/ingredient_scanner_screen.dart';
import '../../data/ingredient_api_service.dart';
import '../../domain/entities/ingredient.dart';
import '../widgets/ingredient_avatar.dart';
import '../widgets/not_vegan_notice.dart';
import 'ingredient_detail_screen.dart';

/// "Nguyên liệu trong tủ": the vegan foods the member has at home (saved
/// from a fridge scan or typed in), as a list with an illustration and the
/// energy per standard unit. Tapping a row opens its nutrition detail; a
/// swipe deletes it (with "Hoàn tác"). A typed food that isn't vegan is
/// refused with the reason and vegan swaps.
///
/// Opened from the Thực đơn card and from the scanner ("Xem tủ lạnh").
/// Pops `true` after "Tạo thực đơn từ tủ lạnh" built a new week, so the
/// caller can show the Thực đơn tab.
class PantryScreen extends ConsumerStatefulWidget {
  const PantryScreen({super.key, this.openedFromScanner = false});

  /// "Quét tủ lạnh" then just goes back to the scanner underneath.
  final bool openedFromScanner;

  static Route<bool> route({bool openedFromScanner = false}) =>
      MaterialPageRoute<bool>(
        builder: (_) => PantryScreen(openedFromScanner: openedFromScanner),
      );

  @override
  ConsumerState<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends ConsumerState<PantryScreen> {
  final _input = TextEditingController();
  bool _adding = false;
  bool _generating = false;

  /// `null` = "Tất cả".
  IngredientCategory? _category;

  /// Last typed food refused for not being vegan (shown under the field).
  ({String name, VeganVerdict verdict})? _refused;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _snack(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            // "Hoàn tác" times out like the rest (screen readers keep it).
            persist: MediaQuery.accessibleNavigationOf(context),
            content: Text(message),
            action: action));

  /// Adds the typed name, or [picked] (a "Gợi ý thay thế" chip).
  Future<void> _add([String? picked]) async {
    final name = (picked ?? _input.text).trim();
    if (name.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final verdict =
          await ref.read(pantryControllerProvider.notifier).addManual(name);
      if (!mounted) return;
      setState(() =>
          _refused = verdict.isVegan ? null : (name: name, verdict: verdict));
      if (verdict.isVegan) _input.clear();
    } catch (e) {
      if (mounted) _snack(describeError(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(PantryItem item) async {
    final notifier = ref.read(pantryControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removal = notifier.remove(item);
      _snack(
        'Đã xoá ${item.ingredient}',
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () => notifier.restore(item).catchError((Object e) {
            messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
          }),
        ),
      );
      await removal;
    } catch (e) {
      if (mounted) _snack(describeError(e));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá hết nguyên liệu?'),
        content: const Text(
            'Danh sách trong tủ sẽ trống. Thực đơn đã tạo không thay đổi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá hết'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(pantryControllerProvider.notifier).clear();
    } catch (e) {
      if (mounted) _snack(describeError(e));
    }
  }

  Future<void> _scan() async {
    if (widget.openedFromScanner) {
      Navigator.of(context).pop(false);
      return;
    }
    final exit =
        await Navigator.of(context).push(IngredientScannerScreen.route());
    if (exit == ScannerExit.openPlanner && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  /// "Tạo thực đơn từ tủ lạnh": a new AI week around the fridge, then back.
  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final planner = ref.read(mealPlanControllerProvider.notifier);
    final hasPlan =
        ref.read(mealPlanControllerProvider).valueOrNull?.plan != null;
    if (hasPlan) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tạo lại cả tuần từ tủ lạnh?'),
          content:
              const Text('Các món bạn đã chọn trong tuần sẽ được thay thế.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tạo lại'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _generating = true);
    final generated = await planner.generatePlan(fromPantry: true);
    if (!mounted) return;
    setState(() => _generating = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(generated
              ? 'Đã tạo thực đơn ưu tiên nguyên liệu trong tủ.'
              : 'Chưa tạo được thực đơn. Thử lại sau ít phút nhé.')));
    if (generated) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(pantryControllerProvider).valueOrNull ?? const <PantryItem>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nguyên liệu trong tủ'),
        actions: [
          if (items.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Tuỳ chọn',
              onSelected: (_) => _clear(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Xoá hết'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: GuestGate(
        icon: Icons.kitchen_outlined,
        title: 'Tủ lạnh của bạn',
        message:
            'Đăng nhập để lưu nguyên liệu trong tủ, xem dinh dưỡng từng món và để AI lên thực đơn từ đó.',
        benefits: const [
          'Năng lượng và dinh dưỡng của từng nguyên liệu',
          'Tạo thực đơn tuần từ những gì đang có',
        ],
        child: _body(context, items),
      ),
    );
  }

  Widget _body(BuildContext context, List<PantryItem> items) {
    final vl = context.vl;
    final async = ref.watch(pantryControllerProvider);
    final failed = async.hasError && !async.hasValue;
    final index = ref.watch(ingredientIndexProvider).valueOrNull ??
        const <IngredientSummary>[];
    final refused = _refused;
    IngredientSummary? match(PantryItem i) =>
        findIngredient(index, id: i.ingredientId, name: i.ingredient);
    IngredientCategory? categoryOf(PantryItem i) =>
        match(i)?.category ?? IngredientCategory.fromApi(i.category);
    final shown = _category == null
        ? items
        : items.where((i) => categoryOf(i) == _category).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_refused != null) setState(() => _refused = null);
                      },
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                        hintText: 'Thêm nguyên liệu…',
                        isDense: true,
                        prefixIcon: Icon(Icons.add_shopping_cart_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Thêm vào tủ',
                    onPressed: _adding ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Chỉ lưu thực phẩm thuần chay.',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
              ),
              if (refused != null) ...[
                const SizedBox(height: 8),
                NotVeganNotice(
                  name: refused.name,
                  verdict: refused.verdict,
                  onPick: _adding ? null : _add,
                ),
              ],
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in [null, ...IngredientCategory.values])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c?.label ?? 'Tất cả'),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!async.hasValue && !async.hasError)
                const _RowsSkeleton()
              else if (failed)
                Row(
                  children: [
                    Expanded(
                      child: Text('Chưa tải được danh sách trong tủ.',
                          style: context.textStyles.bodyMedium),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(pantryControllerProvider),
                      child: const Text('Thử lại'),
                    ),
                  ],
                )
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.kitchen_outlined, size: 48, color: vl.muted),
                      const SizedBox(height: 12),
                      Text(
                        'Tủ lạnh trống. Quét tủ lạnh hoặc thêm nguyên liệu.',
                        textAlign: TextAlign.center,
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: vl.muted),
                      ),
                    ],
                  ),
                )
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Chưa có nguyên liệu nào thuộc nhóm "${_category!.label}".',
                    textAlign: TextAlign.center,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: vl.muted),
                  ),
                )
              else
                for (final item in shown)
                  _PantryRow(
                    key: ValueKey('pantry-${item.id}'),
                    item: item,
                    match: match(item),
                    category: categoryOf(item),
                    onDelete: () => _remove(item),
                    onOpen: () => Navigator.of(context).push(
                        IngredientDetailScreen.route(
                            id: item.ingredientId ?? match(item)?.id,
                            name: item.ingredient)),
                  ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Vuốt sang trái để xoá. $nutritionSourceNote.',
                  textAlign: TextAlign.center,
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scan,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Quét tủ lạnh'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: items.isEmpty || _generating ? null : _generate,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: _generating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _generating
                          ? 'Đang tạo thực đơn…'
                          : 'Tạo thực đơn từ tủ lạnh',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One fridge item: illustration, name, energy per unit, where it came
/// from. Swipe left to delete.
class _PantryRow extends StatelessWidget {
  const _PantryRow({
    super.key,
    required this.item,
    required this.match,
    required this.category,
    required this.onDelete,
    required this.onOpen,
  });

  final PantryItem item;
  final IngredientSummary? match;
  final IngredientCategory? category;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  String get _energy {
    if (match case final m?) return m.energyLine;
    if (item.caloriesPer100g case final kcal?) {
      return energyLineOf(caloriesPer100g: kcal);
    }
    return 'Chưa có dữ liệu dinh dưỡng';
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Xoá ${item.ingredient}'): onDelete,
      },
      child: Dismissible(
        key: ValueKey('dismiss-${item.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
              const SizedBox(width: 6),
              Text('Xoá',
                  style: context.textStyles.labelLarge
                      ?.copyWith(color: cs.onErrorContainer)),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    IngredientAvatar(
                      name: item.ingredient,
                      ingredientId: match?.id ?? item.ingredientId,
                      category: category,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.ingredient,
                              style: context.textStyles.titleSmall),
                          const SizedBox(height: 2),
                          Text(_energy,
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted)),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: item.source.label,
                      child: Icon(
                        switch (item.source) {
                          PantrySource.scan => Icons.document_scanner_outlined,
                          PantrySource.manual => Icons.edit_outlined,
                        },
                        size: 18,
                        color: vl.muted,
                        semanticLabel: item.source.label,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: vl.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: List.generate(
          4,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SkeletonBox(height: 64, radius: 16),
          ),
        ),
      ),
    );
  }
}
