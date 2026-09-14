import 'package:flutter/material.dart';
import '../view_models/meal_planner_view_model.dart';

class DaySelector extends StatelessWidget {
  const DaySelector({required this.vm, super.key});
  final MealPlannerViewModel vm;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, day) in vm.plan.days.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                selected: vm.selectedIndex == index,
                child: SizedBox(
                  width: constraints.maxWidth > 580
                      ? (constraints.maxWidth - 56) / 7
                      : 76,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 8,
                      ),
                      backgroundColor: vm.selectedIndex == index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface,
                      foregroundColor: vm.selectedIndex == index
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () => vm.selectDay(index),
                    child: Column(
                      children: [
                        Text(MealPlannerViewModel.weekdays[index]),
                        const SizedBox(height: 8),
                        Text(
                          '${day.date.day}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
