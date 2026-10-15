// lib/core/widgets/food_cover.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Deterministic illustrated cover used until real media (Cloudinary URLs)
/// arrive from the API. The same [seed] always renders the same cover.
class FoodCover extends StatelessWidget {
  const FoodCover({
    super.key,
    required this.seed,
    this.imageUrl,
    this.height,
    this.aspectRatio,
    this.borderRadius = BorderRadius.zero,
    this.child,
  });

  final String seed;

  /// When set, the network image is drawn over the illustration.
  final String? imageUrl;
  final double? height;
  final double? aspectRatio;
  final BorderRadius borderRadius;

  /// Overlay (play button, duration chip, AI status…).
  final Widget? child;

  static const _palettes = <List<Color>>[
    [AppColors.sage700, AppColors.sprout500],
    [AppColors.ochre500, AppColors.ochre300],
    [AppColors.sage900, AppColors.sage700],
    [Color(0xFFB45309), Color(0xFFF59E0B)],
    [Color(0xFF15803D), Color(0xFF84CC16)],
    [Color(0xFF9A3412), Color(0xFFF97316)],
    [AppColors.ai700, AppColors.ai400],
  ];

  static const _icons = <IconData>[
    Icons.ramen_dining_rounded,
    Icons.rice_bowl_rounded,
    Icons.eco_rounded,
    Icons.soup_kitchen_rounded,
    Icons.bakery_dining_rounded,
    Icons.local_florist_rounded,
    Icons.spa_rounded,
    Icons.breakfast_dining_rounded,
  ];

  static int _hash(String s) {
    var h = 7;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final h = _hash(seed);
    final colors = _palettes[h % _palettes.length];
    final icon = _icons[(h ~/ 7) % _icons.length];

    Widget cover = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -22,
            child: Icon(icon,
                size: 140, color: Colors.white.withValues(alpha: 0.18)),
          ),
          if (imageUrl != null)
            Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (child != null) child!,
        ],
      ),
    );

    cover = ClipRRect(borderRadius: borderRadius, child: cover);
    if (aspectRatio != null) {
      return AspectRatio(aspectRatio: aspectRatio!, child: cover);
    }
    return SizedBox(
        height: height ?? 160, width: double.infinity, child: cover);
  }
}
