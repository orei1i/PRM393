// lib/core/navigation/shell_tab.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 4 tabs of the app shell, in bar order (the round "Quét" button sits
/// between [planner] and [chefs] and is not a tab).
enum ShellTab {
  home('Trang chủ'),
  planner('Thực đơn'),
  chefs('Chuyên gia'),
  me('Tôi');

  const ShellTab(this.label);

  /// The bar label.
  final String label;
}

/// The selected shell tab. Any screen can switch it (e.g. "Xem Thực đơn"
/// through `AppNav.toShellTab`); the shell keeps every tab's state.
final shellTabProvider =
    NotifierProvider<ShellTabController, ShellTab>(ShellTabController.new);

class ShellTabController extends Notifier<ShellTab> {
  @override
  ShellTab build() => ShellTab.home;

  void select(ShellTab tab) => state = tab;
}
