// lib/features/meal_planner/presentation/widgets/meal_planner_skeleton.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/shimmer.dart';

/// Loading state in the final layout's shape (never a blank spinner).
class MealPlannerSkeleton extends StatelessWidget {
  const MealPlannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(double height, List<Widget> children) => Container(
          height: height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: context.vl.border),
            borderRadius: BorderRadius.circular(16),
            color: context.colors.surface,
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    return SafeArea(
      child: Shimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          children: [
            const SkeletonBox(width: 180, height: 28),
            const SizedBox(height: 20),
            card(170, const [
              Row(children: [
                SkeletonBox(width: 120, height: 70, radius: 60),
                SizedBox(width: 16),
                Expanded(
                  child: Column(children: [
                    SkeletonBox(height: 14),
                    SizedBox(height: 12),
                    SkeletonBox(height: 14),
                    SizedBox(height: 12),
                    SkeletonBox(height: 14),
                  ]),
                ),
              ]),
              Spacer(),
              SkeletonBox(width: 220, height: 24, radius: 999),
            ]),
            const SizedBox(height: 12),
            Row(
              children: List.generate(
                7,
                (_) => const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: SkeletonBox(height: 64, radius: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            card(150, const [
              SkeletonBox(width: 200, height: 16),
              SizedBox(height: 16),
              SkeletonBox(height: 8),
              SizedBox(height: 18),
              SkeletonBox(height: 8),
              SizedBox(height: 18),
              SkeletonBox(height: 8),
            ]),
            const SizedBox(height: 12),
            for (var i = 0; i < 3; i++) ...[
              card(96, const [
                Row(children: [
                  SkeletonBox(width: 52, height: 52, radius: 12),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 120, height: 12),
                          SizedBox(height: 8),
                          SkeletonBox(height: 16),
                        ]),
                  ),
                ]),
              ]),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
