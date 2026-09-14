import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/food_art.dart';
import '../view_models/meal_planner_view_model.dart';
import '../widgets/day_selector.dart';

class WeeklyMealCalendarView extends StatefulWidget {
  const WeeklyMealCalendarView({super.key});
  @override
  State<WeeklyMealCalendarView> createState() => _WeeklyMealCalendarViewState();
}

class _WeeklyMealCalendarViewState extends State<WeeklyMealCalendarView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _syncWeek);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWeek());
  }

  void _syncWeek() {
    if (mounted) context.read<MealPlannerViewModel>().syncCurrentWeek();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealPlannerViewModel>();
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'A little planning, a lot of good',
          title: 'Your week, well nourished.',
          subtitle: vm.dateRange,
          action: OutlinedButton.icon(
            onPressed: () => context.push('/bmi'),
            icon: const Icon(Icons.monitor_weight_outlined),
            label: const Text('BMI reference'),
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusBadge('PANTRY TO PLATE', icon: Icons.auto_awesome),
              const SizedBox(height: 14),
              Text(
                'What’s in your kitchen?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'List a few ingredients and we’ll arrange a week of sample meals.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: vm.pantry,
                onChanged: vm.setPantry,
                decoration: const InputDecoration(
                  hintText: 'e.g. tofu, spinach, lentils',
                  prefixIcon: Icon(Icons.kitchen_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: vm.busy ? null : vm.generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      vm.busy ? 'Planning your week…' : 'Generate my week',
                    ),
                  ),
                  const Text(
                    'Demo plan · not a prescribed diet',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              if (vm.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        ErrorNotice(vm.error, onRetry: vm.generate),
        const SizedBox(height: 24),
        DaySelector(vm: vm),
        SectionTitle(
          '${MealPlannerViewModel.weekdays[vm.selectedIndex]}’s menu',
        ),
        AdaptiveCards(
          minWidth: 280,
          children: [
            for (final meal in vm.selectedDay.meals)
              SurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FoodArt(variant: meal.art, height: 155),
                    const SizedBox(height: 14),
                    StatusBadge(meal.kind.toUpperCase()),
                    const SizedBox(height: 12),
                    Text(
                      meal.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('${meal.minutes} min · plant-powered'),
                    const SizedBox(height: 12),
                    Text(
                      meal.ingredients.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SectionTitle('Your weekly shopping list'),
        const Text(
          'Check off what you already have. Suggested meals may need ingredients beyond your pantry list. Quantities depend on your portions.',
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ingredient in vm.shopping)
                FilterChip(
                  label: Text(ingredient.name),
                  selected: ingredient.checked,
                  onSelected: (_) => vm.toggleIngredient(ingredient.name),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Sample meal ideas do not assess allergies or individual nutritional needs. Check every ingredient and consult a dietitian when needed.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
