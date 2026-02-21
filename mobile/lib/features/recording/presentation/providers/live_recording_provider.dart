import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/recording/domain/models/recording_state.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';

/// Controls whether the full-screen recording overlay is visible.
final liveRecordingOverlayProvider = StateProvider<bool>((ref) => false);

/// Controls whether the compact recording banner is visible.
final liveRecordingBannerProvider = StateProvider<bool>((ref) => false);

/// Ticks every second with the elapsed recording duration.
///
/// Only ticks during RecordingState.recording (not during pending state,
/// since audio recording hasn't started yet).
final recordingElapsedProvider = StreamProvider<Duration>((ref) {
  final recordingState = ref.watch(recordingStateProvider);
  return recordingState.when(
    data: (state) {
      if (state != RecordingState.recording) return const Stream<Duration>.empty();
      final service = ref.read(recordingServiceProvider);
      final startTime = service.recordingStartTime;
      if (startTime == null) return const Stream<Duration>.empty();
      return Stream.periodic(const Duration(seconds: 1), (_) {
        return DateTime.now().difference(startTime);
      });
    },
    loading: () => const Stream<Duration>.empty(),
    error: (_, __) => const Stream<Duration>.empty(),
  );
});

/// Side-effect listener that toggles overlay/banner visibility based on
/// recording state changes.
///
/// - On pending: shows the full-screen overlay (shimmer placeholder while
///   identity chain resolves).
/// - On recording: overlay already visible, content updates to show profile.
/// - On idle/error: dismisses both overlay and banner.
final liveRecordingStateListenerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<RecordingState>>(recordingStateProvider, (prev, next) {
    next.whenData((state) {
      if (state == RecordingState.pending ||
          state == RecordingState.recording) {
        final overlay = ref.read(liveRecordingOverlayProvider);
        final banner = ref.read(liveRecordingBannerProvider);
        // Only show overlay if neither overlay nor banner is already visible
        // (prevents re-showing overlay when user has minimized to banner)
        if (!overlay && !banner) {
          ref.read(liveRecordingOverlayProvider.notifier).state = true;
          ref.read(liveRecordingBannerProvider.notifier).state = false;
        }
      } else {
        // Not pending or recording -- dismiss both
        ref.read(liveRecordingOverlayProvider.notifier).state = false;
        ref.read(liveRecordingBannerProvider.notifier).state = false;
      }
    });
  });
});
