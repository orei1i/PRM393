import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/entities/meal_entities.dart';
import '../view_models/meal_planner_view_model.dart';

class BmiCalculatorView extends StatelessWidget {
  const BmiCalculatorView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealPlannerViewModel>();
    return PageBody(
      maxWidth: 640,
      children: [
        const PageHeading(
          title: 'A reference, not a verdict.',
          subtitle: 'Adult BMI calculator · informational only',
        ),
        const Text(
          'BMI is a limited screening measure, not a diagnosis. It does not distinguish muscle from fat or account for individual circumstances. This calculator is not intended for pregnancy or people under 20.',
        ),
        const SizedBox(height: 24),
        SegmentedButton<MeasurementUnit>(
          segments: const [
            ButtonSegment(
              value: MeasurementUnit.metric,
              label: Text('cm / kg'),
            ),
            ButtonSegment(
              value: MeasurementUnit.imperial,
              label: Text('in / lb'),
            ),
          ],
          selected: {vm.unit},
          onSelectionChanged: (selection) => vm.setUnit(selection.first),
        ),
        const SizedBox(height: 24),
        TextFormField(
          key: ValueKey('height-${vm.unit}'),
          initialValue: vm.height,
          onChanged: vm.setHeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: vm.unit == MeasurementUnit.metric
                ? 'Height (cm)'
                : 'Height (inches)',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('weight-${vm.unit}'),
          initialValue: vm.weight,
          onChanged: vm.setWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: vm.unit == MeasurementUnit.metric
                ? 'Weight (kg)'
                : 'Weight (pounds)',
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: vm.adult,
          onChanged: (value) => vm.setAdult(value ?? false),
          title: const Text(
            'I am 20 or older and understand these limitations.',
          ),
        ),
        ErrorNotice(vm.bmiError),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: vm.calculateBmi,
          child: const Text('Calculate BMI'),
        ),
        if (vm.profile != null) ...[
          const SizedBox(height: 24),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR REFERENCE BMI'),
                const SizedBox(height: 10),
                Text(
                  vm.profile!.bmi.toStringAsFixed(1),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                Text(vm.profile!.classification),
                const SizedBox(height: 14),
                const Text(
                  'Standard adult reference interval: 18.5–24.9. This result does not change your meal portions or prescribe weight loss. Measurements are kept only in this app session.',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
