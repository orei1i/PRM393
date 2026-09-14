import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../../core/network/backend_config.dart';
import '../../../auth/domain/entities/auth_session.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';

class RoleSwitcher extends StatelessWidget {
  const RoleSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode && !BackendConfig.enableRoleSwitcher) {
      return const SizedBox.shrink();
    }
    final auth = context.watch<AuthViewModel>();
    return Material(
      elevation: 5,
      color: Theme.of(context).colorScheme.inverseSurface,
      borderRadius: BorderRadius.circular(28),
      child: PopupMenuButton<UserRole>(
        tooltip: 'Switch demo role',
        initialValue: auth.role,
        onSelected: auth.switchRole,
        itemBuilder: (context) => UserRole.values
            .map(
              (role) => PopupMenuItem(
                value: role,
                child: Text('${role.name.toUpperCase()} · demo'),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.science_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'DEMO · ${auth.role.name.toUpperCase()}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.unfold_more,
                size: 16,
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
