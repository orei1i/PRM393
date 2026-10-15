// lib/core/widgets/floating_bar_clearance.dart
import 'package:flutter/widgets.dart';

/// Gap between a tab list's last item and the top of the floating bar band
/// (the scan button's top).
const double kFloatingBarGap = 16;

/// Bottom padding for the main list of a shell tab (Trang chủ, Thực đơn,
/// Chuyên gia / Khách hàng, Tôi) so its last item scrolls clear of the
/// floating bottom bar: the capsule, the scan button rising out of it, the
/// gap under it and the system gesture area.
///
/// The shell's Scaffold uses `extendBody`, so the tabs scroll behind the bar
/// and their `MediaQuery.padding.bottom` is that whole band. Elsewhere (or
/// with the keyboard up) it is just the system inset.
double floatingBarClearance(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + kFloatingBarGap;
