// lib/features/ingredient/presentation/screens/ingredient_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/utils/text_search.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/allergy_match.dart';
import '../../../meal_planner/presentation/controllers/pantry_controller.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../data/ingredient_api_service.dart';
import '../../domain/entities/ingredient.dart';
import '../widgets/ingredient_avatar.dart';

/// Nutrition detail of one ingredient: macros and micronutrients per 100 g,
/// who it suits and who should be careful (plus a personal allergy warning),
/// foods not to combine (reference only), dish ideas and catalogue recipes.
/// Opened from a fridge row or a recipe's ingredient row; an ingredient the
/// DB doesn't know says so.
class IngredientDetailScreen extends ConsumerWidget {
  const IngredientDetailScreen(
      {super.key, this.ingredientId, required this.name});

  /// The DB id when known; otherwise [name] is matched against the DB.
  final String? ingredientId;
  final String name;

  static Route<void> route({String? id, required String name}) =>
      MaterialPageRoute<void>(
        builder: (_) => IngredientDetailScreen(ingredientId: id, name: name),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget body;
    if (ingredientId case final id?) {
      body = _ById(id: id, name: name);
    } else {
      final index = ref.watch(ingredientIndexProvider);
      body = switch (index) {
        AsyncData(:final value) => switch (findIngredient(value, name: name)) {
            final match? => _ById(id: match.id, name: name),
            null => _Unknown(name: name),
          },
        AsyncError(:final error) => Center(
            child: SingleChildScrollView(
              child: ErrorStateView(
                  error: error,
                  onRetry: () => ref.invalidate(ingredientIndexProvider)),
            ),
          ),
        _ => const _DetailSkeleton(),
      };
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: body,
    );
  }
}

class _ById extends ConsumerWidget {
  const _ById({required this.id, required this.name});

  final String id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(ingredientDetailProvider(id))) {
      AsyncData(:final value) => _DetailBody(detail: value),
      AsyncError(:final error)
          when error is ApiException && error.statusCode == 404 =>
        _Unknown(name: name),
      AsyncError(:final error) => Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(ingredientDetailProvider(id))),
          ),
        ),
      _ => const _DetailSkeleton(),
    };
  }
}

/// "Thêm vào tủ" / "Đã có trong tủ" for members.
class _PantryButton extends ConsumerStatefulWidget {
  const _PantryButton({required this.name});

  final String name;

  @override
  ConsumerState<_PantryButton> createState() => _PantryButtonState();
}

class _PantryButtonState extends ConsumerState<_PantryButton> {
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final verdict = await ref
          .read(pantryControllerProvider.notifier)
          .addManual(widget.name);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(verdict.isVegan
                ? 'Đã thêm ${widget.name} vào tủ'
                : '${widget.name} không thuần chay nên không thêm vào tủ.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    if (isGuest) return const SizedBox.shrink();
    final key = foldVietnamese(widget.name.trim());
    final inPantry = (ref.watch(pantryControllerProvider).valueOrNull ?? [])
        .any((i) => foldVietnamese(i.ingredient.trim()) == key);
    if (inPantry) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Đã có trong tủ'),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : _add,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
      icon: const Icon(Icons.kitchen_outlined),
      label: const Text('Thêm vào tủ'),
    );
  }
}

class _Unknown extends StatelessWidget {
  const _Unknown({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Center(child: IngredientAvatar(name: name, size: 72)),
        const SizedBox(height: 12),
        Text(name,
            textAlign: TextAlign.center,
            style: context.textStyles.headlineSmall),
        const EmptyStateView(
          icon: Icons.info_outline_rounded,
          title: 'Chưa có dữ liệu dinh dưỡng cho nguyên liệu này',
          message:
              'Bạn vẫn có thể giữ nó trong tủ; AI vẫn dùng tên nguyên liệu khi gợi ý món.',
        ),
        _PantryButton(name: name),
      ],
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail});

  final IngredientDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final s = detail.summary;
    final isGuest =
        ref.watch(sessionControllerProvider.select((x) => x.isGuest));
    final allergies = isGuest
        ? const <String>[]
        : ref.watch(userAllergiesProvider).valueOrNull ?? const <String>[];
    final conflicts = allergyConflicts(
      tags: detail.allergenIds,
      texts: [s.name, ...s.aliases],
      userAllergies: allergies,
    );
    final macros = [
      ('Đạm', detail.proteinG),
      ('Chất béo', detail.fatG),
      ('Tinh bột', detail.carbsG),
      ('Chất xơ', detail.fiberG),
      ('Đường', detail.sugarG),
    ].where((m) => m.$2 != null).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Row(
          children: [
            IngredientAvatar(
                name: s.name,
                ingredientId: s.id,
                category: s.category,
                size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: context.textStyles.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (s.category case final c?)
                        VLTag.neutral(context, c.label),
                      if (s.isVegan)
                        VLTag(
                          label: 'Thuần chay',
                          icon: Icons.eco_outlined,
                          background: vl.successContainer,
                          foreground: vl.onSuccessContainer,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(s.energyLine,
            style: AppTypography.mono(
                size: 14,
                weight: FontWeight.w600,
                color: context.colors.onSurface)),
        const SizedBox(height: 12),
        _PantryButton(name: s.name),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          VLCard(
            color: vl.cautionContainer,
            borderColor: vl.cautionBorder,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: vl.onCautionContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bạn đã khai báo dị ứng với '
                    '${conflicts.map((a) => allergenLabel(a).toLowerCase()).join(', ')}. '
                    'Không nên dùng nguyên liệu này.',
                    style: context.textStyles.bodyMedium?.copyWith(
                        color: vl.onCautionContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const _Title('Thành phần dinh dưỡng', trailing: 'trên 100 g'),
        const SizedBox(height: 8),
        VLCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _NutrientRow(
                  label: 'Năng lượng',
                  value: '${formatInt(s.caloriesPer100g)} kcal'),
              for (final (label, grams) in macros) ...[
                const Divider(height: 1),
                _NutrientRow(label: label, value: '${_grams(grams!)} g'),
              ],
            ],
          ),
        ),
        if (detail.micronutrients.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('Vitamin & khoáng chất', trailing: '%DV trên 100 g'),
          const SizedBox(height: 8),
          VLCard(
            child: Column(
              children: [
                for (final m in detail.micronutrients)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _MicroRow(micro: m),
                  ),
              ],
            ),
          ),
        ],
        if (detail.goodFor.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('Phù hợp với'),
          const SizedBox(height: 6),
          for (final line in detail.goodFor)
            _Bullet(
                text: line,
                icon: Icons.check_circle_outline,
                color: vl.success),
        ],
        if (detail.cautionFor.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('Cần lưu ý / Không phù hợp với'),
          const SizedBox(height: 6),
          for (final line in detail.cautionFor)
            _Bullet(
                text: line,
                icon: Icons.error_outline_rounded,
                color: vl.caution),
        ],
        if (detail.avoidCombining.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('Không nên dùng chung', trailing: 'tham khảo'),
          const SizedBox(height: 6),
          for (final p in detail.avoidCombining)
            _Bullet(
              text: '${p.name}: ${p.reason}',
              icon: Icons.do_not_disturb_on_outlined,
              color: vl.muted,
            ),
        ],
        if (detail.suggestedDishes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('Món gợi ý'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final dish in detail.suggestedDishes)
                VLTag(label: dish, icon: Icons.restaurant_outlined),
            ],
          ),
        ],
        if (detail.recipes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('Công thức có nguyên liệu này'),
          const SizedBox(height: 8),
          VLCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, r) in detail.recipes.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(r.name),
                    subtitle: r.calories == null
                        ? null
                        : Text('${formatInt(r.calories!)} kcal / phần'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context)
                        .push(RecipeDetailScreen.route(r.id, name: r.name)),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          '${detail.source ?? nutritionSourceNote}. $nutritionDisclaimer',
          textAlign: TextAlign.center,
          style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
        ),
      ],
    );
  }

  /// 8.1 → "8,1", 25 → "25".
  static String _grams(double g) =>
      g == g.roundToDouble() ? formatInt(g) : formatDecimal(g);
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      children: [
        Semantics(
            header: true,
            child: Text(text, style: context.textStyles.titleMedium)),
        if (trailing != null)
          Text(trailing!,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
      ],
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textStyles.bodyLarge)),
          Text(value,
              style: AppTypography.mono(
                  size: 14, color: context.colors.onSurface)),
        ],
      ),
    );
  }
}

class _MicroRow extends StatelessWidget {
  const _MicroRow({required this.micro});

  final Micronutrient micro;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final amount = micro.amount == micro.amount.roundToDouble()
        ? formatInt(micro.amount)
        : formatDecimal(micro.amount, digits: micro.amount < 1 ? 2 : 1);
    final dv = micro.dvPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(micro.name, style: context.textStyles.bodyMedium)),
            Text('$amount ${micro.unit}${dv == null ? '' : ' · $dv%'}',
                style: AppTypography.mono(size: 13, color: vl.muted)),
          ],
        ),
        if (dv != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (dv / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 5,
              color: vl.success,
              backgroundColor: vl.skeletonBase,
              semanticsLabel: micro.name,
              semanticsValue: '$dv% nhu cầu mỗi ngày',
            ),
          ),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.icon, required this.color});

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.textStyles.bodyMedium)),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SkeletonBox(width: 64, height: 64, radius: 999),
              SizedBox(width: 14),
              SkeletonBox(width: 160, height: 22),
            ]),
            SizedBox(height: 16),
            SkeletonBox(width: 220, height: 14),
            SizedBox(height: 20),
            SkeletonBox(height: 180, radius: 16),
          ],
        ),
      ),
    );
  }
}
