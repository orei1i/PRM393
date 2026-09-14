import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'bootstrap.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_view_model.dart';

class VeganLifeApp extends StatefulWidget {
  const VeganLifeApp({this.dependencies, this.initialLocation, super.key});
  final AppDependencies? dependencies;
  final String? initialLocation;
  @override
  State<VeganLifeApp> createState() => _VeganLifeAppState();
}

class _VeganLifeAppState extends State<VeganLifeApp> {
  late final AppDependencies _d;
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    _d = widget.dependencies ?? AppDependencies();
    _router = createAppRouter(_d, initialLocation: widget.initialLocation);
  }

  @override
  void dispose() {
    _router.dispose();
    if (widget.dependencies == null) _d.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: _d.auth),
      ChangeNotifierProvider.value(value: _d.theme),
      ChangeNotifierProvider.value(value: _d.feed),
      ChangeNotifierProvider.value(value: _d.explore),
      ChangeNotifierProvider.value(value: _d.chat),
      ChangeNotifierProvider.value(value: _d.trialChat),
      ChangeNotifierProvider.value(value: _d.planner),
      ChangeNotifierProvider.value(value: _d.shops),
      ChangeNotifierProvider.value(value: _d.profile),
      ChangeNotifierProvider.value(value: _d.dashboard),
      ChangeNotifierProvider.value(value: _d.moderationVm),
      ChangeNotifierProvider.value(value: _d.categoriesVm),
      ChangeNotifierProvider.value(value: _d.aiOperationsVm),
    ],
    child: Consumer<ThemeViewModel>(
      builder: (context, theme, _) => MaterialApp.router(
        title: 'VeganLife',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: theme.mode,
        routerConfig: _router,
      ),
    ),
  );
}
