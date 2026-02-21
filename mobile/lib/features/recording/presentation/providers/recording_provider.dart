import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';
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
///
/// The service receives an authenticated Dio instance for fetching peer
/// profiles as part of the gated identity chain (GATT exchange + profile
/// fetch must both succeed before recording starts).
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final audioEngine = ref.watch(audioEngineProvider);
  final gpsService = ref.watch(gpsServiceProvider);
  final conversationDao = ref.watch(conversationDaoProvider);
  final dio = ref.watch(authenticatedDioProvider);

  final service = RecordingService(
    audioEngine: audioEngine,
    gpsService: gpsService,
    conversationDao: conversationDao,
    dio: dio,
  );

  // Wire the service to BleManager's proximity event stream and exchange
  // stream so peer IDs are resolved from device UUIDs to real user IDs.
  service.initialize(
    BleManager.instance.stateMachine.events,
    exchangeEvents: BleManager.instance.proximityStream,
  );

  ref.onDispose(() => service.dispose());

  return service;
});

/// Streams the current RecordingState for UI consumption.
final recordingStateProvider = StreamProvider<RecordingState>((ref) {
  return ref.watch(recordingServiceProvider).stateStream;
});

/// Streams the active peer ID for reactive UI consumption.
///
/// Directly watches RecordingService.peerIdStream, which emits:
/// - The raw BLE device UUID when peer is detected (pending state)
/// - The resolved real user ID when GATT exchange completes
/// - null when recording stops or returns to idle
///
/// This is more reliable than the previous approach of re-emitting the
/// recording state and reading activePeerId synchronously, because it uses
/// a dedicated stream that emits on every peer ID change.
final activePeerIdProvider = StreamProvider<String?>((ref) {
  final service = ref.watch(recordingServiceProvider);
  return service.peerIdStream;
});

/// Whether the active peer ID has been resolved to a real user ID (not a
/// raw BLE device UUID). Rebuilds whenever recording state changes.
///
/// This is exposed as a separate provider for backwards compatibility.
/// With the gated identity chain, the profile is fetched before recording
/// starts, so this flag is less critical than before.
final isPeerIdResolvedProvider = Provider<bool>((ref) {
  // Watch both recording state and peer ID to trigger rebuilds.
  ref.watch(recordingStateProvider);
  ref.watch(activePeerIdProvider);
  return ref.read(recordingServiceProvider).isPeerIdResolved;
});

/// Streams the active peer's profile from RecordingService.
///
/// The RecordingService fetches the profile as part of the identity chain
/// (during pending state) and emits it on its peerProfileStream. This
/// provider exposes that stream for UI consumption.
final activePeerProfileStreamProvider = StreamProvider<UserProfile?>((ref) {
  return ref.watch(recordingServiceProvider).peerProfileStream;
});

/// Provides the active peer's profile synchronously.
///
/// Reads the profile from RecordingService.activePeerProfile and rebuilds
/// when either recording state or peer profile stream changes. This replaces
/// the old FutureProvider that made a separate API call -- the service now
/// handles the profile fetch internally as part of the gated identity chain.
///
/// During pending state: returns null (profile not yet fetched).
/// During recording state: returns the resolved UserProfile.
/// During idle/error: returns null.
final activePeerProfileProvider = Provider<UserProfile?>((ref) {
  // Watch recording state and profile stream to trigger rebuilds when either
  // the state transitions or a new profile is emitted.
  ref.watch(recordingStateProvider);
  ref.watch(activePeerProfileStreamProvider);
  return ref.read(recordingServiceProvider).activePeerProfile;
});

/// Streams the list of all conversations as domain models.
final conversationListProvider = StreamProvider<List<ConversationLocal>>((ref) {
  final dao = ref.watch(conversationDaoProvider);
  return dao.watchAllConversations().map(
    (entries) => entries.map(ConversationLocal.fromEntry).toList(),
  );
});
