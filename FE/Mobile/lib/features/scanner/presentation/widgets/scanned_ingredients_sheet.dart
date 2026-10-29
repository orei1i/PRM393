// lib/features/scanner/presentation/widgets/scanned_ingredients_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../ingredient/presentation/screens/pantry_screen.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../../meal_planner/presentation/controllers/pantry_controller.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../domain/entities/detected_ingredient.dart';
import '../../domain/scan_mode.dart';
import '../controllers/scanner_controller.dart';
import 'add_to_plan_sheet.dart';
import 'bounding_box_overlay.dart';
import 'confirm_ingredient_sheet.dart';
import 'dashed_border.dart';

/// Draggable tray over the camera. Confirm-only: each detected food shows
/// its name, whether it is vegan ("Thuần chay" / "Không thuần chay") and the
/// model's confidence, and can only be confirmed (low-confidence ones) or
/// removed, never given an amount. Non-vegan foods sit apart under "Không
/// thuần chay — không lưu" with the reason and "Gợi ý thay thế" (a tap adds
/// the swap as a vegan item). The primary CTA "Lưu vào tủ lạnh" keeps only
/// the confirmed vegan items in "Nguyên liệu trong tủ", then offers "Tạo
/// thực đơn từ tủ lạnh" / "Xem tủ lạnh" (the fridge list with nutrition).
/// AI dish ideas from the same vegan items stay available below; once one
/// is added to today's plan its button reads "Xem thực đơn" (leaves the
/// scanner for the Thực đơn tab).
class ScannedIngredientsSheet extends ConsumerStatefulWidget {
  const ScannedIngredientsSheet({
    super.key,
    required this.onRescan,
    this.reservedTop = 0,
    this.onOpenPlanner,
  });

  final VoidCallback onRescan;

  /// Height kept free at the top when the tray is dragged fully open, so the
  /// scanner's top bar ("Đóng", torch) stays visible and tappable.
  final double reservedTop;

  /// Leave the scanner for the Thực đơn tab (after "Tạo thực đơn từ tủ
  /// lạnh"). Defaults to closing the scanner route with
  /// [ScannerExit.openPlanner].
  final VoidCallback? onOpenPlanner;

  /// Opens the low-confidence confirmation and applies the decision.
  static Future<void> reviewItem(
      BuildContext context, WidgetRef ref, DetectedIngredient item) async {
    final decision = await ConfirmIngredientSheet.show(context, item);
    final notifier = ref.read(scannerControllerProvider.notifier);
    switch (decision) {
      case ConfirmAs(:final name):
        notifier.confirm(item.id, name: name);
      case RemoveIngredient():
        notifier.remove(item.id);
      case null:
        break;
    }
  }

  @override
  ConsumerState<ScannedIngredientsSheet> createState() =>
      _ScannedIngredientsSheetState();
}

class _ScannedIngredientsSheetState
    extends ConsumerState<ScannedIngredientsSheet> {
  final _addController = TextEditingController();

  /// Suggestion being added to the meal plan (its button shows progress).
  String? _addingId;

  /// Suggestions already added: their button becomes "Xem thực đơn".
  final _addedIds = <String>{};

  bool _savingPantry = false;
  bool _generatingPlan = false;

  /// Confirmed names at the last successful save: the follow-up actions
  /// show while the tray still matches it.
  String? _savedSignature;
  int _savedCount = 0;

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  static String _signature(List<DetectedIngredient> items) =>
      (items.map((i) => i.name.toLowerCase()).toList()..sort()).join('|');

  /// A typed food that isn't vegan lands under "Không thuần chay — không
  /// lưu", right above the field, with its reason and swaps.
  void _add() {
    ref.read(scannerControllerProvider.notifier).addManual(_addController.text);
    _addController.clear();
  }

  /// "Gợi ý thay thế" chip: adds the vegan swap as a manual item.
  void _addAlternative(String name) {
    final added = ref.read(scannerControllerProvider.notifier).addManual(name);
    if (added != null) HapticFeedback.selectionClick();
  }

  void _remove(DetectedIngredient item) {
    final removed =
        ref.read(scannerControllerProvider.notifier).remove(item.id);
    if (removed == null) return;
    final (removedItem, index) = removed;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        persist: MediaQuery.accessibleNavigationOf(context),
        content: Text('Đã bỏ ${removedItem.name.toLowerCase()}'),
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () => ref
              .read(scannerControllerProvider.notifier)
              .restore(removedItem, index),
        ),
      ));
  }

  /// "Thêm vào thực đơn": pick today's slot, then add through the planner.
  Future<void> _addToPlan(MenuSuggestion m) async {
    final slot = await AddToPlanSheet.show(context, m);
    if (slot == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final keepSnack = MediaQuery.accessibleNavigationOf(context);
    final planner = ref.read(mealPlanControllerProvider.notifier);
    setState(() => _addingId = m.id);
    try {
      final added = await planner.addMealToToday(
        slot: slot,
        name: m.name,
        calories: m.calories,
        prepMinutes: m.prepMinutes,
        ingredients: [...m.usedIngredients, ...m.missingIngredients],
        allergens: m.allergens,
        sourceId: m.id,
      );
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _addedIds.add(m.id));
      final warning = added.allergenConflicts.isEmpty
          ? ''
          : ' Lưu ý: món có thể chứa '
              '${added.allergenConflicts.map(allergenLabel).join(', ').toLowerCase()}.';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          persist: keepSnack,
          content: Text(
              'Đã thêm "${m.name}" vào ${slot.label.toLowerCase()} hôm nay.$warning'),
          action: added.replaced == null
              ? null
              : SnackBarAction(
                  label: 'Hoàn tác',
                  onPressed: () {
                    planner.undoAddMeal(added).then((_) {
                      if (mounted) setState(() => _addedIds.remove(m.id));
                    }).catchError((Object e) {
                      messenger.showSnackBar(
                          SnackBar(content: Text(describeError(e))));
                    });
                  },
                ),
        ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Chưa thêm được vào thực đơn. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  /// "Lưu vào tủ lạnh": keeps the confirmed vegan items (names only, no
  /// amounts) in "Nguyên liệu trong tủ".
  Future<void> _saveToPantry(List<DetectedIngredient> items) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingPantry = true);
    try {
      final saved =
          await ref.read(pantryControllerProvider.notifier).addFromScan([
        for (final i in items)
          if (i.savable)
            ScannedPantryItem(
              name: i.name,
              isVegan: i.isVegan,
              // "Thêm thủ công" in the tray → "Tự thêm" in the fridge.
              source: i.manual ? PantrySource.manual : PantrySource.scan,
            ),
      ]);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      setState(() {
        _savedSignature = _signature(items);
        _savedCount = saved;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Chưa lưu được vào tủ lạnh. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _savingPantry = false);
    }
  }

  void _openPlanner() {
    final open = widget.onOpenPlanner;
    if (open != null) return open();
    Navigator.of(context).pop(ScannerExit.openPlanner);
  }

  /// "Xem tủ lạnh": the fridge list over the scanner. A week generated there
  /// leaves the scanner for the Thực đơn tab.
  Future<void> _openPantry() async {
    final generated = await Navigator.of(context)
        .push(PantryScreen.route(openedFromScanner: true));
    if (generated == true && mounted) _openPlanner();
  }

  /// "Tạo thực đơn từ tủ lạnh": a new AI week built around the (vegan)
  /// fridge, then the Thực đơn tab. Asks first when it would replace a week
  /// the member already has, like the planner does.
  Future<void> _generateFromPantry() async {
    final messenger = ScaffoldMessenger.of(context);
    final planner = ref.read(mealPlanControllerProvider.notifier);
    final current = ref.read(mealPlanControllerProvider).valueOrNull;
    if (current?.plan != null) {
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
    setState(() => _generatingPlan = true);
    final generated = await planner.generatePlan(fromPantry: true);
    if (!mounted) return;
    setState(() => _generatingPlan = false);
    if (!generated) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Chưa tạo được thực đơn. Thử lại sau ít phút nhé.')));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Đã tạo thực đơn ưu tiên nguyên liệu trong tủ.')));
    _openPlanner();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final notifier = ref.read(scannerControllerProvider.notifier);
    final vl = context.vl;
    final cs = context.colors;
    final savableItems = state.savableItems;
    final savable = savableItems.length;
    final veganItems = state.veganItems;
    final nonVeganItems = state.nonVeganItems;
    // Everything found is non-vegan: nothing can go into the fridge.
    final nothingToSave = state.items.isNotEmpty && veganItems.isEmpty;
    final generating = state.menuStatus == MenuStatus.generating;
    final saved = _savedSignature != null &&
        savable > 0 &&
        _savedSignature == _signature(savableItems);
    final saveNotes = [
      if (state.pendingCount > 0)
        'Nguyên liệu chưa xác nhận sẽ không được lưu.',
      if (nonVeganItems.isNotEmpty)
        'Thực phẩm không thuần chay sẽ không được lưu.',
    ];
    bool inTray(String name) => state.items
        .any((i) => i.name.trim().toLowerCase() == name.trim().toLowerCase());

    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      final maxSize = height <= 0
          ? 0.92
          : ((height - widget.reservedTop) / height).clamp(0.5, 0.92);
      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.24,
        maxChildSize: maxSize,
        snap: true,
        snapSizes: const [0.5],
        builder: (context, scrollController) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 32,
                    offset: Offset(0, -8))
              ],
            ),
            // The list ends above the gesture bar; the keyboard is handled
            // by the scanner Scaffold resizing its body.
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                          color: cs.outline,
                          borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nguyên liệu trong tủ',
                                style: context.textStyles.titleMedium),
                            Text(
                              state.items.isEmpty
                                  ? 'Chưa có nguyên liệu nào'
                                  : '${state.items.any((i) => !i.manual) ? 'Tìm thấy ' : ''}'
                                      '${state.summary}'
                                      '${state.pendingCount > 0 ? ' · ${state.pendingCount} cần xác nhận' : ''}',
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: state.isBusy ? null : widget.onRescan,
                        icon: const Icon(Icons.center_focus_strong_outlined,
                            size: 18),
                        label: const Text('Quét lại'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final item in veganItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _IngredientTile(
                        item: item,
                        onReview: () => ScannedIngredientsSheet.reviewItem(
                            context, ref, item),
                        onRemove: () => _remove(item),
                      ),
                    ),
                  if (nonVeganItems.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const _NonVeganHeader(),
                    const SizedBox(height: 8),
                    for (final item in nonVeganItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _IngredientTile(
                          item: item,
                          onReview: () => ScannedIngredientsSheet.reviewItem(
                              context, ref, item),
                          onRemove: () => _remove(item),
                          onPickAlternative: _addAlternative,
                          inTray: inTray,
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(
                            labelText: 'Thêm nguyên liệu',
                            hintText: 'Ví dụ: nấm rơm',
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Thêm',
                        onPressed: _add,
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (saved)
                    _SavedPanel(
                      count: _savedCount,
                      generating: _generatingPlan,
                      onGenerate: _generateFromPantry,
                      onOpenPantry: _openPantry,
                    )
                  else if (nothingToSave)
                    const _NothingToSave()
                  else ...[
                    FilledButton.icon(
                      onPressed: savable == 0 || _savingPantry
                          ? null
                          : () => _saveToPantry(savableItems),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54)),
                      icon: _savingPantry
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.onPrimary),
                            )
                          : const Icon(Icons.kitchen_outlined),
                      label: Text(_savingPantry
                          ? 'Đang lưu…'
                          : 'Lưu vào tủ lạnh${savable > 0 ? ' ($savable)' : ''}'),
                    ),
                    if (saveNotes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        saveNotes.join('\n'),
                        textAlign: TextAlign.center,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  switch (ref.watch(userAllergiesProvider)) {
                    AsyncData(:final value) when value.isNotEmpty => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Gợi ý món sẽ loại trừ: ${value.map(allergenLabel).join(', ')}',
                                style: context.textStyles.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    _ => const SizedBox.shrink(),
                  },
                  OutlinedButton.icon(
                    onPressed: generating
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            notifier.generateMenu();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: vl.ai,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: generating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      generating
                          ? 'Đang gợi ý món…'
                          : 'Gợi ý món từ nguyên liệu này${savable > 0 ? ' ($savable)' : ''}',
                    ),
                  ),
                  if (state.menuError != null) ...[
                    const SizedBox(height: 8),
                    Text(state.menuError!,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.onCautionContainer)),
                  ],
                  const SizedBox(height: 16),
                  if (generating) const _MenuSkeleton(),
                  if (state.menuStatus == MenuStatus.ready) ...[
                    Row(
                      children: [
                        Text('Gợi ý từ AI',
                            style: context.textStyles.titleSmall),
                        const SizedBox(width: 8),
                        const AiBadge(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (state.menu.isEmpty)
                      Text(
                        'Chưa ghép được món nào từ các nguyên liệu này. Thêm 1–2 nguyên liệu rồi thử lại nhé.',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: vl.muted),
                      ),
                    for (final m in state.menu)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _MenuTile(
                          suggestion: m,
                          adding: _addingId == m.id,
                          added: _addedIds.contains(m.id),
                          onAdd: _addingId == null ? () => _addToPlan(m) : null,
                          onOpenPlanner: _openPlanner,
                          onView: () => Navigator.of(context).push(
                              RecipeDetailScreen.route(m.id, name: m.name)),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

/// After "Lưu vào tủ lạnh": what to do with the fridge next.
class _SavedPanel extends StatelessWidget {
  const _SavedPanel({
    required this.count,
    required this.generating,
    required this.onGenerate,
    required this.onOpenPantry,
  });

  final int count;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onOpenPantry;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: vl.successContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded,
                    color: vl.onSuccessContainer, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Đã lưu $count nguyên liệu vào tủ lạnh',
                          style: context.textStyles.titleSmall?.copyWith(
                              color: vl.onSuccessContainer,
                              fontWeight: FontWeight.w700)),
                      Text(
                        'Xem dinh dưỡng từng nguyên liệu và sửa danh sách trong "Nguyên liệu trong tủ".',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.onSuccessContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: generating ? null : onGenerate,
              style: FilledButton.styleFrom(
                backgroundColor: cs.tertiary,
                foregroundColor: cs.onTertiary,
                minimumSize: const Size.fromHeight(50),
              ),
              icon: generating
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onTertiary),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(generating
                  ? 'Đang tạo thực đơn…'
                  : 'Tạo thực đơn từ tủ lạnh'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: generating ? null : onOpenPantry,
              style: OutlinedButton.styleFrom(
                  backgroundColor: cs.surface,
                  minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.kitchen_outlined),
              label: const Text('Xem tủ lạnh'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Không thuần chay — không lưu": heads the non-vegan foods.
class _NonVeganHeader extends StatelessWidget {
  const _NonVeganHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Row(
            children: [
              Icon(Icons.block_rounded, size: 18, color: context.colors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Không thuần chay — không lưu',
                    style: context.textStyles.titleSmall),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Có nguồn gốc động vật nên không được lưu vào tủ. Chạm gợi ý thay thế để thêm món thuần chay.',
          style:
              context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
        ),
      ],
    );
  }
}

/// Every food found is non-vegan: nothing can be saved.
class _NothingToSave extends StatelessWidget {
  const _NothingToSave();

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.no_food_outlined, color: vl.muted, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chưa có thực phẩm thuần chay để lưu',
                      style: context.textStyles.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Tủ lạnh chỉ lưu thực phẩm thuần chay. Chọn gợi ý thay thế, thêm nguyên liệu khác hoặc quét lại.',
                    style:
                        context.textStyles.bodySmall?.copyWith(color: vl.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name, vegan badge and confidence; confirm (low confidence) or remove. No
/// amounts: the fridge only records what is there. A non-vegan item also
/// shows why and its vegan swaps ([onPickAlternative]).
class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.item,
    required this.onReview,
    required this.onRemove,
    this.onPickAlternative,
    this.inTray,
  });

  final DetectedIngredient item;
  final VoidCallback onReview;
  final VoidCallback onRemove;

  /// Tapped "Gợi ý thay thế" chip (non-vegan items).
  final ValueChanged<String>? onPickAlternative;

  /// Whether a swap is already in the tray (its chip then shows as added).
  final bool Function(String name)? inTray;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    final pending = !item.confirmed;
    final nonVegan = !item.isVegan;
    final detailStyle = context.textStyles.bodySmall?.copyWith(
      color: pending ? vl.onCautionContainer : vl.muted,
      fontWeight: pending ? FontWeight.w700 : FontWeight.w500,
    );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 4, nonVegan ? 10 : 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: pending
                        ? Colors.transparent
                        : (nonVegan ? cs.error : vl.success),
                    border: pending
                        ? Border.all(color: vl.caution, width: 2)
                        : null,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pending ? '${item.name}?' : item.name,
                          style: context.textStyles.titleSmall),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          VeganBadge(isVegan: item.isVegan, onDark: false),
                          Text.rich(
                            TextSpan(children: [
                              if (pending)
                                TextSpan(
                                    text: 'Chưa chắc chắn · ',
                                    style: detailStyle),
                              if (item.manual)
                                TextSpan(
                                    text: 'Thêm thủ công', style: detailStyle)
                              // Once the user confirmed it, the model score
                              // is moot.
                              else if (item.userVerified)
                                TextSpan(
                                  text: 'Đã xác nhận',
                                  style: context.textStyles.bodySmall?.copyWith(
                                    color: vl.onSuccessContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                TextSpan(
                                  text: '${(item.confidence * 100).round()}%',
                                  style: AppTypography.mono(
                                      size: 11,
                                      color: pending
                                          ? vl.onCautionContainer
                                          : vl.muted),
                                ),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (pending)
                  TextButton(
                    onPressed: onReview,
                    style: TextButton.styleFrom(
                        foregroundColor: vl.onCautionContainer,
                        minimumSize: const Size(48, 40)),
                    child: const Text('Xác nhận'),
                  ),
                if (nonVegan)
                  Tooltip(
                    message: 'Bỏ ${item.name.toLowerCase()}',
                    child: TextButton(
                      onPressed: onRemove,
                      style: TextButton.styleFrom(
                          foregroundColor: vl.muted,
                          minimumSize: const Size(48, 40)),
                      child: const Text('Bỏ'),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Bỏ ${item.name.toLowerCase()}',
                    onPressed: onRemove,
                    icon: Icon(Icons.close_rounded, size: 18, color: vl.muted),
                  ),
              ],
            ),
            if (nonVegan) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.veganVerdict.nonVeganReason ?? '',
                        style: context.textStyles.bodySmall),
                    if (item.veganAlternatives.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Gợi ý thay thế:',
                              style: context.textStyles.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          for (final alternative in item.veganAlternatives)
                            _AlternativeChip(
                              name: alternative,
                              added: inTray?.call(alternative) ?? false,
                              onPressed: onPickAlternative == null
                                  ? null
                                  : () => onPickAlternative!(alternative),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (pending) {
      return DashedBorder(
        color: vl.caution,
        radius: 12,
        child: Material(
          color: vl.cautionContainer,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onReview,
              child: content),
        ),
      );
    }
    return Material(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

/// A vegan swap ("Đậu hũ non" for eggs); once in the tray it shows as added.
class _AlternativeChip extends StatelessWidget {
  const _AlternativeChip(
      {required this.name, required this.added, required this.onPressed});

  final String name;
  final bool added;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(added ? Icons.check_rounded : Icons.add_rounded, size: 16),
      label: Text(name),
      tooltip: added
          ? 'Đã thêm ${name.toLowerCase()}'
          : 'Thêm ${name.toLowerCase()}',
      onPressed: added ? null : onPressed,
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(
      {required this.suggestion,
      required this.adding,
      required this.added,
      required this.onAdd,
      required this.onOpenPlanner,
      required this.onView});

  final MenuSuggestion suggestion;
  final bool adding;

  /// Already in today's plan: "Xem thực đơn" ([onOpenPlanner]) instead of
  /// "Thêm vào thực đơn" ([onAdd]).
  final bool added;
  final VoidCallback? onAdd;
  final VoidCallback onOpenPlanner;

  /// "Xem công thức": ingredients and steps.
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return VLCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(suggestion.name,
                      style: context.textStyles.titleSmall)),
              Text('${formatInt(suggestion.calories)} kcal',
                  style: AppTypography.mono(size: 12, color: vl.muted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dùng: ${suggestion.usedIngredients.join(', ')} · ${suggestion.prepMinutes} phút',
            style: context.textStyles.bodySmall,
          ),
          if (suggestion.missingIngredients.isNotEmpty)
            Text(
              'Cần thêm: ${suggestion.missingIngredients.join(', ')}',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Xem công thức'),
                ),
                if (added && !adding)
                  TextButton.icon(
                    onPressed: onOpenPlanner,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: const Text('Xem thực đơn'),
                  )
                else
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: adding
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.playlist_add_rounded, size: 18),
                    label: Text(adding ? 'Đang thêm…' : 'Thêm vào thực đơn'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 120, height: 16),
          const SizedBox(height: 10),
          for (var i = 0; i < 3; i++) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: context.vl.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 220, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 160, height: 12),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
