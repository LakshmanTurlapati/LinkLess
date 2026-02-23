import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/debug/presentation/providers/debug_recording_provider.dart';
import 'package:linkless/features/debug/presentation/widgets/amplitude_waveform.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';

/// Toggle record/stop button with elapsed timer and waveform visualization.
///
/// Shows a large circular button that starts/stops a debug recording session.
/// While recording, displays an elapsed timer in MM:SS format and a real-time
/// amplitude waveform below the timer.
///
/// Guards against concurrent audio sessions by checking if a BLE recording
/// is already active before starting.
class DebugRecordButton extends ConsumerStatefulWidget {
  const DebugRecordButton({super.key});

  @override
  ConsumerState<DebugRecordButton> createState() => _DebugRecordButtonState();
}

class _DebugRecordButtonState extends ConsumerState<DebugRecordButton> {
  final List<double> _amplitudes = [];

  @override
  Widget build(BuildContext context) {
    final recordingStateAsync = ref.watch(debugRecordingStateProvider);
    final isRecording = recordingStateAsync.valueOrNull ?? false;

    final elapsedAsync = ref.watch(debugElapsedProvider);
    final elapsed = elapsedAsync.valueOrNull ?? Duration.zero;

    // Listen to amplitude updates and add to rolling buffer
    ref.listen<AsyncValue<double>>(debugAmplitudeProvider, (prev, next) {
      final value = next.valueOrNull;
      if (value != null) {
        setState(() {
          _amplitudes.add(value);
          // Cap at 300 entries (~30 seconds at 100ms intervals)
          if (_amplitudes.length > 300) {
            _amplitudes.removeAt(0);
          }
        });
      }
    });

    return Column(
      children: [
        // Timer and waveform (only visible while recording)
        if (isRecording) ...[
          Text(
            _formatDuration(elapsed),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          AmplitudeWaveform(amplitudes: _amplitudes),
          const SizedBox(height: 12),
        ],

        // Record/Stop button
        GestureDetector(
          onTap: () => _handleTap(isRecording),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error,
                ),
                child: Icon(
                  isRecording ? Icons.stop : Icons.mic,
                  color: AppColors.textPrimary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isRecording ? 'Stop' : 'Record',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleTap(bool isRecording) async {
    final service = ref.read(debugRecordingServiceProvider);

    if (isRecording) {
      await service.stopRecording();
      return;
    }

    // Guard: check if BLE recording is active
    final bleState = ref.read(recordingStateProvider).valueOrNull;
    if (bleState != null && bleState != RecordingState.idle) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot record: BLE recording is active'),
          ),
        );
      }
      return;
    }

    // Guard: check if user is logged in
    final authState = ref.read(authProvider);
    if (authState.status != AuthStatus.authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot record: not logged in'),
          ),
        );
      }
      return;
    }
    final userId = authState.user?.id ?? 'debug';

    // Start recording
    try {
      _amplitudes.clear();
      await service.startRecording(userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}
