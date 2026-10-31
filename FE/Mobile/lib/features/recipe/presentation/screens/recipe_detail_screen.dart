// lib/features/recipe/presentation/screens/recipe_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/navigation/app_nav.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../ingredient/data/ingredient_api_service.dart';
import '../../../ingredient/domain/entities/ingredient.dart';
import '../../../ingredient/presentation/screens/ingredient_detail_screen.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../data/models/recipe_variant_model.dart';
import '../../domain/entities/recipe_detail.dart';
import '../../domain/entities/recipe_review.dart';
import '../../domain/recipe_customization.dart';
import '../controllers/recipe_controller.dart';
import '../controllers/recipe_customization_controller.dart';
import '../controllers/recipe_social_controllers.dart';
import '../widgets/add_to_plan_sheet.dart';
import '../widgets/recipe_energy_card.dart';
import '../widgets/recipe_ingredient_row.dart';
import '../widgets/recipe_note_card.dart';
import '../widgets/recipe_reviews_tab.dart';
import '../widgets/save_variant_dialog.dart';
import '../widgets/servings_stepper.dart';
import '../widgets/substitute_sheet.dart';

/// Recipe detail: a header (cover, kcal, macros, allergen warnings for the
/// member, "Tìm video & quán liên quan"), then two pinned tabs so the cook
/// can focus: "Nguyên liệu" and "Cách làm" (numbered method).
///
/// "Nguyên liệu" is a live preview anyone (guests too) can change: "Nấu
/// cho N người" scales the amounts; rows can be swapped ("Đổi") or left out
/// (optional rows) — a "Thành phần chính" only within its role; energy is
/// re-estimated ("≈"). Saving the changes ("Lưu thành công thức của tôi")
/// and "Thêm vào Thực đơn" ask guests to sign in, then carry on with the
/// changes kept.
///
/// Opened from a meal card ([contextDate] / [contextSlot]), the swap sheet,
/// a scanner suggestion, an ingredient and search results.
///
/// A recipe from the real BE ([RecipeDetail.isReadOnly]) has no quantities, so
/// its page only reads: no scaling, swaps, rating or note. A mock recipe in a
/// hybrid build keeps everything, under the "Dữ liệu mẫu" banner.
class RecipeDetailScreen extends ConsumerWidget {
  /// Under "Nguyên liệu" of a recipe from the real BE.
  static const readOnlyNote =
      'Công thức này chưa có định lượng chi tiết nên chưa chỉnh được số người '
      'hay đổi nguyên liệu.';

  /// Instead of the ingredients when only the meal plan knows the dish.
  static const snapshotNote = 'Món này chưa có chi tiết công thức.';

  const RecipeDetailScreen({
    super.key,
    required this.recipeId,
    this.name,
    this.contextDate,
    this.contextSlot,
  });

  final String recipeId;

  /// App-bar title while the recipe loads.
  final String? name;

  /// The planner day / meal the page was opened from: the default for
  /// "Thêm vào Thực đơn" and for the meal target comparison.
  final DateTime? contextDate;
  final MealSlot? contextSlot;

  static Route<void> route(String recipeId,
          {String? name, DateTime? contextDate, MealSlot? contextSlot}) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(name: AppRoutes.recipe(recipeId)),
        builder: (_) => RecipeDetailScreen(
          recipeId: recipeId,
          name: name,
          contextDate: contextDate,
          contextSlot: contextSlot,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeDetailProvider(recipeId));
    // A refresh keeps the loaded recipe on screen (no skeleton flash).
    final recipe = async.valueOrNull;
    final title = recipe?.name ?? name ?? 'Công thức';
    final error = async.error;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: recipe != null
          ? _withDemoBanner(
              recipe,
              _RecipeBody(
                recipe: recipe,
                contextDate: contextDate,
                contextSlot: contextSlot,
              ),
            )
          : error != null
              ? Center(
                  child: SingleChildScrollView(
                    child: error is ApiException && error.statusCode == 404
                        ? EmptyStateView(
                            icon: Icons.search_off_rounded,
                            title: 'Không tìm thấy công thức',
                            message: 'Món này có thể đã bị gỡ khỏi danh mục.',
                            actionLabel: 'Quay lại',
                            onAction: () => Navigator.of(context).maybePop(),
                          )
                        : ErrorStateView(
                            error: error,
                            onRetry: () =>
                                ref.invalidate(recipeDetailProvider(recipeId)),
                          ),
                  ),
                )
              : const _RecipeSkeleton(),
    );
  }
}

Widget _withDemoBanner(RecipeDetail recipe, Widget body) => recipe.isReadOnly
    ? body
    : DemoDataBanner.wrap(BackendModule.recipeSocial, child: body);

class _RecipeBody extends ConsumerWidget {
  const _RecipeBody({required this.recipe, this.contextDate, this.contextSlot});

  final RecipeDetail recipe;
  final DateTime? contextDate;
  final MealSlot? contextSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    final choices = ref
        .watch(recipeCustomizationProvider(recipe.id).select((s) => s.choices));
    final custom = CustomizedRecipe(recipe, choices);
    // Personal warnings only for members; guests see the plain allergen list.
    final allergies = isGuest
        ? const <String>[]
        : ref.watch(userAllergiesProvider).valueOrNull ?? const <String>[];
    final conflicts = custom.allergenConflicts(allergies);
    final others =
        custom.allergens.where((a) => !conflicts.contains(a)).toList();
    final energy = custom.energy;
    final kcal = energy.shown;

    final header = <Widget>[
      FoodCover(
        seed: recipe.id,
        imageUrl: recipe.imageUrl,
        aspectRatio: 16 / 9,
        borderRadius: BorderRadius.circular(16),
      ),
      const SizedBox(height: 16),
      Text(recipe.name,
          style: context.textStyles.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      if (recipe.createdByName != null) ...[
        const SizedBox(height: 2),
        Text('Công thức của ${recipe.createdByName}',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
      ],
      if (recipe.isVariant) ...[
        const SizedBox(height: 4),
        _VariantOrigin(recipe: recipe),
      ],
      if (recipe.isPublic && !recipe.isReadOnly) _RatingLine(recipe: recipe),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (kcal != null && (recipe.caloriesCache ?? 0) > 0)
            VLTag(
              label: energy.modified
                  ? '≈ ${formatInt(kcal)} kcal / phần'
                  : '${formatInt(kcal)} kcal / phần',
              icon: Icons.local_fire_department_outlined,
            ),
          if (recipe.isVegan)
            VLTag(
              label: 'Thuần chay',
              icon: Icons.eco_outlined,
              background: vl.successContainer,
              foreground: vl.onSuccessContainer,
            ),
          if (recipe.prepMinutes != null)
            VLTag(
                label: '${recipe.prepMinutes} phút',
                icon: Icons.schedule_rounded),
          if (recipe.servings != null)
            VLTag(
                label: '${recipe.servings} phần ăn',
                icon: Icons.people_outline_rounded),
        ],
      ),
      if (energy.proteinG != null ||
          energy.carbsG != null ||
          energy.fatG != null ||
          energy.fiberG != null) ...[
        const SizedBox(height: 14),
        _MacroRow(energy: energy),
      ],
      if (isGuest && custom.isModified) ...[
        const SizedBox(height: 14),
        VLCard(
          padding: const EdgeInsets.all(12),
          color: context.colors.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 20, color: vl.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bạn đang xem thử — đăng nhập để lưu công thức đã chỉnh '
                  'hoặc thêm vào Thực đơn.',
                  style: context.textStyles.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
      if (conflicts.isNotEmpty) ...[
        const SizedBox(height: 14),
        VLCard(
          color: vl.cautionContainer,
          borderColor: vl.cautionBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Món này có thành phần bạn đã khai báo dị ứng',
                style: context.textStyles.titleSmall
                    ?.copyWith(color: vl.onCautionContainer),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in conflicts)
                    VLTag.caution(
                        context, 'Chứa ${allergenLabel(a).toLowerCase()}'),
                ],
              ),
            ],
          ),
        ),
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          'Có chứa: ${others.map((a) => allergenLabel(a).toLowerCase()).join(', ')}',
          style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        // Never two search pages: an open one is replaced by this query.
        onPressed: () => AppNav.replaceExisting(Navigator.of(context),
            SearchScreen.route(initialQuery: recipe.name)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        icon: const Icon(Icons.travel_explore_rounded),
        label: const Text('Tìm video & quán liên quan'),
      ),
      const SizedBox(height: 8),
    ];

    // Reviews only on public catalogue recipes; member / chef recipes and
    // variants are private.
    final reviews = recipe.isPublic && !recipe.isReadOnly;
    return DefaultTabController(
      length: reviews ? 3 : 2,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverList.list(children: header),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedTabBar(
              color: Theme.of(context).scaffoldBackgroundColor,
              tabBar: TabBar(
                tabs: [
                  const Tab(text: 'Nguyên liệu'),
                  const Tab(text: 'Cách làm'),
                  if (reviews) const Tab(text: 'Đánh giá'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _IngredientsTab(
              recipe: recipe,
              custom: custom,
              contextDate: contextDate,
              contextSlot: contextSlot,
            ),
            _StepsTab(recipe: recipe),
            if (reviews) RecipeReviewsTab(recipeId: recipe.id),
          ],
        ),
      ),
    );
  }
}

/// "★ 4,6 · 5 đánh giá" / "Chưa có đánh giá" (opens "Đánh giá"). Follows
/// the reviews tab at once after the member rates; until the reviews load,
/// the figures sent with the recipe.
class _RatingLine extends ConsumerWidget {
  const _RatingLine({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(recipeReviewsProvider(recipe.id)
            .select((s) => s.valueOrNull?.summary)) ??
        RatingSummary(average: recipe.averageRating, count: recipe.ratingCount);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => DefaultTabController.of(context).animateTo(2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            summary.headline,
            style: context.textStyles.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: summary.isEmpty ? context.vl.muted : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Biến thể của «…»" (opens the original, or goes back to it when it is
/// open under this page) and what was changed.
class _VariantOrigin extends StatelessWidget {
  const _VariantOrigin({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context) {
    final original = recipe.basedOnName ?? 'công thức gốc';
    final changes = recipe.customizations.map((c) => c.label).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => AppNav.open(
              Navigator.of(context),
              RecipeDetailScreen.route(recipe.basedOnRecipeId!,
                  name: recipe.basedOnName)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text.rich(
              TextSpan(children: [
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.call_split_rounded, size: 16),
                ),
                TextSpan(text: ' Biến thể của «$original»'),
              ]),
              style: context.textStyles.bodyMedium?.copyWith(
                  color: context.colors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (changes.isNotEmpty)
          Text(changes,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
      ],
    );
  }
}

/// Keeps "Nguyên liệu" / "Cách làm" visible while the header scrolls away.
class _PinnedTabBar extends SliverPersistentHeaderDelegate {
  _PinnedTabBar({required this.tabBar, required this.color});

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: color, child: tabBar);

  @override
  bool shouldRebuild(_PinnedTabBar old) =>
      old.tabBar != tabBar || old.color != color;
}

/// "Nguyên liệu" tab: "Nấu cho N người", the ingredient table "cho N
/// phần" (rows in the nutrition DB open the ingredient; swap / leave out
/// controls), the energy card and the actions.
class _IngredientsTab extends ConsumerStatefulWidget {
  const _IngredientsTab({
    required this.recipe,
    required this.custom,
    this.contextDate,
    this.contextSlot,
  });

  final RecipeDetail recipe;
  final CustomizedRecipe custom;
  final DateTime? contextDate;
  final MealSlot? contextSlot;

  @override
  ConsumerState<_IngredientsTab> createState() => _IngredientsTabState();
}

class _IngredientsTabState extends ConsumerState<_IngredientsTab> {
  bool _adding = false;

  RecipeDetail get _recipe => widget.recipe;

  RecipeCustomizationController get _controller =>
      ref.read(recipeCustomizationProvider(_recipe.id).notifier);

  /// The member's allergies (none for guests).
  List<String> _allergies() => ref.read(sessionControllerProvider).isGuest
      ? const []
      : ref.read(userAllergiesProvider).valueOrNull ?? const [];

  Future<void> _swap(CustomizedRow row) async {
    final custom = widget.custom;
    final choice = await showSubstituteSheet(
      context,
      recipeName: _recipe.name,
      row: row.original,
      currentKey: row.substitute?.key,
      factor: custom.factor,
      baseServings: custom.baseServings,
      userAllergies: _allergies(),
    );
    if (choice == null) return;
    final key = choice.substituteKey;
    if (key == null) {
      _controller.undoSwap(row.key);
    } else {
      _controller.swap(row.original, key);
    }
  }

  Future<void> _lock(CustomizedRow row) async {
    final swap = await showSignatureLockSheet(context,
        recipeName: _recipe.name, row: row.original, currentName: row.name);
    if (swap && mounted) await _swap(row);
  }

  Future<void> _copyShoppingList() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(
        text: CustomizedRecipe(_recipe,
                ref.read(recipeCustomizationProvider(_recipe.id)).choices)
            .shoppingList()));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('Đã sao chép danh sách đi chợ')));
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final keepSnack = MediaQuery.accessibleNavigationOf(context);
    final ok = await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để lưu công thức đã tuỳ chỉnh.');
    if (!ok || !mounted) return;
    final controller = _controller;
    final saved = await showSaveVariantDialog(
      context,
      defaultName: defaultVariantName(_recipe.name),
      onSave: (name) => controller.saveVariant(_recipe, name),
    );
    if (saved == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        persist: keepSnack,
        content: const Text('Đã lưu vào Công thức của tôi'),
        action: SnackBarAction(
          label: 'Xem',
          onPressed: () => AppNav.open(
              navigator, RecipeDetailScreen.route(saved.id, name: saved.name)),
        ),
      ));
  }

  Future<void> _addToPlan() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final keepSnack = MediaQuery.accessibleNavigationOf(context);
    final ok = await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để thêm món vào Thực đơn của bạn.');
    if (!ok || !mounted) return;
    final tabs = ref.read(shellTabProvider.notifier);
    void openPlanner() {
      if (mounted) {
        AppNav.toShellTab(navigator, ref, ShellTab.planner);
      } else {
        navigator.popUntil((r) => r.isFirst);
        tabs.select(ShellTab.planner);
      }
    }

    setState(() => _adding = true);
    final MealPlannerState planner;
    try {
      planner = await ref.read(mealPlanControllerProvider.future);
    } catch (e) {
      if (mounted) setState(() => _adding = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Chưa thêm được món. ${describeError(e)}')));
      return;
    }
    if (!mounted) return;
    setState(() => _adding = false);

    final plan = planner.plan;
    if (plan == null || plan.days.isEmpty) {
      if (await showNoPlanSheet(context)) openPlanner();
      return;
    }
    final state = ref.read(recipeCustomizationProvider(_recipe.id));
    final custom = CustomizedRecipe(_recipe, state.choices);
    final targets = planner.hasHealthProfile
        ? slotTargets(planner.profile)
        : const <MealSlot, int>{};
    final today = ref.read(plannerClockProvider)();
    final date = [widget.contextDate, today]
            .nonNulls
            .map((d) => plan.dayFor(d)?.date)
            .nonNulls
            .firstOrNull ??
        plan.days.first.date;
    final picked = state.compareSlot;
    final slot = widget.contextSlot ??
        (picked != null && targets.containsKey(picked)
            ? picked
            : defaultCompareSlot(targets, custom.energy.original)) ??
        planner.pattern.first;
    if (!mounted) return;
    final choice = await showAddToPlanSheet(
      context,
      plan: plan,
      pattern: planner.pattern,
      targets: targets,
      custom: custom,
      initialDate: date,
      initialSlot: slot,
      allergyConflicts: custom.allergenConflicts(planner.profile.allergies),
    );
    if (choice == null || !mounted) return;

    setState(() => _adding = true);
    try {
      final placed = await _controller.addToPlan(_recipe,
          date: choice.date, slot: choice.slot);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          persist: keepSnack,
          content: Text('Đã thêm «${placed.recipe.name}» vào '
              '${placed.slot.label.toLowerCase()}, '
              '${formatLongDate(placed.date)}.'),
          action: SnackBarAction(label: 'Xem Thực đơn', onPressed: openPlanner),
        ));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('Chưa thêm được món. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final recipe = _recipe;
    final custom = widget.custom;
    final index = ref.watch(ingredientIndexProvider).valueOrNull ??
        const <IngredientSummary>[];
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    final allergies = isGuest
        ? const <String>[]
        : ref.watch(userAllergiesProvider).valueOrNull ?? const <String>[];
    final controller = _controller;

    return ListView(
      key: const PageStorageKey('recipe-ingredients'),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (recipe.isReadOnly)
          Text(
              recipe.isSnapshot
                  ? RecipeDetailScreen.snapshotNote
                  : RecipeDetailScreen.readOnlyNote,
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted))
        else ...[
          ServingsStepper(
            servings: custom.servings,
            baseServings: custom.baseServings,
            onChanged: (n) =>
                controller.setServings(n, base: custom.baseServings),
          ),
          const SizedBox(height: 8),
          Text('cho ${custom.servings} phần',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
          if (recipe.servings == null)
            Text('Công thức chưa ghi số phần — tính theo 1 phần',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
        ],
        if (custom.isModified)
          Row(
            children: [
              Expanded(
                child: Text(
                    'Đã chỉnh ${custom.choices.changeCount} nguyên liệu',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: controller.resetIngredients,
                child: const Text('Đặt lại'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (recipe.isSnapshot)
          const SizedBox.shrink()
        else if (recipe.ingredients.isEmpty)
          Text('Chưa có danh sách nguyên liệu.',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted))
        else
          VLCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, row) in custom.rows.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _row(row, index, allergies),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        RecipeEnergyCard(custom: custom, contextSlot: widget.contextSlot),
        const SizedBox(height: 16),
        if (!recipe.isSnapshot)
          OutlinedButton.icon(
            onPressed: _copyShoppingList,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.content_copy_rounded),
            label: const Text('Sao chép danh sách đi chợ'),
          ),
        if (recipe.isCustomizable && !recipe.isReadOnly) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: custom.isModified ? _save : null,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Lưu thành công thức của tôi'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _adding ? null : _addToPlan,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.event_available_rounded),
          label: Text(_adding ? 'Đang thêm…' : 'Thêm vào Thực đơn'),
        ),
        const SizedBox(height: 12),
        Text(
          'Chạm nguyên liệu có dấu › để xem dinh dưỡng. Định lượng mang tính tham khảo, không thay thế tư vấn y tế.',
          textAlign: TextAlign.center,
          style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
        ),
      ],
    );
  }

  Widget _row(CustomizedRow row, List<IngredientSummary> index,
      List<String> allergies) {
    final match = row.removed
        ? null
        : findIngredient(index, id: row.ingredientId, name: row.name);
    final original = row.original;
    return RecipeIngredientRow(
      row: row,
      conflicts: CustomizedRecipe.rowConflicts(row, allergies),
      onOpen: match == null
          ? null
          // Back to that ingredient if it is open under this page.
          : () => AppNav.open(Navigator.of(context),
              IngredientDetailScreen.route(id: match.id, name: row.name)),
      onSwap: () => _swap(row),
      onUndoSwap: () => _controller.undoSwap(row.key),
      onRemove: () => _controller.remove(original),
      onRestore: () => _controller.restore(row.key),
      onLock: () => _lock(row),
    );
  }
}

/// "Cách làm" tab: the member's private note, then the numbered method.
class _StepsTab extends StatelessWidget {
  const _StepsTab({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final steps = recipe.steps;
    return ListView(
      key: const PageStorageKey('recipe-steps'),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (!recipe.isReadOnly) ...[
          RecipeNoteCard(recipeId: recipe.id),
          const SizedBox(height: 16),
        ],
        if (steps.isEmpty)
          Text('Chưa có hướng dẫn chi tiết.',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted))
        else
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: context.textStyles.labelLarge?.copyWith(
                            color: context.colors.onSecondaryContainer,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(step,
                        style: context.textStyles.bodyLarge
                            ?.copyWith(height: 1.45)),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        Text(
          'Định lượng mang tính tham khảo, không thay thế tư vấn y tế.',
          textAlign: TextAlign.center,
          style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
        ),
      ],
    );
  }
}

/// Macros per serving; "≈" once the ingredients changed.
class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.energy});

  final RecipeEnergy energy;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final approx = energy.modified ? '≈ ' : '';
    final items = [
      ('Đạm', energy.proteinG, vl.macroProtein),
      ('Tinh bột', energy.carbsG, vl.macroCarbs),
      ('Béo', energy.fatG, vl.macroFat),
      ('Chất xơ', energy.fiberG, vl.macroFiber),
    ].where((m) => m.$2 != null).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, grams, color) in items)
          Container(
            constraints: const BoxConstraints(minWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: vl.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(label,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted)),
                  ],
                ),
                Text('$approx${grams!.round()} g',
                    style: AppTypography.mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: context.colors.onSurface)),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecipeSkeleton extends StatelessWidget {
  const _RecipeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
                aspectRatio: 16 / 9,
                child: SkeletonBox(height: double.infinity, radius: 16)),
            SizedBox(height: 16),
            SkeletonBox(width: 240, height: 22),
            SizedBox(height: 12),
            SkeletonBox(width: 180, height: 24, radius: 999),
            SizedBox(height: 24),
            SkeletonBox(width: 120, height: 18),
            SizedBox(height: 10),
            SkeletonBox(height: 140, radius: 16),
            SizedBox(height: 24),
            SkeletonBox(width: 100, height: 18),
            SizedBox(height: 10),
            SkeletonBox(height: 14),
            SizedBox(height: 8),
            SkeletonBox(height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 220, height: 14),
          ],
        ),
      ),
    );
  }
}
