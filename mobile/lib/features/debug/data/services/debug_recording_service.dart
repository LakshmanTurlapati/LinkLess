import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/sync/data/services/sync_engine.dart';

/// Service for manual audio recording from the debug panel.
///
/// Unlike [RecordingService], this does not depend on BLE proximity events
/// or the identity chain. Recordings start on user tap, use a "debug_"
/// peerId prefix for identification, and are auto-uploaded via [SyncEngine]
/// after stopping.
///
/// Key differences from the production [RecordingService]:
/// - No BLE proximity trigger -- starts on demand
/// - No GATT exchange or profile fetch
/// - No foreground-initiated pattern guard
/// - peerId uses "debug_" prefix to distinguish from real conversations
/// - Creates a new [AudioRecorder] per recording session (per record
///   package lifecycle requirements)
class DebugRecordingService {
  final ConversationDao _conversationDao;
  final SyncEngine _syncEngine;

  AudioRecorder? _recorder;
  bool _isRecording = false;
  String? _activeConversationId;
  String? _activeFilePath;
  DateTime? _startTime;
  Timer? _maxDurationTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<bool> _stateController =
      StreamController<bool>.broadcast();

  /// Creates a [DebugRecordingService] with required dependencies.
  DebugRecordingService({
    required ConversationDao conversationDao,
    required SyncEngine syncEngine,
  })  : _conversationDao = conversationDao,
        _syncEngine = syncEngine;

  /// Whether a recording is currently active.
  bool get isRecording => _isRecording;

  /// The ID of the active conversation, or null if not recording.
  String? get activeConversationId => _activeConversationId;

  /// The timestamp when the current recording started, or null if idle.
  DateTime? get startTime => _startTime;

  /// Stream of normalized amplitude values (0.0-1.0) emitted at ~100ms
  /// intervals during recording. Used to drive the waveform visualization.
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Stream of recording state changes (true = recording, false = idle).
  Stream<bool> get recordingStateStream => _stateController.stream;

  /// Starts a new debug recording session.
  ///
  /// Creates a new [AudioRecorder] instance, verifies microphone permission,
  /// begins recording to an M4A file, starts amplitude monitoring, sets a
  /// 5-minute max duration timer, and inserts a conversation entry into the
  /// local database with a "debug_" peerId prefix.
  ///
  /// Returns the generated conversation ID.
  ///
  /// Throws [StateError] if already recording or if microphone permission
  /// is denied.
  Future<String> startRecording(String userId) async {
    if (_isRecording) {
      throw StateError('Already recording');
    }

    // Create a new AudioRecorder per session (per research pitfall #1)
    _recorder = AudioRecorder();

    final hasPermission = await _recorder!.hasPermission();
    if (!hasPermission) {
      await _recorder!.dispose();
      _recorder = null;
      throw StateError('Microphone permission denied');
    }

    final conversationId =
        'debug_${DateTime.now().millisecondsSinceEpoch}';

    final directory = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${directory.path}/recordings');
    await recordingsDir.create(recursive: true);

    final filePath =
        '${directory.path}/recordings/$conversationId.m4a';

    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: filePath,
    );

    _isRecording = true;
    _activeConversationId = conversationId;
    _activeFilePath = filePath;
    _startTime = DateTime.now();

    // Emit recording state
    if (!_stateController.isClosed) {
      _stateController.add(true);
    }

    // Subscribe to amplitude changes for waveform visualization.
    // Normalize dBFS (practical range -50 to 0) to 0.0-1.0.
    _amplitudeSubscription = _recorder!
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      final clamped = amp.current.clamp(-50.0, 0.0);
      final normalized = (clamped + 50.0) / 50.0;
      if (!_amplitudeController.isClosed) {
        _amplitudeController.add(normalized);
      }
    });

    // Enforce 5-minute max duration
    _maxDurationTimer = Timer(const Duration(minutes: 5), () {
      stopRecording();
    });

    // Insert conversation into local database with debug_ peerId prefix
    await _conversationDao.insertConversation(
      ConversationEntriesCompanion.insert(
        id: conversationId,
        peerId: 'debug_$userId',
        startedAt: _startTime!,
      ),
    );

    return conversationId;
  }

  /// Stops the current recording session.
  ///
  /// Cancels the max duration timer and amplitude subscription, stops the
  /// recorder, completes the conversation in the database with duration
  /// and file path, and triggers an upload via [SyncEngine.syncNow].
  ///
  /// Returns the audio file path, or null if not currently recording.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    final path = await _recorder!.stop();
    _recorder!.dispose();
    _recorder = null;

    final endedAt = DateTime.now();
    final duration = _startTime != null
        ? endedAt.difference(_startTime!).inSeconds
        : 0;

    // Complete conversation in database
    await _conversationDao.completeConversation(
      _activeConversationId!,
      audioFilePath: path ?? _activeFilePath!,
      endedAt: endedAt,
      durationSeconds: duration,
    );

    // Trigger upload
    await _syncEngine.syncNow();

    // Reset state
    final resultPath = path ?? _activeFilePath;
    _isRecording = false;
    _activeConversationId = null;
    _activeFilePath = null;
    _startTime = null;

    if (!_stateController.isClosed) {
      _stateController.add(false);
    }

    return resultPath;
  }

  /// Releases all resources held by this service.
  ///
  /// If a recording is active, stops it first (fire and forget).
  /// Closes both stream controllers.
  void dispose() {
    if (_isRecording) {
      // Fire and forget -- best effort cleanup
      stopRecording();
    }
    _maxDurationTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _amplitudeController.close();
    _stateController.close();
  }
}
