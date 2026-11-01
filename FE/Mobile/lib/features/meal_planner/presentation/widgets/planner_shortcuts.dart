// lib/features/meal_planner/presentation/widgets/planner_shortcuts.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../chef/presentation/screens/chef_directory_screen.dart';
import '../../../ingredient/presentation/screens/pantry_screen.dart';

const _pantryTooltip = 'Xem nguyên liệu đang có trong tủ lạnh';
const _chefTooltip = 'Nhờ chuyên gia lên thực đơn';

/// The fridge screen, which has its own guest gate.
void _openPantry(BuildContext context) =>
    Navigator.of(context).push(PantryScreen.route());

/// The same flow as `RequestChefPlanCard`: guests are asked to sign in, then the
/// chef directory opens in pick mode.
Future<void> _openChefPlan(BuildContext context, WidgetRef ref) async {
  if (!await ensureSignedIn(context, ref,
      reason: 'Đăng nhập để nhờ chuyên gia thiết kế thực đơn riêng.')) {
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ChefDirectoryScreen(pickMode: true)));
}

/// App bar icon: the fridge.
class PantryShortcutButton extends StatelessWidget {
  const PantryShortcutButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _pantryTooltip,
        onPressed: () => _openPantry(context),
        icon: const Icon(Icons.kitchen_outlined),
      );
}

/// App bar icon: "Nhờ chuyên gia".
class ChefPlanShortcutButton extends ConsumerWidget {
  const ChefPlanShortcutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: _chefTooltip,
        onPressed: () => _openChefPlan(context, ref),
        icon: const Icon(Icons.support_agent_rounded),
      );
}

/// Top of Thực đơn: both shortcuts, labelled. A long label wraps inside its half
/// at large text sizes.
class PlannerShortcutsRow extends ConsumerWidget {
  const PlannerShortcutsRow({super.key});

  static Widget _button(
          {required String tooltip,
          required IconData icon,
          required String label,
          required VoidCallback onPressed}) =>
      Expanded(
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: Semantics(
            label: tooltip,
            button: true,
            excludeSemantics: true,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 44),
              ),
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
        children: [
          _button(
            tooltip: _pantryTooltip,
            icon: Icons.kitchen_outlined,
            label: 'Tủ lạnh của tôi',
            onPressed: () => _openPantry(context),
          ),
          const SizedBox(width: 8),
          _button(
            tooltip: _chefTooltip,
            icon: Icons.support_agent_rounded,
            label: 'Nhờ chuyên gia',
            onPressed: () => _openChefPlan(context, ref),
          ),
        ],
      );
}
