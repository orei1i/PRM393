// test/helpers/session_helpers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';

/// Signs [account] in through the session controller, the way the app does:
/// email + password against the mock auth server (the seeded credentials of
/// `lib/core/session/mock_accounts.dart`).
///
/// Tests sign in only through this helper, so a change of the sign-in flow
/// touches this file alone.
///
/// [scope] is a [ProviderContainer], or a [WidgetTester] whose tree has a
/// `ProviderScope`. With a tester, pump while the returned future completes
/// (the mock answers in under a second):
///
/// ```dart
/// final done = signInAs(tester, tamChefAccount);
/// await tester.pump(const Duration(seconds: 2));
/// await done;
/// ```
Future<void> signInAs(Object scope, MockAccount account) {
  final container = switch (scope) {
    ProviderContainer() => scope,
    WidgetTester() => ProviderScope.containerOf(
        scope.element(find.byType(UncontrolledProviderScope).first),
        listen: false),
    _ => throw ArgumentError.value(
        scope, 'scope', 'expected a ProviderContainer or a WidgetTester'),
  };
  return container
      .read(sessionControllerProvider.notifier)
      .signIn(email: account.email, password: account.password);
}
