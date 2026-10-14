// lib/core/widgets/shimmer.dart
import 'package:flutter/material.dart';

import '../theme/vl_colors.dart';

/// Sweeps a highlight across every opaque child (1.4 s loop).
/// Static under "reduce motion" accessibility settings.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final vl = context.vl;

    return Semantics(
      label: 'Đang tải',
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: [vl.skeletonBase, vl.skeletonHighlight, vl.skeletonBase],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlideGradient(_controller.value * 2 - 1),
          ).createShader(bounds),
          child: child,
        ),
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.offset);

  final double offset;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * offset, 0, 0);
}

/// A grey placeholder block. Wrap groups of these in a single [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.vl.skeletonBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
