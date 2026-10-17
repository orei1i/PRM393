// lib/features/ingredient/presentation/widgets/ingredient_avatar.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/ingredient.dart';

/// Emoji per nutrition-DB row. Rows without a fitting emoji (tofu, seitan…)
/// use the first-letter fallback.
const Map<String, String> ingredientEmoji = {
  'ing_nam_rom': '🍄',
  'ing_nam_dui_ga': '🍄',
  'ing_nam_huong': '🍄',
  'ing_ca_chua': '🍅',
  'ing_rau_muong': '🥬',
  'ing_rau_chan_vit': '🥬',
  'ing_cai_thia': '🥬',
  'ing_bong_cai_xanh': '🥦',
  'ing_ca_rot': '🥕',
  'ing_bi_do': '🎃',
  'ing_khoai_lang': '🍠',
  'ing_gao_lut': '🍚',
  'ing_yen_mach': '🌾',
  'ing_dau_xanh': '🫘',
  'ing_dau_den': '🫘',
  'ing_dau_ga': '🫘',
  'ing_dau_phong': '🥜',
  'ing_hat_dieu': '🌰',
  'ing_sua_dau_nanh': '🥛',
  'ing_chuoi': '🍌',
  'ing_qua_bo': '🥑',
  'ing_chanh': '🍋',
  'ing_gung': '🫚',
  'ing_toi': '🧄',
  'ing_hanh_tay': '🧅',
  'ing_ot_chuong': '🫑',
  'ing_bap': '🌽',
  'ing_khoai_tay': '🥔',
};

/// Circle colour per category (unknown → neutral).
Color ingredientCategoryColor(BuildContext context, IngredientCategory? c) =>
    switch (c) {
      IngredientCategory.leafy => const Color(0xFF2E9E4F),
      IngredientCategory.veg => const Color(0xFFE07A1F),
      IngredientCategory.mushroom => const Color(0xFF8D6E63),
      IngredientCategory.plantProtein => const Color(0xFF2F7D6B),
      IngredientCategory.grain => const Color(0xFFC59A1B),
      IngredientCategory.nutSeed => const Color(0xFFA0642D),
      IngredientCategory.fruit => const Color(0xFFD94F70),
      IngredientCategory.spice => const Color(0xFFC0392B),
      IngredientCategory.plantMilk => const Color(0xFF3C7DD9),
      null => context.vl.muted,
    };

/// Generated illustration: the ingredient's emoji on a circle tinted with
/// its category colour, or its first letter when there is no emoji.
class IngredientAvatar extends StatelessWidget {
  const IngredientAvatar({
    super.key,
    required this.name,
    this.ingredientId,
    this.category,
    this.size = 44,
  });

  final String name;
  final String? ingredientId;
  final IngredientCategory? category;
  final double size;

  /// The emoji shown, or `null` for the letter fallback.
  String? get emoji => ingredientEmoji[ingredientId];

  /// "Đ" for "đậu hũ".
  String get initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = ingredientCategoryColor(context, category);
    final glyph = emoji;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: glyph != null
            ? Text(glyph, style: TextStyle(fontSize: size * 0.5, height: 1))
            : Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.42,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
      ),
    );
  }
}
