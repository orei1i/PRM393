// test/integration_advisor/snackbar_persist_guard_test.dart
//
// Flutter keeps a SnackBar that has an action on screen until it is
// dismissed (`persist` defaults to `action != null`). On a device that left
// "Hoàn tác", "Xem" and "Xem Thực đơn" covering the buttons under them. Every
// SnackBar with an action sets `persist:` (only screen-reader users keep
// it), so it leaves after its duration like the rest.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every SnackBar with an action sets persist', () {
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final actions = 'SnackBarAction('.allMatches(source).length;
      final persists = 'persist:'.allMatches(source).length;
      if (actions > persists) {
        missing.add('${entity.path}: $actions action(s), $persists persist');
      }
    }
    expect(missing, isEmpty);
  });
}
