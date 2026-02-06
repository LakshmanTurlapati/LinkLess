import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/encounter_model.dart';
import 'ble_proximity_service.dart';
import 'transcription_service.dart';
import 'api_client.dart';

/// Orchestrates the full encounter lifecycle:
/// 1. BLE detects a nearby LinkLess user
/// 2. After sustained proximity, creates an encounter on the backend
/// 3. Starts microphone recording and sends audio chunks for transcription
/// 4. When proximity is lost, stops recording and ends the encounter
/// 5. Optionally triggers AI summarization
class EncounterOrchestrator extends StateNotifier<EncounterOrchestratorState> {
  final BleProximityService _bleService;
  final TranscriptionService _transcriptionService;
  final ApiClient _apiClient;

  StreamSubscription<NearbyPeer>? _triggerSub;
  StreamSubscription<NearbyPeer>? _lostSub;

  /// Peers we've already triggered encounters for (prevent duplicates).
  final Set<String> _activeEncounterPeers = {};

  EncounterOrchestrator({
    required BleProximityService bleService,
    required TranscriptionService transcriptionService,
    required ApiClient apiClient,
  })  : _bleService = bleService,
        _transcriptionService = transcriptionService,
        _apiClient = apiClient,
        super(const EncounterOrchestratorState());

  /// Start listening for proximity events and orchestrating encounters.
  void start() {
    _triggerSub = _bleService.onProximityTriggered.listen(_onProximityTriggered);
    _lostSub = _bleService.onProximityLost.listen(_onProximityLost);
    state = state.copyWith(isActive: true);
  }

  /// Stop orchestrating encounters.
  void stop() {
    _triggerSub?.cancel();
    _lostSub?.cancel();
    state = state.copyWith(isActive: false);
  }

  Future<void> _onProximityTriggered(NearbyPeer peer) async {
    // Skip if we don't have the peer's user ID or already have an active encounter
    if (peer.userId == null) return;
    if (_activeEncounterPeers.contains(peer.userId)) return;

    _activeEncounterPeers.add(peer.userId!);

    try {
      // Create encounter on the backend
      final encounter = await _apiClient.createEncounter(
        peerId: peer.userId!,
        proximityDistance: peer.estimatedDistance,
      );

      if (encounter == null) {
        _activeEncounterPeers.remove(peer.userId);
        return;
      }

      state = state.copyWith(
        activeEncounter: encounter,
        activePeer: peer,
      );

      // Start recording and transcribing
      await _transcriptionService.startRecording(
        encounterId: encounter.id,
        peerId: peer.userId!,
      );
    } catch (e) {
      _activeEncounterPeers.remove(peer.userId);
      state = state.copyWith(error: 'Failed to start encounter: $e');
    }
  }

  Future<void> _onProximityLost(NearbyPeer peer) async {
    if (peer.userId == null) return;
    if (!_activeEncounterPeers.contains(peer.userId)) return;

    _activeEncounterPeers.remove(peer.userId);

    try {
      // Stop recording
      await _transcriptionService.stopRecording();

      // End the encounter on the backend
      if (state.activeEncounter != null) {
        await _apiClient.endEncounter(state.activeEncounter!.id);

        // Trigger async summarization
        _apiClient.summarizeEncounter(state.activeEncounter!.id);
      }

      state = state.copyWith(
        activeEncounter: null,
        activePeer: null,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to end encounter: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

class EncounterOrchestratorState {
  final bool isActive;
  final EncounterModel? activeEncounter;
  final NearbyPeer? activePeer;
  final String? error;

  const EncounterOrchestratorState({
    this.isActive = false,
    this.activeEncounter,
    this.activePeer,
    this.error,
  });

  EncounterOrchestratorState copyWith({
    bool? isActive,
    EncounterModel? activeEncounter,
    NearbyPeer? activePeer,
    String? error,
  }) {
    return EncounterOrchestratorState(
      isActive: isActive ?? this.isActive,
      activeEncounter: activeEncounter ?? this.activeEncounter,
      activePeer: activePeer ?? this.activePeer,
      error: error,
    );
  }
}

/// Provider for the encounter orchestrator.
final encounterOrchestratorProvider = StateNotifierProvider<
    EncounterOrchestrator, EncounterOrchestratorState>((ref) {
  final bleService = ref.watch(bleProximityServiceProvider.notifier);
  final transcriptionService =
      ref.watch(transcriptionServiceProvider.notifier);
  final apiClient = ref.watch(apiClientProvider);

  return EncounterOrchestrator(
    bleService: bleService,
    transcriptionService: transcriptionService,
    apiClient: apiClient,
  );
});
