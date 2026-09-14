import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/entities/admin_entities.dart';

class ActivityChart extends StatelessWidget {
  const ActivityChart({
    required this.samples,
    required this.tableMode,
    super.key,
  });
  final List<ActivitySample> samples;
  final bool tableMode;

  @override
  Widget build(BuildContext context) {
    if (tableMode) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Day')),
            DataColumn(label: Text('Contributions'), numeric: true),
          ],
          rows: [
            for (final sample in samples)
              DataRow(
                cells: [
                  DataCell(Text(sample.day)),
                  DataCell(Text('${sample.contributions}')),
                ],
              ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    final color = theme.brightness == Brightness.dark
        ? const Color(0xFF43A047)
        : const Color(0xFF2E7D32);
    final labelHeight = MediaQuery.textScalerOf(context).scale(14) + 12;
    final minWidth =
        samples.length * MediaQuery.textScalerOf(context).scale(11) * 4.5 + 40;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(minWidth, constraints.maxWidth),
          height: 220 + labelHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(right: 10, bottom: labelHeight),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('50'), Text('25'), Text('0')],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      bottom: labelHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Divider(
                              height: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final sample in samples)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${sample.day}: ${sample.contributions} contributions',
                              triggerMode: TooltipTriggerMode.tap,
                              child: Semantics(
                                label:
                                    '${sample.day}, ${sample.contributions} sample contributions',
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: FractionallySizedBox(
                                          heightFactor:
                                              sample.contributions / 50,
                                          child: Container(
                                            width: 20,
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(4),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: labelHeight,
                                      child: Center(
                                        child: Text(
                                          sample.day,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
