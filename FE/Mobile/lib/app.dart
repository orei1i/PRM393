// lib/app.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/navigation/app_route_stack.dart';
import 'core/navigation/shell_tab.dart';
import 'core/session/onboarding_controller.dart';
import 'core/session/session_controller.dart';
import 'core/settings/theme_mode_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/vl_colors.dart';
import 'features/auth/presentation/screens/forgot_password_screen.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/register_screen.dart';
import 'features/auth/presentation/screens/welcome_screen.dart';
import 'features/chatbot/presentation/screens/chat_screen.dart';
import 'features/chef/presentation/screens/chef_directory_screen.dart';
import 'features/commerce/presentation/screens/payment_screen.dart';
import 'features/community/presentation/screens/feed_screen.dart';
import 'features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'features/profile/presentation/screens/chef_application_screen.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'features/reels/presentation/screens/reels_player_screen.dart';
import 'features/scanner/domain/scan_mode.dart';
import 'features/scanner/presentation/screens/ingredient_scanner_screen.dart';
import 'features/scanner/presentation/widgets/scan_button.dart';

/// VeganLife is mobile-first: every member, guest and chef journey lives in
/// this app. The Next.js project (FE/Web) is the admin console only.
class VeganLifeApp extends ConsumerWidget {
  const VeganLifeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'VeganLife',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Lets the "Hỏi AI" bubble follow the screens pushed over the tabs,
      // and `AppNav` find a page that is already open.
      navigatorObservers: [askAiRouteObserver, _appRouteStack],
      home: const AppEntry(),
    );
  }
}

/// The app navigator's routes, for `AppNav` (found through the navigator's
/// observers).
final _appRouteStack = AppRouteStack();

/// First launch as a guest (`vl.onboarded` unset): the Welcome screen.
/// Otherwise — and as soon as the user signs in or chooses to look around
/// as a guest — the tab shell.
class AppEntry extends ConsumerWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    final onboarded = ref.watch(onboardingProvider);
    if (isGuest && !onboarded) return const WelcomeScreen();
    return const AppShell();
  }
}

/// 4 tabs, 2 on each side of a big round "Quét" button: Trang chủ · Thực đơn
/// | Quét | Chuyên gia · Tôi, the same for every role (a chef's tools live
/// under Tôi). Signing out goes back to Trang chủ as a guest. "Quét" opens
/// the full-screen scanner instead of a tab (tap: the remembered mode, long
/// press: pick Chụp hình / Chọn ảnh / Nhập tay).
///
/// The selected tab is [shellTabProvider], so pushed screens can switch it
/// (`AppNav.toShellTab`). Android Back on another tab goes to Trang chủ;
/// on Trang chủ it leaves the app.
///
/// The bar is a floating capsule (see [_ShellBottomBar]); the tabs scroll
/// behind it and end their lists with `floatingBarClearance` so the last
/// item still clears it.
///
/// "Hỏi AI" is a floating chat-head bubble (see [_AskAiBubble]) in the root
/// overlay: it stays over the tabs and the screens pushed from them, rests
/// as a slim tab on the screen edge, can be dragged to either edge, and
/// steps aside while a tab's list scrolls.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Quiet time after the last scroll update before the bubble comes back.
  static const _scrollSettle = Duration(milliseconds: 450);

  final _barKey = GlobalKey();

  /// Inputs of the bubble layer, which lives in the root overlay (outside
  /// this widget's subtree).
  final _scrolling = ValueNotifier<bool>(false);
  final _barHeight = ValueNotifier<double>(_ShellBottomBar.minHeight);
  final _shellOnTop = ValueNotifier<bool>(true);
  Timer? _scrollIdle;
  OverlayEntry? _bubble;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entry = OverlayEntry(
        builder: (_) => _AskAiBubble(
          host: context,
          scrolling: _scrolling,
          barHeight: _barHeight,
          shellOnTop: _shellOnTop,
          onOpen: _openAi,
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(entry);
      _bubble = entry;
    });
  }

  @override
  void dispose() {
    _scrollIdle?.cancel();
    _bubble?.remove();
    _bubble?.dispose();
    _scrolling.dispose();
    _barHeight.dispose();
    _shellOnTop.dispose();
    super.dispose();
  }

  /// A tab was shown (from the bar or from anywhere else): its list is not
  /// scrolling, whatever the previous tab was doing.
  void _resetScrolling() {
    _scrollIdle?.cancel();
    _scrolling.value = false;
  }

  void _onDestination(ShellTab tab) {
    _resetScrolling();
    ref.read(shellTabProvider.notifier).select(tab);
  }

  Future<void> _scan(ScanMode mode) async {
    final exit = await Navigator.of(context)
        .push(IngredientScannerScreen.route(mode: mode));
    if (!mounted) return;
    if (exit == ScannerExit.openPlanner) _onDestination(ShellTab.planner);
  }

  bool _onScroll(ScrollUpdateNotification n) {
    // A tab's main list only, not nested rows (filter chips, Reels strip).
    if (n.depth != 0 ||
        n.metrics.axis != Axis.vertical ||
        (n.scrollDelta ?? 0) == 0) {
      return false;
    }
    _scrolling.value = true;
    _scrollIdle?.cancel();
    _scrollIdle = Timer(_scrollSettle, () => _scrolling.value = false);
    return false;
  }

  void _openAi() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: askAiRouteName),
          builder: (_) => const ChatScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Signed out (from Tôi or an account menu): back to Trang chủ.
    ref.listen(sessionControllerProvider.select((s) => s.isGuest),
        (wasGuest, isGuest) {
      if (wasGuest == false && isGuest) _onDestination(ShellTab.home);
    });
    ref.listen(shellTabProvider, (_, __) => _resetScrolling());
    final tab = ref.watch(shellTabProvider);
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shellOnTop.value = onTop;
      final height = _barKey.currentContext?.size?.height;
      if (height != null) _barHeight.value = height;
    });
    const pages = <Widget>[
      FeedScreen(),
      MealPlannerScreen(),
      ChefDirectoryScreen(key: ValueKey('tab-chefs')),
      ProfileScreen(),
    ];

    // Android Back with nothing pushed: another tab → Trang chủ; on Trang
    // chủ the route bubbles up and the app closes.
    return PopScope<Object?>(
      canPop: tab == ShellTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onDestination(ShellTab.home);
      },
      child: Scaffold(
        // The tabs run behind the floating bar and see its height as their
        // bottom padding (`floatingBarClearance`); snackbars still sit above
        // it (the Scaffold places them above `bottomNavigationBar`).
        extendBody: true,
        body: NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScroll,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IndexedStack(index: tab.index, children: pages),
              // Over the tabs: a floating app bar (Trang chủ, Chuyên gia)
              // scrolls away and the list would run under the clock.
              const _StatusBarScrim(),
            ],
          ),
        ),
        bottomNavigationBar: KeyedSubtree(
          key: _barKey,
          child: _ShellBottomBar(
            key: const ValueKey('shell-nav'),
            selected: tab.index,
            onSelected: (index) => _onDestination(ShellTab.values[index]),
            onScan: _scan,
          ),
        ),
      ),
    );
  }
}

/// Covers the status bar area of the tabs in the app bar colour, so a list
/// that scrolled its floating app bar away never draws under the clock and
/// the system icons. Sets the status bar icons for that colour (dark icons
/// on the light theme, light icons on the dark one). Lets touches through.
class _StatusBarScrim extends StatelessWidget {
  const _StatusBarScrim();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final theme = Theme.of(context);
    final color =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final light =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: top,
      child: IgnorePointer(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            // iOS names the bar's background, Android the icons' colour.
            statusBarBrightness: light ? Brightness.light : Brightness.dark,
            statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
          ),
          child: ColoredBox(
            key: const ValueKey('shell-status-bar-scrim'),
            color: color,
          ),
        ),
      ),
    );
  }
}

/// TPBank-style floating capsule: detached from the screen edges, a smooth
/// notch in the middle of its top edge for the round scan button, which
/// rises out of it with a ring in the bar colour and a soft glow. "Quét"
/// sits under the button inside the bar. The selected tab has a tinted
/// pill that slides between tabs.
///
/// The widget is the whole bottom band: the space the button rises into,
/// the capsule, the gap under it and the system gesture area. Only the
/// capsule and the button take touches; the rest shows (and passes taps to)
/// the content behind.
class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onScan,
  });

  /// Space above the capsule the scan button rises into.
  static const double rise = 32;
  static const double scanSize = 64;

  /// The scan button's centre sits this far below the capsule's top edge.
  static const double scanDrop = 4;

  /// Bar-coloured ring around the button (on top of its own 4 dp border).
  static const double halo = 2;

  /// Gap between the ring and the notch. Zero: the bar-coloured ring fills
  /// the notch, so content scrolling behind can't show through above "Quét".
  static const double notchGap = 0;
  static const double notchRadius = scanSize / 2 + halo + notchGap;

  static const double capsuleMinHeight = 68;
  static const double capsuleRadius = 30;
  static const double sideMargin = 12;

  /// Between the capsule and the system gesture area.
  static const double bottomGap = 8;

  /// The middle slot, under the button, that holds the "Quét" label.
  static const double centerSlot = 2 * notchRadius + 4;

  /// "Quét" starts just below the notch.
  static const double labelTop = scanDrop + notchRadius + 2;

  /// Height at normal text size, before the gesture-bar inset.
  static const double minHeight = rise + capsuleMinHeight + bottomGap;

  static const _slide = Duration(milliseconds: 280);

  final int selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<ScanMode> onScan;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final vl = context.vl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor =
        NavigationBarTheme.of(context).backgroundColor ?? cs.surfaceContainer;
    final shape = _NotchedCapsuleBorder(
      radius: capsuleRadius,
      notchRadius: notchRadius,
      notchDepth: scanDrop,
      side: BorderSide(
          color: vl.border.withValues(alpha: dark ? 0.9 : 0.7), width: 1),
    );
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Trang chủ'),
      (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Thực đơn'),
      (Icons.soup_kitchen_outlined, Icons.soup_kitchen_rounded, 'Chuyên gia'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Tôi'),
    ];

    Widget item(int index) {
      final (icon, selectedIcon, label) = items[index];
      return Expanded(
        child: _NavItem(
          icon: icon,
          selectedIcon: selectedIcon,
          label: label,
          selected: selected == index,
          onTap: () => onSelected(index),
        ),
      );
    }

    final capsule = DecoratedBox(
      // Shadow only; the fill is drawn over the blurred content below.
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            key: const ValueKey('shell-bar-capsule'),
            decoration: ShapeDecoration(
              shape: shape,
              color: barColor.withValues(alpha: 0.9),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: capsuleMinHeight),
                child: IntrinsicHeight(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _Highlight(selected: selected)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          item(0),
                          item(1),
                          // The button is drawn on top; this slot holds its
                          // label.
                          SizedBox(
                            width: centerSlot,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  top: labelTop, bottom: 8),
                              child: ExcludeSemantics(
                                child: Text(
                                  'Quét',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _NavItem.labelStyle(context,
                                          selected: false)
                                      ?.copyWith(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                          item(2),
                          item(3),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final button = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: barColor,
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: dark ? 0.4 : 0.22),
            blurRadius: 14,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(halo),
        // ScanButton draws its own border in the navigation bar colour.
        child: NavigationBarTheme(
          data: NavigationBarTheme.of(context)
              .copyWith(backgroundColor: barColor),
          child: ScanButton(
            key: const ValueKey('scan-button'),
            size: scanSize,
            onScan: onScan,
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin,
          bottomGap + MediaQuery.viewPaddingOf(context).bottom),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: rise),
            child: capsule,
          ),
          Positioned(
            top: rise + scanDrop - scanSize / 2 - halo,
            left: 0,
            right: 0,
            child: Center(child: button),
          ),
        ],
      ),
    );
  }
}

/// The selected tab's tinted pill; slides to the newly selected tab.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth - _ShellBottomBar.centerSlot) / 4;
      var left =
          selected * slot + (selected >= 2 ? _ShellBottomBar.centerSlot : 0.0);
      if (rtl) left = c.maxWidth - left - slot;
      return Stack(
        children: [
          AnimatedPositioned(
            duration: reduceMotion ? Duration.zero : _ShellBottomBar._slide,
            curve: Curves.easeOutCubic,
            left: left + _NavItem.inset.horizontal / 2,
            width: math.max(0.0, slot - _NavItem.inset.horizontal),
            top: _NavItem.inset.top,
            bottom: _NavItem.inset.bottom,
            child: DecoratedBox(
              key: const ValueKey('shell-nav-highlight'),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: _NavItem.radius,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// Around the tap target (and the highlight pill) inside the capsule.
  static const inset = EdgeInsets.symmetric(horizontal: 2, vertical: 6);
  static const radius = BorderRadius.all(Radius.circular(20));

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static TextStyle? labelStyle(BuildContext context,
          {required bool selected}) =>
      context.textStyles.labelMedium?.copyWith(
        color: selected ? context.colors.primary : context.vl.muted,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = context.vl.muted;
    return Padding(
      padding: inset,
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: selected ? 1 : 0),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : _ShellBottomBar._slide,
                builder: (context, t, _) {
                  final color = Color.lerp(muted, cs.primary, t);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(selected ? selectedIcon : icon,
                          size: 24, color: color),
                      const SizedBox(height: 2),
                      // Large text sizes shrink the label to its slot rather
                      // than cut it ("Trang c…").
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: labelStyle(context, selected: selected)
                                ?.copyWith(color: color),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A capsule with a smooth circular notch in the middle of its top edge
/// (the [CircularNotchedRectangle] curve on rounded corners) for the scan
/// button to sit in.
class _NotchedCapsuleBorder extends ShapeBorder {
  const _NotchedCapsuleBorder({
    required this.radius,
    required this.notchRadius,
    required this.notchDepth,
    this.side = BorderSide.none,
  });

  final double radius;
  final double notchRadius;

  /// How far below the top edge the notch's centre is.
  final double notchDepth;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.all(math.max(side.strokeInset, 0));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final capsule = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect, Radius.circular(math.min(radius, rect.shortestSide / 2))));
    final notch = Rect.fromCircle(
        center: Offset(rect.center.dx, rect.top + notchDepth),
        radius: notchRadius);
    return Path.combine(PathOperation.intersect, capsule,
        const CircularNotchedRectangle().getOuterPath(rect, notch));
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(math.max(side.strokeInset, 0)));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => _NotchedCapsuleBorder(
        radius: radius * t,
        notchRadius: notchRadius * t,
        notchDepth: notchDepth * t,
        side: side.scale(t),
      );

  @override
  bool operator ==(Object other) =>
      other is _NotchedCapsuleBorder &&
      other.radius == radius &&
      other.notchRadius == notchRadius &&
      other.notchDepth == notchDepth &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, notchRadius, notchDepth, side);
}

// ------------------------------------------------------------ "Hỏi AI" --

/// Tracks the top route of the app's navigator for the "Hỏi AI" bubble.
class AskAiRouteObserver extends NavigatorObserver {
  final top = ValueNotifier<Route<dynamic>?>(null);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      top.value = route;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      top.value = previousRoute;

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (top.value == route) top.value = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (top.value == oldRoute) top.value = newRoute;
  }
}

final askAiRouteObserver = AskAiRouteObserver();

/// Name of the assistant's route opened by the bubble.
const askAiRouteName = '/hoi-ai';

/// Hidden with "Ẩn bong bóng" until the app restarts (not persisted).
final askAiBubbleHiddenProvider =
    NotifierProvider<AskAiBubbleHidden, bool>(AskAiBubbleHidden.new);

class AskAiBubbleHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void hide() => state = true;
  void show() => state = false;
}

/// Where the bubble rests: an edge and a 0…1 position between the top and
/// bottom limits (`null` = the default spot).
@visibleForTesting
abstract final class AskAiBubbleStore {
  static const sideKey = 'vl.ai_bubble_side';
  static const yKey = 'vl.ai_bubble_y';
}

/// Wrap a pushed screen (e.g. its Scaffold) in this to keep the "Hỏi AI"
/// bubble off it: screens whose main action sits on the bottom or right
/// edge, or that are a form.
class AskAiBubbleFree extends StatelessWidget {
  const AskAiBubbleFree({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Full-screen flows and forms the bubble stays out of, whatever route
/// pushed them.
const _bubbleFreeScreens = {
  ChatScreen,
  PaymentScreen,
  ReelsPlayerScreen,
  IngredientScannerScreen,
  WelcomeScreen,
  LoginScreen,
  RegisterScreen,
  ForgotPasswordScreen,
  ChefApplicationScreen,
  AskAiBubbleFree,
};

/// Channel to `MainActivity` (Android) for the system gesture exclusion.
@visibleForTesting
const askAiGestureExclusionChannel =
    MethodChannel('vn.veganlife/gesture_exclusion');

/// Android 10+ takes a touch that starts near the left or right screen edge
/// as the system Back gesture unless the app excludes that area. The bubble
/// lives on an edge, so it hands its rect to `MainActivity`
/// (`View.setSystemGestureExclusionRects`). The system honours at most
/// 200 dp per edge; each rect is capped well below that.
///
/// A no-op on other platforms and wherever the channel has no handler
/// (widget tests without a mock: the first [MissingPluginException] turns
/// it off).
class _GestureExclusion {
  static const double _maxHeight = 120;

  List<Rect> _sent = const [];
  bool _off = false;

  static bool get _platform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// [rects] in logical pixels; sent as physical pixels of the Flutter view.
  void update(List<Rect> rects, double devicePixelRatio) {
    if (_off || !_platform) return;
    final physical = [
      for (final r in rects)
        Rect.fromLTRB(
          (r.left * devicePixelRatio).floorToDouble(),
          (r.top * devicePixelRatio).floorToDouble(),
          (r.right * devicePixelRatio).ceilToDouble(),
          (math.min(r.bottom, r.top + _maxHeight) * devicePixelRatio)
              .ceilToDouble(),
        ),
    ];
    if (listEquals(physical, _sent)) return;
    _sent = physical;
    unawaited(_send(physical));
  }

  Future<void> _send(List<Rect> rects) async {
    try {
      await askAiGestureExclusionChannel.invokeMethod<Object?>(
        'setExclusionRects',
        [
          for (final r in rects)
            <String, int>{
              'left': r.left.toInt(),
              'top': r.top.toInt(),
              'right': r.right.toInt(),
              'bottom': r.bottom.toInt(),
            },
        ],
      );
    } on MissingPluginException {
      _off = true;
    } on PlatformException {
      _off = true;
    }
  }
}

/// Messenger-style "Hỏi AI" chat head.
///
/// - At rest it is a slim tab on the screen edge ([tabWidth] dp, inside the
///   screens' 16 dp content padding), so it never sits on a button. It
///   expands to the full 56 dp bubble (AI gradient, "AI" badge) while
///   dragged and for a moment after it is moved, then docks again.
/// - Tap (tab or bubble): opens the assistant. Long press: "Ẩn bong bóng"
///   (until restart, with "Hoàn tác") or "Đưa về vị trí mặc định".
/// - Drag anywhere; on release it springs to the nearest side, kept between
///   the app bar area and the bottom bar (never on the scan button), and
///   the spot is remembered.
/// - Its rect is excluded from Android's edge Back gesture, so dragging it
///   off the edge never leaves the app.
/// - Fades out while a tab's list scrolls, when the keyboard is up, over
///   dialogs / sheets and over full-screen flows (scanner, Reels, payment,
///   the chat itself, screens wrapped in [AskAiBubbleFree]).
class _AskAiBubble extends ConsumerStatefulWidget {
  const _AskAiBubble({
    required this.host,
    required this.scrolling,
    required this.barHeight,
    required this.shellOnTop,
    required this.onOpen,
  });

  /// The shell's context: below the navigator, for menus and snackbars.
  final BuildContext host;
  final ValueListenable<bool> scrolling;
  final ValueListenable<double> barHeight;
  final ValueListenable<bool> shellOnTop;
  final VoidCallback onOpen;

  static const double size = 56;
  static const double margin = 12;

  /// The docked tab: visible width (all of it is on screen) and height.
  static const double tabWidth = 12;
  static const double tabHeight = 56;

  /// Default spot: the leading (left) edge, centre at 38 % of the screen
  /// height. Screens keep their 16 dp padding on that edge even in
  /// horizontal strips (Reels, filter chips), which run off the right edge;
  /// trailing actions ("+", "Xoá hết", chevrons, ⋯) and the bottom-right
  /// primary buttons are on the other side.
  static const double defaultCenter = 0.38;

  @override
  ConsumerState<_AskAiBubble> createState() => _AskAiBubbleState();
}

class _AskAiBubbleState extends ConsumerState<_AskAiBubble>
    with SingleTickerProviderStateMixin {
  /// How long the bubble stays expanded after it was moved.
  static const _dockAfter = Duration(milliseconds: 1500);
  static const _morph = Duration(milliseconds: 250);

  late final AnimationController _snap =
      AnimationController.unbounded(vsync: this)
        ..addListener(() => setState(() {}));
  Offset _snapFrom = Offset.zero;
  Offset _snapTo = Offset.zero;

  bool _right = false;

  /// 0…1 between the limits; null until moved (default spot).
  double? _fraction;

  /// Bubble top-left while the finger is down, and where the finger holds
  /// it.
  Offset? _drag;
  Offset _grab = Offset.zero;

  /// Resting as the slim edge tab.
  bool _docked = true;
  Timer? _dockTimer;

  /// Over a screen the bubble may show on (decided after it builds).
  bool _routeAllowed = true;

  final _exclusion = _GestureExclusion();
  List<Rect> _exclusionRects = const [];
  double _devicePixelRatio = 1;
  bool _exclusionScheduled = false;

  SharedPreferences? get _prefs {
    try {
      return ref.read(sharedPreferencesProvider);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final prefs = _prefs;
    _right = prefs?.getString(AskAiBubbleStore.sideKey) == 'right';
    _fraction = prefs?.getDouble(AskAiBubbleStore.yKey);
    for (final l in [widget.scrolling, widget.barHeight, widget.shellOnTop]) {
      l.addListener(_inputsChanged);
    }
    askAiRouteObserver.top.addListener(_routeChanged);
    _routeChanged();
  }

  @override
  void dispose() {
    for (final l in [widget.scrolling, widget.barHeight, widget.shellOnTop]) {
      l.removeListener(_inputsChanged);
    }
    askAiRouteObserver.top.removeListener(_routeChanged);
    _dockTimer?.cancel();
    _snap.dispose();
    _exclusion.update(const [], _devicePixelRatio);
    super.dispose();
  }

  void _inputsChanged() {
    if (!mounted) return;
    if (widget.shellOnTop.value) _routeAllowed = true;
    setState(() {});
  }

  /// Route changes are reported mid-navigation; look at the new top route
  /// once it has built.
  void _routeChanged() {
    if (!mounted) return;
    final route = askAiRouteObserver.top.value;
    if (route != null && !widget.shellOnTop.value) {
      // Hidden until the new screen is known.
      _routeAllowed = false;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(
          () => _routeAllowed = _allowedOver(askAiRouteObserver.top.value));
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool _allowedOver(Route<dynamic>? route) {
    if (route == null) return true;
    if (route is PopupRoute) return false;
    if (route is PageRoute && route.fullscreenDialog) return false;
    if (route.settings.name == askAiRouteName) return false;
    if (route is ModalRoute) {
      final context = route.subtreeContext;
      if (context != null && _contains(context, _bubbleFreeScreens)) {
        return false;
      }
    }
    return true;
  }

  /// Bounded search of the route's first few widget levels.
  static bool _contains(BuildContext context, Set<Type> types) {
    var budget = 400;
    bool found = false;
    void visit(Element e, int depth) {
      if (found || budget-- <= 0 || depth > 40) return;
      if (types.contains(e.widget.runtimeType)) {
        found = true;
        return;
      }
      e.visitChildElements((c) => visit(c, depth + 1));
    }

    (context as Element).visitChildElements((c) => visit(c, 0));
    return found;
  }

  /// Full bubble for [_dockAfter], then back to the edge tab.
  void _expandBriefly() {
    _dockTimer?.cancel();
    if (_docked && mounted) setState(() => _docked = false);
    _dockTimer = Timer(_dockAfter, _dock);
  }

  void _dock() {
    if (!mounted || _drag != null) return;
    if (_snap.isAnimating) {
      _dockTimer = Timer(_morph, _dock);
      return;
    }
    setState(() => _docked = true);
  }

  ({double minY, double maxY, double left, double right}) _limits(
      MediaQueryData media) {
    final minY = media.padding.top + kToolbarHeight + 8;
    final maxY = math.max(minY,
        media.size.height - widget.barHeight.value - 8 - _AskAiBubble.size);
    return (
      minY: minY,
      maxY: maxY,
      left: media.padding.left,
      right: media.size.width - media.padding.right,
    );
  }

  double _defaultFraction(MediaQueryData media) {
    final l = _limits(media);
    final top =
        media.size.height * _AskAiBubble.defaultCenter - _AskAiBubble.size / 2;
    return l.maxY == l.minY
        ? 0
        : ((top - l.minY) / (l.maxY - l.minY)).clamp(0.0, 1.0);
  }

  /// Top-left of the expanded bubble at rest on its edge.
  Offset _restingSpot(MediaQueryData media) {
    final l = _limits(media);
    final f = _fraction ?? _defaultFraction(media);
    final x = _right
        ? l.right - _AskAiBubble.margin - _AskAiBubble.size
        : l.left + _AskAiBubble.margin;
    return Offset(x, l.minY + f.clamp(0.0, 1.0) * (l.maxY - l.minY));
  }

  /// The docked tab, flush with the edge, centred on the resting spot.
  Rect _tabRect(MediaQueryData media) {
    final l = _limits(media);
    final spot = _restingSpot(media);
    return Rect.fromLTWH(
      _right ? l.right - _AskAiBubble.tabWidth : l.left,
      spot.dy + (_AskAiBubble.size - _AskAiBubble.tabHeight) / 2,
      _AskAiBubble.tabWidth,
      _AskAiBubble.tabHeight,
    );
  }

  void _save() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setString(AskAiBubbleStore.sideKey, _right ? 'right' : 'left');
    final f = _fraction;
    if (f == null) {
      prefs.remove(AskAiBubbleStore.yKey);
    } else {
      prefs.setDouble(AskAiBubbleStore.yKey, f);
    }
  }

  void _springTo(Offset from, MediaQueryData media) {
    _snapFrom = from;
    _snapTo = _restingSpot(media);
    _snap.value = 0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _snap.value = 1;
      return;
    }
    _snap.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 420, damping: 26),
      0,
      1,
      0,
    ));
  }

  Offset _clampDrag(Offset topLeft, MediaQueryData media) {
    final l = _limits(media);
    return Offset(
      topLeft.dx.clamp(l.left, math.max(l.left, l.right - _AskAiBubble.size)),
      topLeft.dy.clamp(l.minY, l.maxY),
    );
  }

  void _onDragStart(DragStartDetails d, Rect current, MediaQueryData media) {
    _dockTimer?.cancel();
    _snap.stop();
    // From the tab the bubble comes out under the finger; a bubble keeps
    // the point it was grabbed by.
    const centre = Offset(_AskAiBubble.size / 2, _AskAiBubble.size / 2);
    final grab = _docked ? centre : d.globalPosition - current.topLeft;
    setState(() {
      _docked = false;
      _grab = grab;
      _drag = _clampDrag(d.globalPosition - grab, media);
    });
  }

  void _onDragUpdate(DragUpdateDetails d, MediaQueryData media) {
    final next = d.globalPosition - _grab;
    setState(() => _drag = _clampDrag(next, media));
  }

  void _onDragEnd(MediaQueryData media) {
    final at = _drag;
    if (at == null) return;
    final l = _limits(media);
    _right = at.dx + _AskAiBubble.size / 2 >= (l.left + l.right) / 2;
    _fraction = l.maxY == l.minY
        ? 0
        : ((at.dy - l.minY) / (l.maxY - l.minY)).clamp(0.0, 1.0);
    _save();
    setState(() => _drag = null);
    _springTo(at, media);
    HapticFeedback.selectionClick();
    _expandBriefly();
  }

  void _moveToSide({required bool right}) {
    final media = MediaQuery.of(context);
    final from = _restingSpot(media);
    _right = right;
    _save();
    _springTo(from, media);
    _expandBriefly();
  }

  void _resetPosition() {
    final media = MediaQuery.of(context);
    final from = _restingSpot(media);
    _right = false;
    _fraction = null;
    _save();
    _springTo(from, media);
    _expandBriefly();
  }

  void _hide() {
    final messenger = ScaffoldMessenger.maybeOf(widget.host);
    final hidden = ref.read(askAiBubbleHiddenProvider.notifier)..hide();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        // With an action Flutter keeps it until dismissed; only for screen
        // readers, so it doesn't sit over the tab bar for everyone else.
        persist: MediaQuery.accessibleNavigationOf(widget.host),
        content:
            const Text('Đã ẩn bong bóng Hỏi AI. Mở lại ứng dụng để hiện lại.'),
        action: SnackBarAction(label: 'Hoàn tác', onPressed: hidden.show),
      ));
  }

  Future<void> _menu(Rect bubble) async {
    _dockTimer?.cancel();
    HapticFeedback.mediumImpact();
    final host = widget.host;
    if (!host.mounted) return;
    final screen = MediaQuery.sizeOf(context);
    final choice = await showMenu<String>(
      context: host,
      position: RelativeRect.fromLTRB(bubble.left, bubble.top,
          screen.width - bubble.right, screen.height - bubble.bottom),
      items: const [
        PopupMenuItem(
          value: 'hide',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_off_outlined),
            title: Text('Ẩn bong bóng'),
          ),
        ),
        PopupMenuItem(
          value: 'reset',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restart_alt_rounded),
            title: Text('Đưa về vị trí mặc định'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'hide':
        _hide();
      case 'reset':
        _resetPosition();
      default:
        if (!_docked) _dockTimer = Timer(_dockAfter, _dock);
    }
  }

  void _open() {
    _dockTimer?.cancel();
    // Back from the assistant it rests as the tab again.
    if (!_docked) setState(() => _docked = true);
    widget.onOpen();
  }

  /// Sends the rects once this frame is done (at most once per frame).
  void _syncExclusion(List<Rect> rects, double devicePixelRatio) {
    _exclusionRects = rects;
    _devicePixelRatio = devicePixelRatio;
    if (_exclusionScheduled) return;
    _exclusionScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _exclusionScheduled = false;
      if (mounted) _exclusion.update(_exclusionRects, _devicePixelRatio);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final hidden = ref.watch(askAiBubbleHiddenProvider);
    final keyboard = media.viewInsets.bottom > 0;
    // Without the observer (an app built without it, e.g. in tests) only
    // the tabs themselves get the bubble.
    final observed = askAiRouteObserver.navigator != null;
    final routeOk = widget.shellOnTop.value || (observed && _routeAllowed);
    final visible = !hidden && !keyboard && routeOk && !widget.scrolling.value;

    final rest = _restingSpot(media);
    final moving = _drag != null || _snap.isAnimating;
    final Offset at;
    if (_drag != null) {
      at = _drag!;
    } else if (_snap.isAnimating) {
      at = Offset.lerp(_snapFrom, _snapTo, _snap.value)!;
    } else {
      at = rest;
    }
    final docked = _docked && !moving;
    final tab = _tabRect(media);
    final rect = docked ? tab : at & const Size.square(_AskAiBubble.size);

    // Keep the system Back gesture off the bubble: its live rect while it
    // moves, otherwise the tab and the resting bubble (covers the morph
    // between them). Nothing while it is hidden.
    final screen = Offset.zero & media.size;
    _syncExclusion(
      !visible
          ? const []
          : [
              (moving
                      ? rect.inflate(8)
                      : tab
                          .expandToInclude(
                              rest & const Size.square(_AskAiBubble.size))
                          .inflate(4))
                  .intersect(screen),
            ],
      media.devicePixelRatio,
    );

    return Stack(
      children: [
        AnimatedPositioned.fromRect(
          duration: moving || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _morph,
          curve: Curves.easeOutCubic,
          rect: rect,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            child: !visible
                ? const SizedBox.shrink(key: ValueKey('ask-ai-hidden'))
                : Semantics(
                    key: const ValueKey('ask-ai'),
                    button: true,
                    label: 'Hỏi AI',
                    hint: 'Mở trợ lý dinh dưỡng AI',
                    customSemanticsActions: {
                      CustomSemanticsAction(
                          label: _right
                              ? 'Đưa sang cạnh trái'
                              : 'Đưa sang cạnh phải'): () =>
                          _moveToSide(right: !_right),
                      const CustomSemanticsAction(
                          label: 'Đưa về vị trí mặc định'): _resetPosition,
                      const CustomSemanticsAction(label: 'Ẩn bong bóng'): _hide,
                    },
                    excludeSemantics: true,
                    child: Tooltip(
                      message: 'Hỏi trợ lý dinh dưỡng AI',
                      triggerMode: TooltipTriggerMode.manual,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _open,
                        onLongPress: () => _menu(rect),
                        onPanStart: (d) => _onDragStart(d, rect, media),
                        onPanUpdate: (d) => _onDragUpdate(d, media),
                        onPanEnd: (_) => _onDragEnd(media),
                        onPanCancel: () => _onDragEnd(media),
                        child: _BubbleFace(docked: docked, right: _right),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The full bubble (AI gradient circle, sparkle, "AI" badge) or, docked, a
/// slim gradient tab with a small sparkle, rounded on the screen side.
class _BubbleFace extends StatelessWidget {
  const _BubbleFace({required this.docked, required this.right});

  final bool docked;
  final bool right;

  static const _morph = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    const tabRadius = Radius.circular(_AskAiBubble.tabWidth);
    final BorderRadius radius;
    if (!docked) {
      radius = BorderRadius.circular(_AskAiBubble.size / 2);
    } else if (right) {
      radius = const BorderRadius.horizontal(left: tabRadius);
    } else {
      radius = const BorderRadius.horizontal(right: tabRadius);
    }
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: _morph,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [vl.ai, cs.primary],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: docked ? 0.2 : 0.28),
                blurRadius: docked ? 6 : 12,
                offset: docked ? const Offset(0, 2) : const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.auto_awesome,
                  key: ValueKey(docked),
                  color: Colors.white,
                  size: docked ? 10 : 26),
            ),
          ),
        ),
        if (!docked)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: vl.aiBorder),
              ),
              child: Text('AI',
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: vl.ai)),
            ),
          ),
      ],
    );
  }
}
