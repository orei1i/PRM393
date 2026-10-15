// lib/features/meal_planner/presentation/widgets/meal_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/meal_plan_controller.dart';
import '../screens/user_recipe_form_screen.dart';

/// What the member chose for a slot.
sealed class MealPick {
  const MealPick();
}

/// A recipe by id; its [Recipe.source] says which tab it came from.
class RecipePick extends MealPick {
  const RecipePick(this.recipe);

  final Recipe recipe;
}

/// "Tự nhập món": a dish name with optional kcal and macros.
class ManualPick extends MealPick {
  const ManualPick({
    required this.name,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  final String name;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
}

/// "Bỏ món": empty the slot.
class RemovePick extends MealPick {
  const RemovePick();
}

/// Fill or replace a slot from 4 sources: AI suggestions, the member's own
/// recipes, chef suggestions, or a dish typed in. Dishes with the member's
/// allergens are flagged, and choosing one asks for confirmation.
class MealPickerSheet extends ConsumerWidget {
  const MealPickerSheet({
    super.key,
    required this.slot,
    required this.allergies,
    this.current,
  });

  final MealSlot slot;
  final List<String> allergies;

  /// The dish in the slot now; `null` for an empty slot.
  final Recipe? current;

  static Future<MealPick?> show(
    BuildContext context, {
    required MealSlot slot,
    required List<String> allergies,
    Recipe? current,
  }) {
    return showModalBottomSheet<MealPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child:
            MealPickerSheet(slot: slot, allergies: allergies, current: current),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = this.current;
    final slotName = slot.label.toLowerCase();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        current == null ? 'Thêm $slotName' : 'Đổi $slotName',
                        style: context.textStyles.titleLarge),
                  ),
                  if (current != null)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(const RemovePick()),
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          size: 18),
                      label: const Text('Bỏ món'),
                    ),
                ],
              ),
            ),
            if (current != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Text('Đang có: ${current.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted)),
              ),
            const SizedBox(height: 4),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'AI gợi ý'),
                Tab(text: 'Công thức của tôi'),
                Tab(text: 'Từ chuyên gia'),
                Tab(text: 'Tự nhập món'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AiTab(slot: slot, current: current, allergies: allergies),
                  _MyRecipesTab(slot: slot, allergies: allergies),
                  _ChefTab(allergies: allergies),
                  _ManualTab(slot: slot),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pops [recipe]; asks first when it contains the member's allergens.
Future<void> _choose(
    BuildContext context, Recipe recipe, List<String> allergies) async {
  final conflicts = recipe.allergenConflicts(allergies);
  if (conflicts.isNotEmpty) {
    final names =
        conflicts.map((a) => allergenLabel(a).toLowerCase()).join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: context.vl.caution),
        title: const Text('Món có chất bạn dị ứng'),
        content: Text(
            '"${recipe.name}" chứa $names — bạn đã khai báo dị ứng với thành phần này. Vẫn thêm vào thực đơn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Chọn món khác'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vẫn thêm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  if (context.mounted) Navigator.of(context).pop(RecipePick(recipe));
}

void _openRecipe(BuildContext context, Recipe recipe) => Navigator.of(context)
    .push(RecipeDetailScreen.route(recipe.id, name: recipe.name));

// ----------------------------------------------------------------- AI --

class _AiTab extends ConsumerStatefulWidget {
  const _AiTab(
      {required this.slot, required this.current, required this.allergies});

  final MealSlot slot;
  final Recipe? current;
  final List<String> allergies;

  @override
  ConsumerState<_AiTab> createState() => _AiTabState();
}

class _AiTabState extends ConsumerState<_AiTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Recipe>> _suggestions;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _suggestions = ref
        .read(mealPlanControllerProvider.notifier)
        .fetchSwapSuggestions(widget.slot);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final current = widget.current;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          current != null && current.hasNutrition
              ? 'Cùng mức năng lượng (±10%) với "${current.name}" và an toàn với dị ứng của bạn.'
              : 'Món vừa với mục tiêu năng lượng mỗi bữa và an toàn với dị ứng của bạn.',
          style:
              context.textStyles.bodyMedium?.copyWith(color: context.vl.muted),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Recipe>>(
          future: _suggestions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _PickSkeleton();
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                error: snapshot.error!,
                onRetry: () => setState(_load),
              );
            }
            final items = snapshot.data ?? const <Recipe>[];
            if (items.isEmpty) {
              return const EmptyStateView(
                icon: Icons.search_off_rounded,
                title: 'Chưa có món thay thế phù hợp',
                message:
                    'Không tìm được món cùng mức năng lượng mà tránh được dị ứng của bạn. Thử nguồn khác hoặc tự nhập món nhé.',
              );
            }
            return Column(
              children: [
                for (final r in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PickTile(
                      recipe: r,
                      allergies: widget.allergies,
                      kcalDelta: current != null && current.hasNutrition
                          ? r.nutrition.calories - current.nutrition.calories
                          : null,
                      onTap: () => _choose(context, r, widget.allergies),
                      onView: () => _openRecipe(context, r),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- my recipes --

class _MyRecipesTab extends ConsumerStatefulWidget {
  const _MyRecipesTab({required this.slot, required this.allergies});

  final MealSlot slot;
  final List<String> allergies;

  @override
  ConsumerState<_MyRecipesTab> createState() => _MyRecipesTabState();
}

class _MyRecipesTabState extends ConsumerState<_MyRecipesTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Recipe>> _recipes;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _recipes = ref.read(mealPlanControllerProvider.notifier).fetchMyRecipes();
  }

  /// A new recipe is saved for later and goes straight into the slot.
  Future<void> _create() async {
    final created =
        await Navigator.of(context).push<Recipe>(UserRecipeFormScreen.route());
    if (created == null || !mounted) return;
    setState(_load);
    await _choose(context, created, widget.allergies);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        OutlinedButton.icon(
          onPressed: _create,
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tạo công thức mới'),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Recipe>>(
          future: _recipes,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _PickSkeleton();
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                  error: snapshot.error!, onRetry: () => setState(_load));
            }
            final items = snapshot.data ?? const <Recipe>[];
            if (items.isEmpty) {
              return const EmptyStateView(
                icon: Icons.menu_book_outlined,
                title: 'Chưa có công thức nào',
                message:
                    'Tạo công thức của riêng bạn (nguyên liệu, cách làm, kcal) để dùng lại cho các bữa sau.',
              );
            }
            return Column(
              children: [
                for (final r in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PickTile(
                      recipe: r,
                      allergies: widget.allergies,
                      onTap: () => _choose(context, r, widget.allergies),
                      onView: () => _openRecipe(context, r),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- chef --

class _ChefTab extends ConsumerStatefulWidget {
  const _ChefTab({required this.allergies});

  final List<String> allergies;

  @override
  ConsumerState<_ChefTab> createState() => _ChefTabState();
}

class _ChefTabState extends ConsumerState<_ChefTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<ChefSuggestion>> _suggestions;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _suggestions =
        ref.read(mealPlanControllerProvider.notifier).fetchChefSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<ChefSuggestion>>(
      future: _suggestions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _PickSkeleton());
        }
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: ErrorStateView(
                  error: snapshot.error!, onRetry: () => setState(_load)),
            ),
          );
        }
        final items = snapshot.data ?? const <ChefSuggestion>[];
        if (items.isEmpty) {
          return const Center(
            child: SingleChildScrollView(
              child: EmptyStateView(
                icon: Icons.verified_outlined,
                title: 'Chưa có đề xuất từ chuyên gia',
                message: 'Đăng ký gói Thực đơn VIP để nhận món đề xuất.',
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            for (final s in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PickTile(
                  recipe: s.recipe,
                  allergies: widget.allergies,
                  byline: [
                    '${s.chefName} đề xuất',
                    // With a day, the meal moves to the schedule line.
                    if (s.slot != null && s.targetDate == null)
                      'cho ${s.slot!.label.toLowerCase()}',
                  ].join(' '),
                  schedule: s.scheduleLabel,
                  note: s.note,
                  onTap: () => _choose(context, s.recipe, widget.allergies),
                  onView: () => _openRecipe(context, s.recipe),
                ),
              ),
          ],
        );
      },
    );
  }
}

// -------------------------------------------------------------- manual --

class _ManualTab extends StatefulWidget {
  const _ManualTab({required this.slot});

  final MealSlot slot;

  @override
  State<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<_ManualTab>
    with AutomaticKeepAliveClientMixin {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  /// After a refused submit, every edit re-checks the form, so a message
  /// clears as soon as its value is valid.
  bool _attempted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  String? _validateName(String? v) {
    final text = v?.trim() ?? '';
    if (text.length < 2) return 'Nhập tên món (ít nhất 2 ký tự).';
    if (text.length > 80) return 'Tên món tối đa 80 ký tự.';
    return null;
  }

  String? _validateKcal(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null || n < 50 || n > 3000) return 'Từ 50 đến 3000 kcal.';
    return null;
  }

  String? _validateGrams(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = _number(text);
    if (n == null || n < 0 || n > 300) return '0–300 g';
    return null;
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(context).pop(ManualPick(
      name: _name.text.trim(),
      calories: int.tryParse(_kcal.text.trim()),
      proteinG: _number(_protein.text),
      carbsG: _number(_carbs.text),
      fatG: _number(_fat.text),
    ));
  }

  Widget _gramsField(TextEditingController c, String label) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
        ],
        validator: _validateGrams,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Form(
      key: _form,
      autovalidateMode: _attempted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            maxLength: 80,
            validator: _validateName,
            decoration: const InputDecoration(
              labelText: 'Tên món',
              hintText: 'VD: Cơm tấm chay nhà làm',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _kcal,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: _validateKcal,
            decoration: const InputDecoration(
              labelText: 'Năng lượng (kcal)',
              helperText: 'Không bắt buộc — để trống nếu bạn chưa biết.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Đạm, tinh bột, chất béo (không bắt buộc)',
              style: context.textStyles.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (c, label) in [
                (_protein, 'Đạm (g)'),
                (_carbs, 'Tinh bột (g)'),
                (_fat, 'Béo (g)'),
              ])
                SizedBox(width: 120, child: _gramsField(c, label)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Món tự nhập vẫn được kiểm tra dị ứng theo tên món.',
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text('Thêm vào ${widget.slot.label.toLowerCase()}'),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- tiles --

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.recipe,
    required this.allergies,
    required this.onTap,
    required this.onView,
    this.kcalDelta,
    this.byline,
    this.schedule,
    this.note,
  });

  final Recipe recipe;
  final List<String> allergies;
  final VoidCallback onTap;
  final VoidCallback onView;
  final int? kcalDelta;
  final String? byline;

  /// The day (and meal) a chef suggested the dish for.
  final String? schedule;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final n = recipe.nutrition;
    final conflicts = recipe.allergenConflicts(allergies);
    final delta = kcalDelta;
    return VLCard(
      onTap: onTap,
      borderColor: conflicts.isEmpty ? null : vl.cautionBorder,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.name, style: context.textStyles.titleSmall),
                if (byline != null)
                  Text(byline!,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: vl.onSuccessContainer)),
                if (schedule != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.event_outlined, size: 14, color: vl.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(schedule!,
                              style: context.textStyles.bodySmall?.copyWith(
                                  color: context.colors.onSurface,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: recipe.hasNutrition
                          ? '${formatInt(n.calories)} kcal '
                          : 'Chưa rõ kcal ',
                      style: AppTypography.mono(
                          size: 12, color: context.colors.onSurface)),
                  if (delta != null)
                    TextSpan(
                        text: delta == 0
                            ? '(±0)'
                            : (delta > 0 ? '(+$delta)' : '($delta)'),
                        style: AppTypography.mono(
                            size: 12,
                            weight: FontWeight.w500,
                            color: vl.muted)),
                  // Unknown protein is left out, never "Đạm 0 g".
                  if (n.summary(macros: const [Macro.protein])
                      case final protein?)
                    TextSpan(
                        text: ' · $protein',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted)),
                ])),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text('“$note”',
                      style: context.textStyles.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic, color: vl.muted)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (conflicts.isEmpty)
                      VLTag(
                        label: 'An toàn dị ứng',
                        icon: Icons.verified_user_outlined,
                        background: vl.successContainer,
                        foreground: vl.onSuccessContainer,
                      )
                    else
                      for (final a in conflicts)
                        VLTag.caution(
                            context, 'Chứa ${allergenLabel(a).toLowerCase()}'),
                    for (final t in recipe.dietTags.take(2))
                      VLTag.neutral(context, dietTagLabel(t)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Xem công thức',
            onPressed: onView,
            icon: Icon(Icons.info_outline_rounded, color: vl.muted),
          ),
        ],
      ),
    );
  }
}

class _PickSkeleton extends StatelessWidget {
  const _PickSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: context.vl.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 200, height: 16),
                SizedBox(height: 8),
                SkeletonBox(width: 140, height: 12),
                SizedBox(height: 10),
                SkeletonBox(width: 100, height: 22, radius: 999),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
