import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/features/recording/data/services/audio_engine.dart';
import 'package:linkless/features/recording/data/services/gps_service.dart';
import 'package:linkless/features/recording/data/services/recording_service.dart';
import 'package:linkless/features/recording/domain/models/conversation_local.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';

/// Provides the AudioEngine instance.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = AudioEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Provides the GpsService instance.
final gpsServiceProvider = Provider<GpsService>((ref) {
  return GpsService();
});

/// Provides the RecordingService wired to BleManager's proximity events.
///
/// This is the critical integration point: the service is initialized with
/// the BleManager's proximity state machine event stream so that recording
/// starts/stops automatically on peer detection/loss.
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final audioEngine = ref.watch(audioEngineProvider);
  final gpsService = ref.watch(gpsServiceProvider);
  final conversationDao = ref.watch(conversationDaoProvider);

  final service = RecordingService(
    audioEngine: audioEngine,
    gpsService: gpsService,
    conversationDao: conversationDao,
  );

  // Wire the service to BleManager's proximity event stream.
  service.initialize(BleManager.instance.stateMachine.events);

  ref.onDispose(() => service.dispose());

  return service;
});

/// Streams the current RecordingState for UI consumption.
final recordingStateProvider = StreamProvider<RecordingState>((ref) {
  return ref.watch(recordingServiceProvider).stateStream;
});

/// Streams the list of all conversations as domain models.
final conversationListProvider = StreamProvider<List<ConversationLocal>>((ref) {
  final dao = ref.watch(conversationDaoProvider);
  return dao.watchAllConversations().map(
    (entries) => entries.map(ConversationLocal.fromEntry).toList(),
  );
});
