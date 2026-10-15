// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings/theme_mode_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/vl_colors.dart';
import 'features/chatbot/presentation/screens/chat_screen.dart';
import 'features/chef/presentation/screens/chef_directory_screen.dart';
import 'features/community/presentation/screens/feed_screen.dart';
import 'features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'features/scanner/presentation/screens/ingredient_scanner_screen.dart';

/// VeganLife is mobile-first: every member, guest and chef journey lives in
/// this app. The Next.js project (FE/Web) is the admin console only.
class VeganLifeApp extends ConsumerWidget {
  const VeganLifeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'VeganLife',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AppShell(),
    );
  }
}

/// 5 tabs (Trang chủ · Thực đơn · Quét · Chuyên gia · Tôi) + the global
/// "Hỏi AI" button. "Quét" opens the full-screen camera instead of a tab.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _scanDestination = 2;

  /// Index into [_pages] (the scan destination has no page).
  int _page = 0;

  static const _pages = <Widget>[
    FeedScreen(),
    MealPlannerScreen(),
    ChefDirectoryScreen(),
    ProfileScreen(),
  ];

  int get _selectedDestination => _page >= _scanDestination ? _page + 1 : _page;

  void _onDestination(int index) {
    if (index == _scanDestination) {
      Navigator.of(context).push(IngredientScannerScreen.route());
      return;
    }
    setState(() => _page = index > _scanDestination ? index - 1 : index);
  }

  void _openAi() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _page, children: _pages),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ask-ai',
        onPressed: _openAi,
        backgroundColor: context.vl.ai,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Hỏi AI'),
        tooltip: 'Hỏi trợ lý dinh dưỡng AI',
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedDestination,
        onDestinationSelected: _onDestination,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Thực đơn',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner_rounded),
            label: 'Quét',
          ),
          NavigationDestination(
            icon: Icon(Icons.soup_kitchen_outlined),
            selectedIcon: Icon(Icons.soup_kitchen_rounded),
            label: 'Chuyên gia',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Tôi',
          ),
        ],
      ),
    );
  }
}
