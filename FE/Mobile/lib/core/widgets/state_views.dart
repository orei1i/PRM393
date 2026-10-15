// lib/core/widgets/state_views.dart
import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../theme/vl_colors.dart';

/// Empty state: what happened + the next step.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.colors.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: context.colors.primary),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: context.textStyles.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            message,
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.muted),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Error state with a retry button. Network errors get their own icon/copy.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isNetwork =
        error is ApiException && (error as ApiException).isNetwork;
    return EmptyStateView(
      icon: isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: isNetwork ? 'Mất kết nối' : 'Chưa tải được dữ liệu',
      message: describeError(error),
      actionLabel: onRetry == null ? null : 'Thử lại',
      onAction: onRetry,
    );
  }
}
