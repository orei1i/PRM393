// lib/features/profile/presentation/screens/my_recipes_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/my_recipes_controller.dart';
import '../../../meal_planner/presentation/screens/user_recipe_form_screen.dart';
import '../../../recipe/presentation/controllers/recipe_controller.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';

/// Tôi › "Công thức của tôi": what the member wrote or saved from a recipe page.
/// Open, create, edit and delete. Should [BackendModules.myRecipeEdit] be off, an
/// edit is saved as a new copy, the page says so, and there is no "Xoá".
class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  /// Under the list when an edit can't overwrite a recipe.
  static const copyNote =
      'Máy chủ chưa cho sửa hoặc xoá công thức: bản sửa được '
      'lưu thành công thức mới, bản cũ vẫn ở trong danh sách.';

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const MyRecipesScreen(),
      );

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final saved =
        await Navigator.of(context).push(UserRecipeFormScreen.route());
    if (saved != null) ref.invalidate(myRecipesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(plannerUserIdProvider) != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Công thức của tôi'),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: 'Tạo công thức',
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: GuestGate(
        icon: Icons.menu_book_rounded,
        title: 'Công thức của tôi',
        message: 'Đăng nhập để lưu công thức của riêng bạn.',
        benefits: const [
          'Lưu công thức đã đổi nguyên liệu để dùng lại',
          'Thêm công thức của bạn vào Thực đơn',
        ],
        child: _Body(onCreate: () => _create(context, ref)),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRecipesProvider);
    if (async.hasError && !async.hasValue) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
            error: async.error!,
            onRetry: () => ref.invalidate(myRecipesProvider),
          ),
        ),
      );
    }
    final recipes = async.valueOrNull;
    if (recipes == null) {
      return const Shimmer(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              SkeletonBox(height: 72, radius: 16),
              SizedBox(height: 12),
              SkeletonBox(height: 72, radius: 16),
            ],
          ),
        ),
      );
    }
    if (recipes.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.menu_book_rounded,
            title: 'Chưa có công thức nào',
            message: 'Tự viết một công thức, hoặc đổi nguyên liệu ở trang công '
                'thức rồi bấm "Lưu thành công thức của tôi".',
            actionLabel: 'Tạo công thức',
            onAction: onCreate,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myRecipesProvider.future),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          for (final recipe in recipes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecipeTile(recipe: recipe),
            ),
          if (!BackendModules.myRecipeEdit)
            Text(
              MyRecipesScreen.copyNote,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
        ],
      ),
    );
  }
}

enum _TileAction { edit, delete }

class _RecipeTile extends ConsumerWidget {
  const _RecipeTile({required this.recipe});

  final Recipe recipe;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final detail = await ref.read(recipeDetailProvider(recipe.id).future);
      final saved =
          await navigator.push(UserRecipeFormScreen.route(existing: detail));
      if (saved == null) return;
      ref
        ..invalidate(myRecipesProvider)
        ..invalidate(recipeDetailProvider(recipe.id));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá công thức?'),
        content: Text('«${recipe.name}» sẽ bị xoá khỏi Công thức của tôi. Món '
            'đã có trong Thực đơn không đổi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(mealPlannerApiProvider).deleteMyRecipe(recipe.id);
      ref.invalidate(myRecipesProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Đã xoá «${recipe.name}»')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = recipe.nutrition.calories;
    final details = [
      if (kcal > 0) '${formatInt(kcal)} kcal / phần',
      if (recipe.prepMinutes case final minutes?) '$minutes phút',
    ].join(' · ');
    return VLCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      onTap: () => Navigator.of(context)
          .push(RecipeDetailScreen.route(recipe.id, name: recipe.name)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.name, style: context.textStyles.titleSmall),
                if (details.isNotEmpty)
                  Text(details,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted)),
              ],
            ),
          ),
          if (BackendModules.myRecipeEdit)
            PopupMenuButton<_TileAction>(
              tooltip: 'Tuỳ chọn cho ${recipe.name}',
              onSelected: (action) => switch (action) {
                _TileAction.edit => _edit(context, ref),
                _TileAction.delete => _delete(context, ref),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: _TileAction.edit, child: Text('Sửa')),
                PopupMenuItem(value: _TileAction.delete, child: Text('Xoá')),
              ],
            )
          else
            IconButton(
              tooltip: '${UserRecipeFormScreen.editLabel}: ${recipe.name}',
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
    );
  }
}
