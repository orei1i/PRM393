// lib/core/widgets/build_error_fallback.dart
import 'package:flutter/material.dart';

/// What stands in for a widget whose `build` threw, instead of the red (debug)
/// or grey (release) box. The rest of the screen keeps working, and the error
/// is still reported through `FlutterError`.
///
/// Theme-free on purpose: it can replace any widget, above or below the app's
/// `MaterialApp`.
Widget buildErrorFallback(FlutterErrorDetails details) => const Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Không hiển thị được phần này. Hãy quay lại rồi thử lại.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
