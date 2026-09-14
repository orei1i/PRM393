import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../theme/theme_view_model.dart';
import 'navigation_section.dart';
import '../../features/auth/presentation/view_models/auth_view_model.dart';
import '../../features/auth/presentation/widgets/auth_sheet.dart';
import '../../features/role_switcher/presentation/widgets/role_switcher.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.child, required this.location, super.key});
  final Widget child;
  final String location;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final theme = context.watch<ThemeViewModel>();
    final destinations = auth.isAdmin
        ? _admin
        : auth.isGuest
        ? _guest
        : _member;
    final section = navigationRoot(location, auth.role);
    final index = destinations.indexWhere((d) => d.path == section);
    final selected = index < 0 ? 0 : index;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.spa,
                  color: Theme.of(context).colorScheme.primary,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'VeganLife',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<ThemeMode>(
                tooltip: 'Appearance',
                icon: const Icon(Icons.contrast),
                initialValue: theme.mode,
                onSelected: theme.setMode,
                itemBuilder: (_) => [
                  for (final mode in ThemeMode.values)
                    PopupMenuItem(
                      value: mode,
                      child: Text('${mode.name} theme'),
                    ),
                ],
              ),
              if (auth.isGuest)
                TextButton(
                  onPressed: () => showAuthSheet(context),
                  child: const Text('Join us'),
                ),
              if (!auth.isGuest)
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: auth.signOut,
                  icon: const Icon(Icons.logout),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: RoleSwitcher(),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (wide) ...[
                        NavigationRail(
                          extended: constraints.maxWidth >= 1120,
                          selectedIndex: selected,
                          onDestinationSelected: (index) =>
                              context.go(destinations[index].path),
                          destinations: [
                            for (final destination in destinations)
                              NavigationRailDestination(
                                icon: Icon(destination.icon),
                                label: Text(destination.label),
                              ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) =>
                      context.go(destinations[index].path),
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }

  static const _guest = [
    _Destination('Explore', '/explore', Icons.explore_outlined),
    _Destination('Try AI', '/trial', Icons.auto_awesome_outlined),
  ];
  static const _member = [
    _Destination('Community', '/community', Icons.grid_view_rounded),
    _Destination('Ask AI', '/assistant', Icons.auto_awesome_outlined),
    _Destination('Meal plan', '/planner', Icons.calendar_month_outlined),
    _Destination('Nearby', '/discover', Icons.place_outlined),
    _Destination('You', '/profile', Icons.person_outline),
  ];
  static const _admin = [
    _Destination('Overview', '/admin', Icons.dashboard_outlined),
    _Destination('Moderation', '/admin/moderation', Icons.shield_outlined),
    _Destination('Categories', '/admin/categories', Icons.category_outlined),
    _Destination('AI ops', '/admin/ai', Icons.auto_awesome_outlined),
  ];
}

class _Destination {
  const _Destination(this.label, this.path, this.icon);
  final String label, path;
  final IconData icon;
}
