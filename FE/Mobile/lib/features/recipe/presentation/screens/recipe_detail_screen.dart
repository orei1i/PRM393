// lib/features/recipe/presentation/screens/recipe_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../ingredient/data/ingredient_api_service.dart';
import '../../../ingredient/domain/entities/ingredient.dart';
import '../../../ingredient/presentation/screens/ingredient_detail_screen.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../domain/entities/recipe_detail.dart';
import '../controllers/recipe_controller.dart';

/// Recipe detail: a header (cover, kcal, macros, allergen warnings for the
/// member, "Tìm video & quán liên quan"), then two pinned tabs so the cook
/// can focus: "Nguyên liệu" (rows with quantity/unit; rows in the nutrition
/// DB open the ingredient) and "Cách làm" (numbered method). Opened from a
/// meal card, the swap sheet, a scanner suggestion, an ingredient and search
/// results.
class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId, this.name});

  final String recipeId;

  /// App-bar title while the recipe loads.
  final String? name;

  static Route<void> route(String recipeId, {String? name}) =>
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(recipeId: recipeId, name: name),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeDetailProvider(recipeId));
    final title = async.valueOrNull?.name ?? name ?? 'Công thức';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: switch (async) {
        AsyncData(:final value) => _RecipeBody(recipe: value),
        AsyncError(:final error) => Center(
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
          ),
        _ => const _RecipeSkeleton(),
      },
    );
  }
}

class _RecipeBody extends ConsumerWidget {
  const _RecipeBody({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    // Personal warnings only for members; guests see the plain allergen list.
    final allergies = isGuest
        ? const <String>[]
        : ref.watch(userAllergiesProvider).valueOrNull ?? const <String>[];
    final conflicts = recipe.allergenConflicts(allergies);
    final others =
        recipe.allergens.where((a) => !conflicts.contains(a)).toList();
    final kcal = recipe.caloriesCache;

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
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (kcal != null && kcal > 0)
            VLTag(
              label: '${formatInt(kcal)} kcal / phần',
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
      if (recipe.hasMacros) ...[
        const SizedBox(height: 14),
        _MacroRow(recipe: recipe),
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
        onPressed: () => Navigator.of(context)
            .push(SearchScreen.route(initialQuery: recipe.name)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        icon: const Icon(Icons.travel_explore_rounded),
        label: const Text('Tìm video & quán liên quan'),
      ),
      const SizedBox(height: 8),
    ];

    return DefaultTabController(
      length: 2,
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
              tabBar: const TabBar(
                tabs: [Tab(text: 'Nguyên liệu'), Tab(text: 'Cách làm')],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _IngredientsTab(recipe: recipe),
            _StepsTab(recipe: recipe),
          ],
        ),
      ),
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

/// "Nguyên liệu" tab: the ingredient table "cho N phần". Rows found in the
/// nutrition DB open the ingredient's detail.
class _IngredientsTab extends ConsumerWidget {
  const _IngredientsTab({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final index = ref.watch(ingredientIndexProvider).valueOrNull ??
        const <IngredientSummary>[];
    return ListView(
      key: const PageStorageKey('recipe-ingredients'),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text('cho ${recipe.servings ?? 1} phần',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
        const SizedBox(height: 8),
        if (recipe.ingredients.isEmpty)
          Text('Chưa có danh sách nguyên liệu.',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted))
        else
          VLCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, ingredient) in recipe.ingredients.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _IngredientRow(
                    ingredient: ingredient,
                    match: findIngredient(index,
                        id: ingredient.ingredientId, name: ingredient.name),
                  ),
                ],
              ],
            ),
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
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, required this.match});

  final RecipeIngredient ingredient;
  final IngredientSummary? match;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final row = Padding(
      padding: EdgeInsets.fromLTRB(14, 11, m == null ? 14 : 6, 11),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(ingredient.name, style: context.textStyles.bodyLarge),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              ingredient.amount,
              textAlign: TextAlign.end,
              style:
                  AppTypography.mono(size: 14, color: context.colors.onSurface),
            ),
          ),
          if (m != null)
            Icon(Icons.chevron_right_rounded, color: context.vl.muted),
        ],
      ),
    );
    if (m == null) return row;
    return Semantics(
      button: true,
      hint: 'Xem dinh dưỡng',
      child: InkWell(
        onTap: () => Navigator.of(context).push(
            IngredientDetailScreen.route(id: m.id, name: ingredient.name)),
        child: row,
      ),
    );
  }
}

/// "Cách làm" tab: the numbered method.
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

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final items = [
      ('Đạm', recipe.proteinG, vl.macroProtein),
      ('Tinh bột', recipe.carbsG, vl.macroCarbs),
      ('Béo', recipe.fatG, vl.macroFat),
      ('Chất xơ', recipe.fiberG, vl.macroFiber),
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
                Text('${grams!.round()} g',
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
