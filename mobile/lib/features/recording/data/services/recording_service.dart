import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/ble/proximity_state_machine.dart';
import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/recording/data/services/audio_engine.dart';
import 'package:linkless/features/recording/data/services/audio_session_config.dart';
import 'package:linkless/features/recording/data/services/gps_service.dart';
import 'package:linkless/core/services/notification_service.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';

/// Resolves a BLE peer device ID to the peer's display initials.
typedef PeerInitialsResolver = Future<String?> Function(String peerId);

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
  final PeerInitialsResolver? _peerInitialsResolver;

  static const _maxRecordingDuration = Duration(minutes: 3);

  StreamSubscription<ProximityEvent>? _proximitySubscription;
  StreamSubscription<BleProximityEvent>? _exchangeSubscription;
  Timer? _maxDurationTimer;
  String? _activeConversationId;
  String? _activePeerId;
  String? _originalDeviceId;
  DateTime? _recordingStartTime;
  RecordingState _state = RecordingState.idle;
  bool _isInForeground = true;
  bool _peerIdResolved = false;

  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();

  final StreamController<String?> _peerIdController =
      StreamController<String?>.broadcast();

  /// Creates a RecordingService with the required dependencies.
  RecordingService({
    required AudioEngine audioEngine,
    required GpsService gpsService,
    required ConversationDao conversationDao,
    PeerInitialsResolver? peerInitialsResolver,
  })  : _audioEngine = audioEngine,
        _gpsService = gpsService,
        _conversationDao = conversationDao,
        _peerInitialsResolver = peerInitialsResolver;

  /// The current recording state.
  RecordingState get state => _state;

  /// Stream of recording state changes for UI observation.
  Stream<RecordingState> get stateStream => _stateController.stream;

  /// Stream of active peer ID changes for reactive UI consumption.
  Stream<String?> get peerIdStream => _peerIdController.stream;

  /// Whether a recording is currently active.
  bool get isRecording => _state == RecordingState.recording;

  /// The peer ID of the active recording, or null if not recording.
  ///
  /// Initially this is the raw BLE device UUID. After GATT exchange resolves,
  /// it becomes the real user ID. Check [isPeerIdResolved] to know which.
  String? get activePeerId => _activePeerId;

  /// Whether the active peer ID has been resolved to a real user ID via GATT exchange.
  bool get isPeerIdResolved => _peerIdResolved;

  /// The timestamp when the current recording started, or null if not recording.
  DateTime? get recordingStartTime => _recordingStartTime;

  /// The ID of the active conversation, or null if not recording.
  String? get activeConversationId => _activeConversationId;

  /// Initializes the service by configuring the audio session, subscribing
  /// to proximity events, and registering as a lifecycle observer.
  ///
  /// [proximityEvents] should be [BleManager.instance.stateMachine.events]
  /// or [BleManager.instance.proximityStateStream].
  ///
  /// [exchangeEvents] is an optional stream of BLE proximity events used to
  /// resolve device IDs to real user IDs during an active recording.
  Future<void> initialize(
    Stream<ProximityEvent> proximityEvents, {
    Stream<BleProximityEvent>? exchangeEvents,
  }) async {
    // Subscribe to streams FIRST (synchronously) before any async gap.
    // These are broadcast streams that don't buffer -- if we subscribe after
    // an await, we risk missing events that fire during the async gap.
    _proximitySubscription = proximityEvents.listen(_onProximityEvent);
    _exchangeSubscription = exchangeEvents?.listen(_onExchangeResolved);
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[RecordingService] Initialized (streams subscribed)');

    try {
      await configureAudioSession();
    } catch (e) {
      debugPrint('[RecordingService] Audio session config failed (non-fatal): $e');
    }
  }

  void _onProximityEvent(ProximityEvent event) {
    debugPrint('[RecordingService] Proximity event: ${event.type} peer=${event.peerId}');
    switch (event.type) {
      case ProximityEventType.detected:
        _startRecording(event.peerId);
      case ProximityEventType.lost:
        _stopRecording(event.peerId);
    }
  }

  /// Called when a GATT exchange resolves a device ID to a real user ID.
  ///
  /// If we have an active recording whose peerId matches the raw deviceId
  /// (or the original device ID from recording start), update both the
  /// in-memory tracking and the database record so the conversation is
  /// attributed to the real user.
  ///
  /// Handles three exchange paths:
  /// - Central exchange: event.deviceId matches _activePeerId (raw BLE UUID)
  /// - Peripheral exchange: event.deviceId is empty, matched via _originalDeviceId
  /// - Late resolution: _activePeerId already resolved but _originalDeviceId still matches
  void _onExchangeResolved(BleProximityEvent event) {
    if (!event.isExchanged) return;
    if (event.peerId.isEmpty) return;
    if (_activeConversationId == null) {
      debugPrint(
        '[RecordingService] Exchange event ignored: no active conversation '
        '(peerId=${event.peerId}, deviceId=${event.deviceId})',
      );
      return;
    }

    // Already resolved to this peer -- just ensure the flag is set.
    // This handles the case where updatePeerId ran in the state machine
    // before the detected event, so _activePeerId was already the real
    // user ID when _startRecording was called.
    if (_activePeerId == event.peerId) {
      if (!_peerIdResolved) {
        debugPrint(
          '[RecordingService] Peer already matched, setting resolved flag '
          '(peerId=${event.peerId})',
        );
        _peerIdResolved = true;
        // Re-emit state so UI providers pick up the resolved flag.
        if (!_stateController.isClosed) {
          _stateController.add(_state);
        }
      }
      return;
    }

    // Match via device ID (Central exchange path) or original device ID
    // (Peripheral exchange path where event.deviceId is empty, or case
    // where state machine updatePeerId ran before detection).
    final matchesActive = event.deviceId.isNotEmpty &&
        (_activePeerId == event.deviceId || _originalDeviceId == event.deviceId);
    final matchesPeripheral = event.deviceId.isEmpty && _activePeerId != null;

    if (!matchesActive && !matchesPeripheral) {
      debugPrint(
        '[RecordingService] Exchange event unmatched: '
        'activePeerId=$_activePeerId, originalDeviceId=$_originalDeviceId, '
        'event.peerId=${event.peerId}, event.deviceId=${event.deviceId}',
      );
      return;
    }

    debugPrint(
      '[RecordingService] Resolving peerId: '
      '${event.deviceId.isNotEmpty ? event.deviceId : "(peripheral)"} '
      '-> ${event.peerId}',
    );

    _activePeerId = event.peerId;
    _peerIdResolved = true;
    _conversationDao.updatePeerId(_activeConversationId!, event.peerId);

    if (!_peerIdController.isClosed) {
      _peerIdController.add(event.peerId);
    }

    // Re-emit current state so UI providers rebuild with the resolved peer ID.
    if (!_stateController.isClosed) {
      _stateController.add(_state);
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
      _originalDeviceId = peerId;

      // Check if the peer ID was already resolved to a real user ID by the
      // state machine (updatePeerId ran before detection). In that case,
      // the peerId from the ProximityEvent IS the real user ID.
      final exchangedUserIds = BleManager.instance.deviceToUserIdMap.values;
      if (exchangedUserIds.contains(peerId)) {
        _peerIdResolved = true;
        debugPrint(
          '[RecordingService] Peer ID already resolved at recording start: $peerId',
        );
      } else {
        debugPrint(
          '[RecordingService] Peer ID not yet resolved (raw device UUID): $peerId',
        );
      }
      _recordingStartTime = now;
      if (!_peerIdController.isClosed) {
        _peerIdController.add(peerId);
      }
      _setState(RecordingState.recording);
      NotificationService.instance.showRecordingNotification();

      // Async: resolve initials and update notification (non-blocking)
      _peerInitialsResolver?.call(peerId).then((initials) {
        if (initials != null && isRecording) {
          NotificationService.instance.showRecordingNotification(initials: initials);
        }
      });

      // Start recording FIRST -- do not wait for GPS
      await _audioEngine.startRecording(conversationId);

      // Hard stop after 3 minutes
      _maxDurationTimer = Timer(_maxRecordingDuration, () {
        debugPrint('[RecordingService] Max duration reached (3 min) -- stopping');
        _stopRecording(peerId);
      });

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
      NotificationService.instance.dismissRecordingNotification();
      _setState(RecordingState.error);
      _clearActiveState();
    }
  }

  Future<void> _stopRecording(String peerId) async {
    // Guard: not recording or different peer
    if (!isRecording) return;
    if (_activePeerId != peerId && _originalDeviceId != peerId) return;

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
      NotificationService.instance.dismissRecordingNotification();
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
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _activeConversationId = null;
    _activePeerId = null;
    _peerIdResolved = false;
    if (!_peerIdController.isClosed) {
      _peerIdController.add(null);
    }
    _originalDeviceId = null;
    _recordingStartTime = null;
  }

  /// Releases all resources: cancels proximity subscription, removes
  /// lifecycle observer, closes state stream, and disposes audio engine.
  Future<void> dispose() async {
    await _proximitySubscription?.cancel();
    _proximitySubscription = null;
    await _exchangeSubscription?.cancel();
    _exchangeSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    await _stateController.close();
    await _peerIdController.close();
    await _audioEngine.dispose();
  }
}
