import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';

Future<AppDependencies> _mount(
  WidgetTester tester,
  String route,
  UserRole role,
) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final d = AppDependencies();
  d.auth.switchRole(role);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    d.dispose();
  });
  await tester.pumpWidget(
    VeganLifeApp(dependencies: d, initialLocation: route),
  );
  await tester.pumpAndSettle();
  return d;
}

Finder _fields() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextFormField),
);
String _fieldText(WidgetTester tester, int index) => tester
    .widget<EditableText>(
      find.descendant(
        of: _fields().at(index),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  testWidgets('Override keeps rejected text and reason until successful save', (
    tester,
  ) async {
    final d = await _mount(tester, '/admin/ai', UserRole.admin);
    await tester.ensureVisible(find.text('Manual override').first);
    await tester.tap(find.text('Manual override').first);
    await tester.pumpAndSettle();
    const draft =
        'Please check every ingredient and consult a registered dietitian.';
    await tester.enterText(_fields().at(0), draft);
    await tester.enterText(_fields().at(1), 'x');
    await tester.tap(find.text('Apply local override'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_fieldText(tester, 0), draft);
    expect(_fieldText(tester, 1), 'x');
    expect(d.aiOperations.logs.first.overridden, isFalse);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Provide replacement text'),
      ),
      findsOneWidget,
    );
    await tester.enterText(_fields().at(1), 'Reviewed for individual needs');
    await tester.tap(find.text('Apply local override'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(d.aiOperations.logs.first.overrideText, draft);
    expect(tester.takeException(), isNull);
  });

  for (final tag in [false, true]) {
    testWidgets(
      '${tag ? 'Tag' : 'Category'} editor preserves rejected name and cancel does not save',
      (tester) async {
        final d = await _mount(tester, '/admin/categories', UserRole.admin);
        final name = tag
            ? d.categories.tags.first.name
            : d.categories.categories.first.name;
        final add = find.byTooltip(tag ? 'Add tag' : 'Add category');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.enterText(_fields(), name);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(_fieldText(tester, 0), name);
        const unique = 'Seasonal favorites';
        await tester.enterText(_fields(), unique);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          tag
              ? d.categories.tags.any((t) => t.name == unique)
              : d.categories.categories.any((c) => c.name == unique),
          isTrue,
        );
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.enterText(_fields(), 'Never saved');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          tag
              ? d.categories.tags.any((t) => t.name == 'Never saved')
              : d.categories.categories.any((c) => c.name == 'Never saved'),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Comment editor stays open on invalid input and saves corrected draft',
    (tester) async {
      final d = await _mount(tester, '/my-content', UserRole.member);
      await tester.tap(find.text('My Comments'));
      await tester.pumpAndSettle();
      final original = d.profile.comments.first;
      await tester.ensureVisible(find.text('Edit').first);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(_fields(), ' ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_fieldText(tester, 0), ' ');
      expect(d.profile.comments.first.text, original.text);
      await tester.enterText(_fields(), 'A useful corrected comment.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        d.profile.comments.firstWhere((c) => c.id == original.id).text,
        'A useful corrected comment.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
