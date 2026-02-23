import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';

/// A visual waveform widget that renders real-time amplitude bars during
/// recording.
///
/// Displays a series of vertical bars where each bar's height corresponds
/// to a normalized amplitude value (0.0-1.0). Bars are drawn from left to
/// right, with the most recent values on the right. When the number of
/// amplitude values exceeds the available width, only the most recent
/// values are shown (scrolling left effect).
///
/// Example usage:
/// ```dart
/// AmplitudeWaveform(amplitudes: [0.1, 0.5, 0.8, 0.3, 0.6])
/// ```
class AmplitudeWaveform extends StatelessWidget {
  /// Normalized amplitude values in the range 0.0-1.0.
  final List<double> amplitudes;

  const AmplitudeWaveform({super.key, required this.amplitudes});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(amplitudes: amplitudes),
        size: Size.infinite,
      ),
    );
  }
}

/// CustomPainter that renders amplitude bars with rounded corners.
///
/// Each bar is 3px wide with a 2px gap. Bars are centered vertically
/// within the available height. A minimum bar height of 2px ensures
/// silent segments remain visible.
class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;

  _WaveformPainter({required this.amplitudes});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    const barWidth = 3.0;
    const gap = 2.0;
    final maxBars = (size.width / (barWidth + gap)).floor();

    // Show only the most recent values if we exceed available space
    final visibleAmps = amplitudes.length > maxBars
        ? amplitudes.sublist(amplitudes.length - maxBars)
        : amplitudes;

    final paint = Paint()
      ..color = AppColors.accentBlue
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < visibleAmps.length; i++) {
      final x = i * (barWidth + gap);
      final barHeight =
          (visibleAmps[i] * size.height).clamp(2.0, size.height);
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.amplitudes != amplitudes;
}
