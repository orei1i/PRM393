import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/core/theme/app_theme.dart';
import 'package:vegan_life/src/features/admin_dashboard/domain/entities/admin_entities.dart';
import 'package:vegan_life/src/features/admin_dashboard/presentation/widgets/activity_chart.dart';

void main() {
  const samples = [
    ActivitySample('Mon', 18),
    ActivitySample('Tue', 24),
    ActivitySample('Wed', 20),
    ActivitySample('Thu', 31),
    ActivitySample('Fri', 28),
    ActivitySample('Sat', 42),
    ActivitySample('Sun', 35),
  ];
  for (final table in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('Chart table=$table dark=$dark at large text on phone', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: ActivityChart(samples: samples, tableMode: table),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Mon'), findsOneWidget);
      });
    }
  }
}
