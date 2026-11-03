// lib/core/widgets/demo_data_banner.dart
import 'package:flutter/material.dart';

import '../config/backend_modules.dart';
import '../theme/vl_colors.dart';

/// Says that a screen shows sample data because the server does not support
/// its module yet. Only in a hybrid build: never in a fully mock one.
///
/// Prefer [visibleFor] or [wrap] over an unconditional widget, so a build
/// without the banner keeps its widget tree unchanged.
class DemoDataBanner extends StatelessWidget {
  const DemoDataBanner({super.key, required BackendModule this.module});

  /// For one sample item in a module that is otherwise real (a mock recipe's
  /// page): shown in any hybrid build.
  const DemoDataBanner.sample({super.key}) : module = null;

  static const label = 'Dữ liệu mẫu · Máy chủ chưa hỗ trợ tính năng này';

  final BackendModule? module;

  static bool visibleFor(BackendModule module) =>
      BackendModules.isHybrid && BackendModules.isMock(module);

  /// [child] with the banner above it, or just [child] when it is hidden.
  /// For a `Scaffold.body` or any other bounded slot.
  static Widget wrap(BackendModule module, {required Widget child}) {
    if (!visibleFor(module)) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DemoDataBanner(module: module),
        Expanded(child: child),
      ],
    );
  }

  /// [wrap] for [DemoDataBanner.sample].
  static Widget wrapSample({required Widget child}) {
    if (!BackendModules.isHybrid) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DemoDataBanner.sample(),
        Expanded(child: child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final module = this.module;
    if (module == null ? !BackendModules.isHybrid : !visibleFor(module)) {
      return const SizedBox.shrink();
    }
    final vl = context.vl;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: vl.cautionContainer,
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: vl.onCautionContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: vl.onCautionContainer),
            ),
          ),
        ],
      ),
    );
  }
}
