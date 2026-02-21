import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/ble/proximity_state_machine.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';
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
/// resolves peer identity via GATT exchange and profile API fetch, then
/// starts/stops audio recording, captures GPS, and persists metadata to Drift.
///
/// Implements the "foreground-initiated, background-continued" pattern:
/// - Recording starts ONLY when the app is in the foreground.
/// - Once started, recording continues if the app moves to background.
/// - Recording stops on peer lost regardless of foreground/background state.
///
/// Recording is gated behind a successful identity chain:
/// 1. Proximity detected -> enter PENDING state (overlay shows shimmer)
/// 2. GATT exchange resolves device UUID to real user ID (1 initial + 2 retries)
/// 3. Profile API fetch retrieves peer's name, photo, initials
/// 4. Both succeed -> enter RECORDING state (overlay shows profile)
/// 5. Any failure -> return to IDLE (no recording created)
///
/// GPS capture runs concurrently with recording start so it never blocks
/// the audio engine from beginning capture.
class RecordingService with WidgetsBindingObserver {
  final AudioEngine _audioEngine;
  final GpsService _gpsService;
  final ConversationDao _conversationDao;
  final Dio _dio;
  final PeerInitialsResolver? _peerInitialsResolver;

  static const _maxRecordingDuration = Duration(minutes: 3);
  static const _identityChainTimeout = Duration(seconds: 15);

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

  /// The resolved peer profile (available after identity chain completes).
  UserProfile? _activePeerProfile;

  /// Completer used to cancel the identity chain when peer is lost during
  /// the pending state.
  Completer<void>? _identityChainCompleter;

  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();

  final StreamController<String?> _peerIdController =
      StreamController<String?>.broadcast();

  final StreamController<UserProfile?> _peerProfileController =
      StreamController<UserProfile?>.broadcast();

  /// Creates a RecordingService with the required dependencies.
  RecordingService({
    required AudioEngine audioEngine,
    required GpsService gpsService,
    required ConversationDao conversationDao,
    required Dio dio,
    PeerInitialsResolver? peerInitialsResolver,
  })  : _audioEngine = audioEngine,
        _gpsService = gpsService,
        _conversationDao = conversationDao,
        _dio = dio,
        _peerInitialsResolver = peerInitialsResolver;

  /// The current recording state.
  RecordingState get state => _state;

  /// Stream of recording state changes for UI observation.
  Stream<RecordingState> get stateStream => _stateController.stream;

  /// Stream of active peer ID changes for reactive UI consumption.
  Stream<String?> get peerIdStream => _peerIdController.stream;

  /// Stream of peer profile changes for reactive UI consumption.
  Stream<UserProfile?> get peerProfileStream => _peerProfileController.stream;

  /// Whether a recording is currently active.
  bool get isRecording => _state == RecordingState.recording;

  /// The peer ID of the active recording, or null if not recording.
  ///
  /// Initially this is the raw BLE device UUID. After GATT exchange resolves,
  /// it becomes the real user ID. Check [isPeerIdResolved] to know which.
  String? get activePeerId => _activePeerId;

  /// Whether the active peer ID has been resolved to a real user ID via GATT exchange.
  bool get isPeerIdResolved => _peerIdResolved;

  /// The resolved peer profile, or null if not yet available.
  UserProfile? get activePeerProfile => _activePeerProfile;

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
        _onPeerDetected(event.peerId);
      case ProximityEventType.lost:
        _onPeerLost(event.peerId);
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
    if (_activeConversationId == null && _state != RecordingState.pending) {
      debugPrint(
        '[RecordingService] Exchange event ignored: no active conversation '
        'and not pending (peerId=${event.peerId}, deviceId=${event.deviceId})',
      );
      return;
    }

    // Already resolved to this peer -- ensure the flag is set and ALWAYS
    // emit on _peerIdController so downstream providers rebuild (Bug 2 fix).
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
      // Bug 2 fix: ALWAYS emit on _peerIdController so activePeerIdProvider
      // rebuilds even when the value hasn't changed (forces downstream
      // providers like activePeerProfileProvider to re-evaluate).
      if (!_peerIdController.isClosed) {
        _peerIdController.add(event.peerId);
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

    // Only update DB if we have an active conversation (recording state)
    if (_activeConversationId != null) {
      _conversationDao.updatePeerId(_activeConversationId!, event.peerId);
    }

    if (!_peerIdController.isClosed) {
      _peerIdController.add(event.peerId);
    }

    // Re-emit current state so UI providers rebuild with the resolved peer ID.
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  // ---------------------------------------------------------------------------
  // Gated Detection Flow
  // ---------------------------------------------------------------------------

  /// Called when proximity detection fires. Enters the pending state and
  /// kicks off the identity resolution chain (GATT exchange + profile fetch).
  /// Recording only starts if the entire chain succeeds.
  Future<void> _onPeerDetected(String peerId) async {
    // Guard: already in a non-idle state (pending or recording)
    if (_state != RecordingState.idle) return;

    // Guard: foreground-initiated pattern -- do not start from background
    if (!_isInForeground) {
      debugPrint(
        '[RecordingService] Skipping recording start: app is in background '
        '(foreground-initiated pattern)',
      );
      return;
    }

    _originalDeviceId = peerId;
    _activePeerId = peerId;
    if (!_peerIdController.isClosed) {
      _peerIdController.add(peerId);
    }

    // Enter pending state -- overlay shows shimmer immediately
    _setState(RecordingState.pending);
    _identityChainCompleter = Completer<void>();

    debugPrint('[RecordingService] Peer detected, entering pending state: $peerId');

    try {
      await _resolveIdentityChain(peerId);
    } catch (e) {
      // Identity chain failed (timeout, GATT failure, profile fetch error).
      // Skip this encounter entirely -- no recording created.
      debugPrint(
        '[RecordingService] Identity chain failed for $peerId: $e '
        '-- skipping encounter entirely, no recording',
      );

      // Capture peer IDs before _clearActiveState nulls them.
      final resetPeerId = _activePeerId;
      final resetDeviceId = _originalDeviceId;

      _clearActiveState();
      _setState(RecordingState.idle);

      // Schedule a delayed peer reset so the state machine drops this peer
      // and re-detects it on the next BLE scan cycle. The 3s delay prevents
      // an immediate retry storm (next scan cycle is ~5s).
      Future.delayed(const Duration(seconds: 3), () {
        if (resetPeerId != null) {
          BleManager.instance.resetPeerTracking(resetPeerId);
        }
        if (resetDeviceId != null && resetDeviceId != resetPeerId) {
          BleManager.instance.resetPeerTracking(resetDeviceId);
        }
      });
    }
  }

  /// Resolves the peer identity via GATT exchange and profile API fetch.
  ///
  /// The entire chain has a 15-second total timeout. GATT exchange uses
  /// 1 initial attempt + 2 retries = 3 total attempts with increasing
  /// timeouts (3s, 4s, 5s). If all GATT attempts fail, the encounter is
  /// skipped entirely with no recording.
  ///
  /// If the profile API fetch fails, the encounter is also skipped entirely
  /// (no fallback to partial identity, per user decision).
  Future<void> _resolveIdentityChain(String peerId) async {
    await Future.any([
      _runIdentityChain(peerId),
      // If peer is lost during the chain, _identityChainCompleter is completed
      // and this future resolves, causing the chain to be cancelled.
      _identityChainCompleter!.future.then((_) {
        throw StateError('Peer lost during identity chain -- aborting');
      }),
    ]).timeout(_identityChainTimeout, onTimeout: () {
      throw TimeoutException(
        'Identity chain timed out after ${_identityChainTimeout.inSeconds}s',
      );
    });
  }

  /// The actual identity resolution logic, separated for cancellation support.
  Future<void> _runIdentityChain(String peerId) async {
    // Step 1: Resolve user ID via GATT exchange
    final resolvedUserId = await _resolveGattIdentity(peerId);

    // Check if peer was lost during GATT resolution
    if (_identityChainCompleter?.isCompleted == true) {
      throw StateError('Peer lost after GATT resolution -- aborting');
    }

    debugPrint(
      '[RecordingService] GATT identity resolved: $peerId -> $resolvedUserId',
    );

    // Step 2: Fetch profile via API
    final profile = await _fetchPeerProfile(resolvedUserId);

    // Check if peer was lost during profile fetch
    if (_identityChainCompleter?.isCompleted == true) {
      throw StateError('Peer lost after profile fetch -- aborting');
    }

    debugPrint(
      '[RecordingService] Profile fetched for $resolvedUserId: '
      '${profile.displayName ?? profile.initials ?? "(no name)"}',
    );

    // Step 3: Store profile and start recording
    _activePeerId = resolvedUserId;
    _peerIdResolved = true;
    _activePeerProfile = profile;
    if (!_peerProfileController.isClosed) {
      _peerProfileController.add(profile);
    }
    if (!_peerIdController.isClosed) {
      _peerIdController.add(resolvedUserId);
    }

    await _startGatedRecording(resolvedUserId, profile);
  }

  /// Resolves the real user ID from a BLE device UUID via GATT exchange.
  ///
  /// Checks three scenarios:
  /// 1. Already resolved (peerId is in deviceToUserIdMap values -- central-before-detection)
  /// 2. Mapped in deviceToUserIdMap (deviceId -> userId lookup)
  /// 3. Wait for exchange event from proximityStream with retry
  Future<String> _resolveGattIdentity(String peerId) async {
    // Check if already resolved: peerId is already a real user ID
    final deviceMap = BleManager.instance.deviceToUserIdMap;
    if (deviceMap.values.contains(peerId)) {
      debugPrint(
        '[RecordingService] Peer ID already a known user ID: $peerId',
      );
      return peerId;
    }

    // Check if there's a mapping for this device
    final mappedUserId = deviceMap[peerId];
    if (mappedUserId != null) {
      debugPrint(
        '[RecordingService] Peer ID mapped via deviceToUserIdMap: '
        '$peerId -> $mappedUserId',
      );
      return mappedUserId;
    }

    // Wait for GATT exchange event with retry policy:
    // 1 initial attempt + 2 retries = 3 total attempts
    const maxAttempts = 3;
    final timeouts = [
      const Duration(seconds: 3),
      const Duration(seconds: 4),
      const Duration(seconds: 5),
    ];

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Check if peer was lost between retry attempts
      if (_identityChainCompleter?.isCompleted == true) {
        throw StateError('Peer lost during GATT retry -- aborting');
      }

      debugPrint(
        '[RecordingService] GATT attempt ${attempt + 1}/$maxAttempts '
        'for $peerId (timeout: ${timeouts[attempt].inSeconds}s)...',
      );

      try {
        final event = await BleManager.instance.proximityStream
            .where((e) =>
                e.isExchanged &&
                e.peerId.isNotEmpty &&
                (e.deviceId == peerId ||
                    e.deviceId == _originalDeviceId ||
                    e.deviceId.isEmpty)) // Peripheral path
            .first
            .timeout(timeouts[attempt]);

        debugPrint(
          '[RecordingService] GATT exchange succeeded on attempt '
          '${attempt + 1}: peerId=${event.peerId}',
        );
        return event.peerId;
      } on TimeoutException {
        debugPrint(
          '[RecordingService] GATT wait timeout '
          '(attempt ${attempt + 1}/$maxAttempts)',
        );
        if (attempt == maxAttempts - 1) {
          debugPrint(
            '[RecordingService] GATT exchange failed after $maxAttempts '
            'attempts for $peerId -- skipping encounter entirely, no recording',
          );
          rethrow;
        }
        // Check device map again in case it resolved via a different path
        // between attempts
        final recheckMap = BleManager.instance.deviceToUserIdMap;
        if (recheckMap.values.contains(peerId)) return peerId;
        final recheckMapped = recheckMap[peerId];
        if (recheckMapped != null) return recheckMapped;
      }
    }

    // Should not reach here, but just in case
    throw TimeoutException(
      'GATT exchange failed after $maxAttempts attempts for $peerId',
    );
  }

  /// Fetches the peer's profile from the backend API with retry.
  ///
  /// Makes up to 2 attempts (initial + 1 retry after 1s delay). On each
  /// failure, logs status code, URL, response body, and full error for
  /// diagnostics. Checks [_identityChainCompleter] during the retry delay
  /// to abort early if the peer is lost. If both attempts fail, the
  /// exception propagates to the caller which skips the encounter entirely.
  /// Bug 2's peer reset then handles scheduling a fresh detection.
  Future<UserProfile> _fetchPeerProfile(String userId) async {
    const maxAttempts = 2;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint(
          '[RecordingService] Fetching profile for user: $userId '
          '(attempt $attempt/$maxAttempts)',
        );
        final response = await _dio.get('/profile/$userId');
        return UserProfile.fromJson(response.data as Map<String, dynamic>);
      } on DioException catch (e) {
        debugPrint(
          '[RecordingService] Profile fetch failed '
          '(attempt $attempt/$maxAttempts): '
          'status=${e.response?.statusCode}, '
          'url=${e.requestOptions.uri}, '
          'body=${e.response?.data}, '
          'error=$e',
        );
        if (attempt < maxAttempts) {
          // Wait before retry, but abort if peer is lost
          await Future.delayed(const Duration(seconds: 1));
          if (_identityChainCompleter?.isCompleted == true) {
            throw StateError('Peer lost during profile fetch retry -- aborting');
          }
          continue;
        }
        rethrow;
      } catch (e) {
        debugPrint(
          '[RecordingService] Profile fetch unexpected error '
          '(attempt $attempt/$maxAttempts): $e',
        );
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
          if (_identityChainCompleter?.isCompleted == true) {
            throw StateError('Peer lost during profile fetch retry -- aborting');
          }
          continue;
        }
        rethrow;
      }
    }

    // Should not reach here, but satisfy return type
    throw StateError('Profile fetch exhausted all attempts for $userId');
  }

  // ---------------------------------------------------------------------------
  // Recording Start (gated)
  // ---------------------------------------------------------------------------

  /// Starts the actual audio recording after identity chain has succeeded.
  ///
  /// This is only called after GATT exchange AND profile fetch both complete.
  /// The resolved userId and profile are guaranteed available at this point.
  Future<void> _startGatedRecording(String userId, UserProfile profile) async {
    try {
      final now = DateTime.now();
      final conversationId =
          'conv_${now.millisecondsSinceEpoch}_${userId.hashCode.abs()}';

      _activeConversationId = conversationId;
      _recordingStartTime = now;
      _setState(RecordingState.recording);

      // Show notification with initials from the resolved profile
      NotificationService.instance.showRecordingNotification(
        initials: profile.initials ?? '...',
      );

      // Start recording FIRST -- do not wait for GPS
      await _audioEngine.startRecording(conversationId);

      // Hard stop after 3 minutes
      _maxDurationTimer = Timer(_maxRecordingDuration, () {
        debugPrint('[RecordingService] Max duration reached (3 min) -- stopping');
        _onPeerLost(userId);
      });

      // Fire GPS concurrently -- do not block recording
      final gpsFuture = _gpsService.getCurrentPosition();

      // Insert initial conversation record into database with the resolved
      // userId (not raw device UUID)
      await _conversationDao.insertConversation(
        ConversationEntriesCompanion.insert(
          id: conversationId,
          peerId: userId,
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
        '(peer: $userId, gps: ${position != null})',
      );
    } catch (e) {
      debugPrint('[RecordingService] Failed to start recording: $e');
      NotificationService.instance.dismissRecordingNotification();
      _setState(RecordingState.error);
      _clearActiveState();
    }
  }

  // ---------------------------------------------------------------------------
  // Peer Lost / Stop Recording
  // ---------------------------------------------------------------------------

  /// Handles peer-lost events for both pending and recording states.
  ///
  /// - If in pending state: cancels the identity chain by completing the
  ///   completer, clears active state, returns to idle. Audio was never started.
  /// - If in recording state: stops audio, completes conversation in DB,
  ///   clears active state, returns to idle.
  Future<void> _onPeerLost(String peerId) async {
    // Match via both active peer ID and original device ID
    if (_activePeerId != peerId && _originalDeviceId != peerId) return;

    if (_state == RecordingState.pending) {
      debugPrint(
        '[RecordingService] Peer lost during pending state: $peerId '
        '-- cancelling identity chain',
      );
      // Cancel the identity chain
      if (_identityChainCompleter != null &&
          !_identityChainCompleter!.isCompleted) {
        _identityChainCompleter!.complete();
      }
      _clearActiveState();
      _setState(RecordingState.idle);
      return;
    }

    if (_state != RecordingState.recording) return;

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
    if (state == AppLifecycleState.detached) {
      _stopRecordingOnTermination();
    }
  }

  /// Emergency stop when the app is being terminated (detached state).
  ///
  /// Best-effort: the process may die before all async operations complete.
  /// The startup cleanup (Fix 3) handles any incomplete conversations.
  void _stopRecordingOnTermination() {
    if (_state == RecordingState.idle) return;

    debugPrint(
      '[RecordingService] App detached during ${_state.name} '
      '-- emergency stop',
    );

    if (_state == RecordingState.recording) {
      // Best-effort: try to finalize audio and DB record
      final conversationId = _activeConversationId;
      final startTime = _recordingStartTime;
      _audioEngine.stopRecording().then((filePath) {
        if (conversationId != null) {
          final endedAt = DateTime.now();
          final durationSeconds = startTime != null
              ? endedAt.difference(startTime).inSeconds
              : 0;
          _conversationDao.completeConversation(
            conversationId,
            audioFilePath: filePath ?? '',
            endedAt: endedAt,
            durationSeconds: durationSeconds,
          );
        }
      }).catchError((_) {});
      NotificationService.instance.dismissRecordingNotification();
    }

    _clearActiveState();
    _setState(RecordingState.idle);
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
    _activePeerProfile = null;
    if (!_peerIdController.isClosed) {
      _peerIdController.add(null);
    }
    if (!_peerProfileController.isClosed) {
      _peerProfileController.add(null);
    }
    // Complete identity chain completer if still pending
    if (_identityChainCompleter != null &&
        !_identityChainCompleter!.isCompleted) {
      _identityChainCompleter!.complete();
    }
    _identityChainCompleter = null;
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
    await _peerProfileController.close();
    await _audioEngine.dispose();
  }
}
