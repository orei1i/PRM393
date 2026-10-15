// lib/core/widgets/user_avatar.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/vl_colors.dart';

/// Initials avatar with a stable colour per name, plus an optional
/// "verified chef" tick.
class UserAvatar extends StatelessWidget {
  const UserAvatar(
      {super.key, required this.name, this.size = 40, this.verified = false});

  final String name;
  final double size;
  final bool verified;

  static const _backgrounds = [
    AppColors.sage100,
    AppColors.ochre50,
    AppColors.ai50,
    AppColors.sprout100,
  ];
  static const _foregrounds = [
    AppColors.sage800,
    AppColors.ochre800,
    AppColors.ai700,
    AppColors.sprout800,
  ];

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[parts.length - 2].characters.first +
            parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final i =
        name.codeUnits.fold<int>(0, (a, b) => a + b) % _backgrounds.length;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: _backgrounds[i],
            foregroundColor: _foregrounds[i],
            child: Text(
              _initials,
              style:
                  TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.36),
            ),
          ),
          if (verified)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                    color: context.colors.surface, shape: BoxShape.circle),
                child: Icon(Icons.verified_rounded,
                    size: size * 0.38, color: context.vl.success),
              ),
            ),
        ],
      ),
    );
  }
}
