import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';

/// A small indicator widget that shows the current recording status.
///
/// - Recording: red dot with "Recording" text
/// - Error: orange dot with "Error" text
/// - Idle or loading: renders nothing (SizedBox.shrink)
class RecordingIndicator extends ConsumerWidget {
  const RecordingIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingState = ref.watch(recordingStateProvider);

    return recordingState.when(
      data: (state) {
        switch (state) {
          case RecordingState.recording:
            return _buildIndicator(
              color: AppColors.error,
              label: 'Recording',
            );
          case RecordingState.error:
            return _buildIndicator(
              color: AppColors.warning,
              label: 'Error',
            );
          case RecordingState.idle:
          case RecordingState.pending:
          case RecordingState.paused:
            return const SizedBox.shrink();
        }
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildIndicator({
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
