import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';

/// A reusable pulsing shimmer circle used as a loading placeholder.
///
/// Displays a circular container with a left-to-right gradient sweep
/// animation, creating a smooth shimmer effect. Used in the recording
/// overlay and banner while the peer profile is being resolved during
/// the identity chain (GATT exchange + profile fetch).
class ShimmerAvatar extends StatefulWidget {
  /// The radius of the shimmer circle.
  final double radius;

  const ShimmerAvatar({super.key, required this.radius});

  @override
  State<ShimmerAvatar> createState() => _ShimmerAvatarState();
}

class _ShimmerAvatarState extends State<ShimmerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.radius * 2,
          height: widget.radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: const [
                AppColors.backgroundCard,
                AppColors.border,
                AppColors.backgroundCard,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform:
                  _SlidingGradientTransform(_controller.value * 2 - 0.5),
            ),
          ),
        );
      },
    );
  }
}

/// Custom gradient transform that slides the gradient horizontally.
///
/// Used by [ShimmerAvatar] to create the left-to-right sweep effect.
/// The [slidePercent] controls how far the gradient highlight has moved
/// across the circle.
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}
