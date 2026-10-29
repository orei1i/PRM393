// test/nav_foundation/app_nav_test.dart
// WP0: route names, the root route stack and the AppNav helpers.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_history_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

/// A page showing [label], named [name].
MaterialPageRoute<String> _page(String? name, String label) =>
    MaterialPageRoute<String>(
      settings: RouteSettings(name: name),
      builder: (_) => Scaffold(body: Center(child: Text(label))),
    );

class _App {
  _App(this.stack);

  final AppRouteStack? stack;
  final key = GlobalKey<NavigatorState>();

  NavigatorState get nav => key.currentState!;

  List<String?> get names => [for (final r in stack!.routes) r.settings.name];
}

/// A plain app: the shell ("shell") is the first route, named '/'.
Future<_App> _pump(WidgetTester tester,
    {bool observed = true, AppRouteStack? stack}) async {
  final app = _App(observed ? (stack ?? AppRouteStack()) : null);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      navigatorKey: app.key,
      navigatorObservers: [if (app.stack != null) app.stack!],
      home: const Scaffold(body: Center(child: Text('shell'))),
    ),
  ));
  return app;
}

Future<void> _push(WidgetTester tester, _App app, Route<String> route) async {
  app.nav.push(route);
  await tester.pumpAndSettle();
}

void main() {
  group('AppRoutes', () {
    test('names carry the item, search and history do not', () {
      expect(AppRoutes.recipe('l5'), '/recipe/l5');
      expect(AppRoutes.ingredient(id: 'ing_ca_chua', name: 'Cà chua'),
          '/ingredient/ing_ca_chua');
      expect(AppRoutes.ingredient(name: ' Cà chua '), '/ingredient/ca chua');
      expect(AppRoutes.search, '/search');
      expect(AppRoutes.booking('b_1'), '/booking/b_1');
      expect(AppRoutes.bookingHistory, '/booking-history');
      expect(AppRoutes.bodyMetrics, '/body-metrics');
    });

    test('the screens\' route() set them', () {
      expect(
          RecipeDetailScreen.route('l5', name: 'Bún riêu chay').settings.name,
          '/recipe/l5');
      expect(IngredientDetailScreen.route(name: 'Cà chua').settings.name,
          '/ingredient/ca chua');
      expect(
          IngredientDetailScreen.route(id: 'ing_ca_chua', name: 'Cà chua')
              .settings
              .name,
          '/ingredient/ing_ca_chua');
      expect(SearchScreen.route(initialQuery: 'bún').settings.name, '/search');
      expect(SearchScreen.route().settings.name, '/search');
      expect(BookingDetailScreen.route('b_1', initialTab: 2).settings.name,
          '/booking/b_1');
      expect(BookingHistoryScreen.route().settings.name, '/booking-history');
    });
  });

  group('AppRouteStack', () {
    testWidgets(
        'mirrors push, pop, remove, replace, pushReplacement, '
        'pushAndRemoveUntil and dialogs', (tester) async {
      final app = await _pump(tester);
      expect(AppRouteStack.of(app.nav), same(app.stack));
      expect(app.names, ['/']);

      final a = _page('/a', 'a');
      final b = _page('/b', 'b');
      await _push(tester, app, a);
      await _push(tester, app, b);
      await _push(tester, app, _page('/c', 'c'));
      expect(app.names, ['/', '/a', '/b', '/c']);
      expect(app.stack!.lastNamed('/b'), same(b));
      expect(app.stack!.lastNamed('/x'), isNull);

      app.nav.pop();
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/a', '/b']);

      app.nav.removeRoute(a);
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/b']);

      app.nav.replace(oldRoute: b, newRoute: _page('/d', 'd'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/d']);
      expect(find.text('d'), findsOneWidget);

      app.nav.pushReplacement(_page('/e', 'e'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/e']);

      showDialog<void>(
          context: tester.element(find.text('e')),
          builder: (_) => const AlertDialog(content: Text('hộp thoại')));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/e', null]);
      app.nav.pop();
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/e']);

      await _push(tester, app, _page('/e', 'e again'));
      expect(app.stack!.countNamed('/e'), 2);
      app.nav.pushAndRemoveUntil(_page('/f', 'f'), (r) => r.isFirst);
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/f']);
    });

    testWidgets('a new app tree starts from an empty stack', (tester) async {
      final stack = AppRouteStack();
      var app = await _pump(tester, stack: stack);
      await _push(tester, app, _page('/a', 'a'));
      expect(app.names, ['/', '/a']);

      await tester.pumpWidget(const SizedBox());
      expect(stack.routes, isEmpty, reason: 'no navigator any more');
      app = await _pump(tester, stack: stack);
      expect(app.names, ['/']);
    });
  });

  group('AppNav', () {
    testWidgets('open goes back to the page already open, else pushes',
        (tester) async {
      final app = await _pump(tester);
      await _push(tester, app, _page(AppRoutes.recipe('l5'), 'Bún riêu chay'));
      await _push(
          tester, app, _page(AppRoutes.ingredient(name: 'Cà chua'), 'Cà chua'));

      final back = AppNav.open(
          app.nav, _page(AppRoutes.recipe('l5'), 'Bún riêu chay (bản 2)'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/recipe/l5']);
      expect(find.text('Bún riêu chay'), findsOneWidget);
      expect(find.text('Bún riêu chay (bản 2)'), findsNothing);
      expect(await back, isNull);

      // Already on top: stays.
      AppNav.open(app.nav, _page(AppRoutes.recipe('l5'), 'copy'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/recipe/l5']);

      // Another recipe: pushed, and its result comes back.
      final result =
          AppNav.open(app.nav, _page(AppRoutes.recipe('menu_1'), 'menu 1'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/recipe/l5', '/recipe/menu_1']);
      app.nav.pop('xong');
      await tester.pumpAndSettle();
      expect(await result, 'xong');

      // Unnamed routes are always pushed.
      AppNav.open(app.nav, _page(null, 'không tên'));
      AppNav.open(app.nav, _page(null, 'không tên 2'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/recipe/l5', null, null]);
    });

    testWidgets('open pops dialogs and pages above the existing page',
        (tester) async {
      final app = await _pump(tester);
      await _push(tester, app, _page(AppRoutes.search, 'search'));
      await _push(tester, app, _page(AppRoutes.recipe('l5'), 'recipe'));
      showModalBottomSheet<void>(
          context: tester.element(find.text('recipe')),
          builder: (_) => const Text('sheet'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/search', '/recipe/l5', null]);

      AppNav.open(app.nav, _page(AppRoutes.search, 'search 2'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/search']);
      expect(find.text('search'), findsOneWidget);
    });

    testWidgets(
        'replaceExisting removes the page and what is above it, then pushes '
        'the new one', (tester) async {
      final app = await _pump(tester);
      await _push(tester, app, _page(AppRoutes.search, 'search: bún'));
      await _push(tester, app, _page(AppRoutes.recipe('l5'), 'recipe'));

      AppNav.replaceExisting(
          app.nav, _page(AppRoutes.search, 'search: bún riêu chay'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/search']);
      expect(app.stack!.countNamed(AppRoutes.search), 1);
      expect(find.text('search: bún riêu chay'), findsOneWidget);

      app.nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('shell'), findsOneWidget);
      expect(app.names, ['/']);

      // Nothing to replace: a push.
      AppNav.replaceExisting(app.nav, _page(AppRoutes.search, 'search 3'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/search']);
    });

    testWidgets('resetTo leaves one page above the shell', (tester) async {
      final app = await _pump(tester);
      await _push(tester, app, _page('/directory', 'directory'));
      await _push(tester, app, _page('/chef', 'chef'));
      await _push(tester, app, _page('/book', 'book'));

      AppNav.resetTo(app.nav, _page(AppRoutes.booking('b_1'), 'booking'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/booking/b_1']);
      app.nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('shell'), findsOneWidget);
    });

    testWidgets('popToOrReset: back to the open page, else reset',
        (tester) async {
      final app = await _pump(tester);
      await _push(tester, app, _page(AppRoutes.bookingHistory, 'history'));
      await _push(tester, app, _page(AppRoutes.booking('b_1'), 'detail'));
      await _push(tester, app, _page('/payment', 'payment'));

      AppNav.popToOrReset(app.nav, _page(AppRoutes.bookingHistory, 'new'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/booking-history']);
      expect(find.text('history'), findsOneWidget);

      app.nav.pop();
      await tester.pumpAndSettle();
      await _push(tester, app, _page(AppRoutes.booking('b_1'), 'detail'));
      await _push(tester, app, _page('/payment', 'payment'));
      AppNav.popToOrReset(app.nav, _page(AppRoutes.bookingHistory, 'new'));
      await tester.pumpAndSettle();
      expect(app.names, ['/', '/booking-history']);
      expect(find.text('new'), findsOneWidget);
    });

    testWidgets('without a route stack every helper still navigates',
        (tester) async {
      final app = await _pump(tester, observed: false);
      expect(AppRouteStack.of(app.nav), isNull);

      AppNav.open(app.nav, _page(AppRoutes.recipe('l5'), 'first'));
      await tester.pumpAndSettle();
      AppNav.open(app.nav, _page(AppRoutes.recipe('l5'), 'second'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      AppNav.replaceExisting(app.nav, _page(AppRoutes.search, 'search'));
      await tester.pumpAndSettle();
      expect(find.text('search'), findsOneWidget);

      app.nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget, reason: 'plain pushes');
      app.nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);

      AppNav.popToOrReset(app.nav, _page(AppRoutes.bookingHistory, 'history'));
      await tester.pumpAndSettle();
      app.nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('shell'), findsOneWidget, reason: 'reset');
    });

    testWidgets('toShellTab pops to the shell and selects the tab',
        (tester) async {
      final app = await _pump(tester);
      for (final label in ['a', 'b']) {
        await _push(
          tester,
          app,
          MaterialPageRoute<String>(
            settings: RouteSettings(name: '/$label'),
            builder: (_) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => AppNav.toShellTab(
                      Navigator.of(context), ref, ShellTab.planner),
                  child: Text('Xem Thực đơn $label'),
                ),
              ),
            ),
          ),
        );
      }
      final container = ProviderScope.containerOf(
          tester.element(find.text('shell', skipOffstage: false)));
      expect(container.read(shellTabProvider), ShellTab.home);

      await tester.tap(find.text('Xem Thực đơn b'));
      await tester.pumpAndSettle();
      expect(app.names, ['/']);
      expect(find.text('shell'), findsOneWidget);
      expect(container.read(shellTabProvider), ShellTab.planner);
    });
  });
}
