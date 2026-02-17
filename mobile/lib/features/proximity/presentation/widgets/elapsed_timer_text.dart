import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/recording/presentation/providers/live_recording_provider.dart';

/// Displays the elapsed recording time formatted as MM:SS.
///
/// Watches [recordingElapsedProvider] and updates every second.
/// Accepts a configurable [style] for the text appearance.
class ElapsedTimerText extends ConsumerWidget {
  final TextStyle? style;

  const ElapsedTimerText({super.key, this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elapsed = ref.watch(recordingElapsedProvider);

    return elapsed.when(
      data: (duration) => Text(_format(duration), style: style),
      loading: () => Text('00:00', style: style),
      error: (_, __) => Text('--:--', style: style),
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
