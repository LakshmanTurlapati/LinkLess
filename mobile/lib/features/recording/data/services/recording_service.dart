import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import 'package:linkless/ble/proximity_state_machine.dart';
import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/recording/data/services/audio_engine.dart';
import 'package:linkless/features/recording/data/services/audio_session_config.dart';
import 'package:linkless/features/recording/data/services/gps_service.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';

/// Orchestrates the full recording lifecycle: listens to proximity events,
/// starts/stops audio recording, captures GPS, and persists metadata to Drift.
///
/// Implements the "foreground-initiated, background-continued" pattern:
/// - Recording starts ONLY when the app is in the foreground.
/// - Once started, recording continues if the app moves to background.
/// - Recording stops on peer lost regardless of foreground/background state.
///
/// GPS capture runs concurrently with recording start so it never blocks
/// the audio engine from beginning capture.
class RecordingService with WidgetsBindingObserver {
  final AudioEngine _audioEngine;
  final GpsService _gpsService;
  final ConversationDao _conversationDao;

  StreamSubscription<ProximityEvent>? _proximitySubscription;
  String? _activeConversationId;
  String? _activePeerId;
  DateTime? _recordingStartTime;
  RecordingState _state = RecordingState.idle;
  bool _isInForeground = true;

  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();

  /// Creates a RecordingService with the required dependencies.
  RecordingService({
    required AudioEngine audioEngine,
    required GpsService gpsService,
    required ConversationDao conversationDao,
  })  : _audioEngine = audioEngine,
        _gpsService = gpsService,
        _conversationDao = conversationDao;

  /// The current recording state.
  RecordingState get state => _state;

  /// Stream of recording state changes for UI observation.
  Stream<RecordingState> get stateStream => _stateController.stream;

  /// Whether a recording is currently active.
  bool get isRecording => _state == RecordingState.recording;

  /// The ID of the active conversation, or null if not recording.
  String? get activeConversationId => _activeConversationId;

  /// Initializes the service by configuring the audio session, subscribing
  /// to proximity events, and registering as a lifecycle observer.
  ///
  /// [proximityEvents] should be [BleManager.instance.stateMachine.events]
  /// or [BleManager.instance.proximityStateStream].
  Future<void> initialize(Stream<ProximityEvent> proximityEvents) async {
    await configureAudioSession();
    _proximitySubscription = proximityEvents.listen(_onProximityEvent);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onProximityEvent(ProximityEvent event) {
    switch (event.type) {
      case ProximityEventType.detected:
        _startRecording(event.peerId);
      case ProximityEventType.lost:
        _stopRecording(event.peerId);
    }
  }

  Future<void> _startRecording(String peerId) async {
    // Guard: already recording
    if (isRecording) return;

    // Guard: foreground-initiated pattern -- do not start from background
    if (!_isInForeground) {
      debugPrint(
        '[RecordingService] Skipping recording start: app is in background '
        '(foreground-initiated pattern)',
      );
      return;
    }

    try {
      final now = DateTime.now();
      final conversationId =
          'conv_${now.millisecondsSinceEpoch}_${peerId.hashCode.abs()}';

      _activeConversationId = conversationId;
      _activePeerId = peerId;
      _recordingStartTime = now;
      _setState(RecordingState.recording);

      // Start recording FIRST -- do not wait for GPS
      await _audioEngine.startRecording(conversationId);

      // Fire GPS concurrently -- do not block recording
      final gpsFuture = _gpsService.getCurrentPosition();

      // Insert initial conversation record into database
      await _conversationDao.insertConversation(
        ConversationEntriesCompanion.insert(
          id: conversationId,
          peerId: peerId,
          startedAt: now,
        ),
      );

      // Await GPS result and update conversation with coordinates
      final position = await gpsFuture;
      if (position != null) {
        await (_conversationDao.update(_conversationDao.conversationEntries)
              ..where((t) => t.id.equals(conversationId)))
            .write(
          ConversationEntriesCompanion(
            latitude: Value(position.latitude),
            longitude: Value(position.longitude),
          ),
        );
      }

      debugPrint(
        '[RecordingService] Recording started: $conversationId '
        '(peer: $peerId, gps: ${position != null})',
      );
    } catch (e) {
      debugPrint('[RecordingService] Failed to start recording: $e');
      _setState(RecordingState.error);
      _clearActiveState();
    }
  }

  Future<void> _stopRecording(String peerId) async {
    // Guard: not recording or different peer
    if (!isRecording) return;
    if (_activePeerId != peerId) return;

    try {
      final filePath = await _audioEngine.stopRecording();
      final endedAt = DateTime.now();
      final durationSeconds = _recordingStartTime != null
          ? endedAt.difference(_recordingStartTime!).inSeconds
          : 0;

      if (_activeConversationId != null) {
        await _conversationDao.completeConversation(
          _activeConversationId!,
          audioFilePath: filePath ?? '',
          endedAt: endedAt,
          durationSeconds: durationSeconds,
        );
      }

      debugPrint(
        '[RecordingService] Recording stopped: $_activeConversationId '
        '(duration: ${durationSeconds}s)',
      );

      _clearActiveState();
      _setState(RecordingState.idle);
    } catch (e) {
      debugPrint('[RecordingService] Failed to stop recording: $e');
      _setState(RecordingState.error);
      _clearActiveState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;
  }

  void _setState(RecordingState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void _clearActiveState() {
    _activeConversationId = null;
    _activePeerId = null;
    _recordingStartTime = null;
  }

  /// Releases all resources: cancels proximity subscription, removes
  /// lifecycle observer, closes state stream, and disposes audio engine.
  Future<void> dispose() async {
    await _proximitySubscription?.cancel();
    _proximitySubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    await _stateController.close();
    await _audioEngine.dispose();
  }
}
