import 'package:flutter/material.dart';

/// An animated pulsing red dot that indicates an active recording.
///
/// Animates opacity (0.4 - 1.0) and scale (0.8 - 1.0) with a 1-second
/// repeating cycle. The [size] parameter controls the dot diameter.
class PulsingRecordingDot extends StatefulWidget {
  final double size;

  const PulsingRecordingDot({super.key, this.size = 10});

  @override
  State<PulsingRecordingDot> createState() => _PulsingRecordingDotState();
}

class _PulsingRecordingDotState extends State<PulsingRecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
