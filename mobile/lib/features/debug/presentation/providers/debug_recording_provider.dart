import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/debug/data/services/debug_recording_service.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';
import 'package:linkless/features/sync/presentation/providers/sync_provider.dart';

/// Provides the [DebugRecordingService] singleton, wired with
/// [ConversationDao] and [SyncEngine].
///
/// Disposed when the provider is no longer watched.
final debugRecordingServiceProvider = Provider<DebugRecordingService>((ref) {
  final dao = ref.watch(conversationDaoProvider);
  final syncEngine = ref.watch(syncEngineProvider);

  final service = DebugRecordingService(
    conversationDao: dao,
    syncEngine: syncEngine,
  );

  ref.onDispose(() => service.dispose());

  return service;
});

/// Streams the recording state (true = recording, false = idle).
///
/// Rebuilds downstream consumers whenever recording starts or stops.
final debugRecordingStateProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(debugRecordingServiceProvider);
  return service.recordingStateStream;
});

/// Streams normalized amplitude values (0.0-1.0) during recording.
///
/// Used by the [AmplitudeWaveform] widget for real-time visualization.
final debugAmplitudeProvider = StreamProvider<double>((ref) {
  final service = ref.watch(debugRecordingServiceProvider);
  return service.amplitudeStream;
});

/// Ticks every second with the elapsed recording duration.
///
/// Only emits while recording is active. Returns [Stream.empty] when
/// not recording, loading, or in error state.
///
/// Follows the same pattern as [recordingElapsedProvider] in
/// live_recording_provider.dart.
final debugElapsedProvider = StreamProvider<Duration>((ref) {
  final recordingState = ref.watch(debugRecordingStateProvider);
  return recordingState.when(
    data: (isRecording) {
      if (!isRecording) return const Stream<Duration>.empty();
      final service = ref.read(debugRecordingServiceProvider);
      final startTime = service.startTime;
      if (startTime == null) return const Stream<Duration>.empty();
      return Stream.periodic(const Duration(seconds: 1), (_) {
        return DateTime.now().difference(startTime);
      });
    },
    loading: () => const Stream<Duration>.empty(),
    error: (_, __) => const Stream<Duration>.empty(),
  );
});
