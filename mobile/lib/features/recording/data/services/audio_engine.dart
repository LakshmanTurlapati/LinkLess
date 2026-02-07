import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thrown when the user has denied microphone permission and recording
/// cannot proceed.
class RecordingPermissionDeniedException implements Exception {
  const RecordingPermissionDeniedException();

  @override
  String toString() => 'RecordingPermissionDeniedException: '
      'Microphone permission is required to record conversations.';
}

/// Thin wrapper around the [record] package that handles configuration,
/// file path generation, and state tracking.
///
/// Isolates the recording library from business logic so that
/// [RecordingService] never touches the record API directly.
class AudioEngine {
  AudioRecorder? _recorder;
  String? _currentFilePath;
  bool _isRecording = false;

  /// Whether a recording session is currently active.
  bool get isRecording => _isRecording;

  /// The file path of the current (or most recently started) recording.
  String? get currentFilePath => _currentFilePath;

  /// Starts recording audio for the given [conversationId].
  ///
  /// Creates a new [AudioRecorder] instance, verifies microphone permission,
  /// and begins recording to an AAC-LC .m4a file in the app documents
  /// directory under a `recordings/` subdirectory.
  ///
  /// Returns the full file path of the recording.
  ///
  /// Throws [RecordingPermissionDeniedException] if the user has not granted
  /// microphone access.
  Future<String> startRecording(String conversationId) async {
    _recorder = AudioRecorder();

    final hasPermission = await _recorder!.hasPermission();
    if (!hasPermission) {
      await _recorder!.dispose();
      _recorder = null;
      throw const RecordingPermissionDeniedException();
    }

    final directory = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${directory.path}/recordings');
    await recordingsDir.create(recursive: true);

    final filePath = '${directory.path}/recordings/$conversationId.m4a';

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
    _currentFilePath = filePath;
    return filePath;
  }

  /// Stops the current recording and returns the final file path.
  ///
  /// Returns `null` if no recording is currently active.
  Future<String?> stopRecording() async {
    if (!_isRecording || _recorder == null) return null;

    final path = await _recorder!.stop();
    _isRecording = false;
    _currentFilePath = null;

    await _recorder!.dispose();
    _recorder = null;

    return path;
  }

  /// Releases all resources held by the audio engine.
  ///
  /// Stops any active recording before disposing.
  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await _recorder?.dispose();
      _recorder = null;
    }
  }
}
