import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/encounter_model.dart';
import 'api_client.dart';

/// State for a transcription session.
class TranscriptionState {
  final bool isRecording;
  final bool isTranscribing;
  final String? currentEncounterId;
  final List<TranscriptSegment> segments;
  final String? error;
  final Duration recordingDuration;

  const TranscriptionState({
    this.isRecording = false,
    this.isTranscribing = false,
    this.currentEncounterId,
    this.segments = const [],
    this.error,
    this.recordingDuration = Duration.zero,
  });

  TranscriptionState copyWith({
    bool? isRecording,
    bool? isTranscribing,
    String? currentEncounterId,
    List<TranscriptSegment>? segments,
    String? error,
    Duration? recordingDuration,
  }) {
    return TranscriptionState(
      isRecording: isRecording ?? this.isRecording,
      isTranscribing: isTranscribing ?? this.isTranscribing,
      currentEncounterId: currentEncounterId ?? this.currentEncounterId,
      segments: segments ?? this.segments,
      error: error,
      recordingDuration: recordingDuration ?? this.recordingDuration,
    );
  }
}

/// Manages audio recording and real-time transcription during encounters.
///
/// Records audio in chunks and sends them to the backend for AI-powered
/// transcription. Supports streaming transcription for real-time display.
class TranscriptionService extends StateNotifier<TranscriptionState> {
  final ApiClient _apiClient;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _chunkTimer;
  Timer? _durationTimer;
  String? _currentAudioPath;
  int _chunkIndex = 0;
  final _uuid = const Uuid();

  TranscriptionService({required ApiClient apiClient})
      : _apiClient = apiClient,
        super(const TranscriptionState());

  /// Start recording and transcribing for an encounter.
  Future<void> startRecording({
    required String encounterId,
    required String peerId,
  }) async {
    try {
      if (state.isRecording) return;

      // Check microphone permission
      if (!await _recorder.hasPermission()) {
        state = state.copyWith(error: 'Microphone permission is required');
        return;
      }

      final dir = await getTemporaryDirectory();
      _currentAudioPath =
          '${dir.path}/linkless_${encounterId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _chunkIndex = 0;

      // Start recording in AAC format for good quality at small file size
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentAudioPath!,
      );

      state = state.copyWith(
        isRecording: true,
        currentEncounterId: encounterId,
        segments: [],
        error: null,
      );

      // Send audio chunks every 10 seconds for near-real-time transcription
      _chunkTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _sendAudioChunk(encounterId),
      );

      // Track recording duration
      _durationTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          state = state.copyWith(
            recordingDuration: state.recordingDuration + const Duration(seconds: 1),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to start recording: $e');
    }
  }

  /// Stop recording and send final audio chunk for transcription.
  Future<void> stopRecording() async {
    try {
      if (!state.isRecording) return;

      _chunkTimer?.cancel();
      _durationTimer?.cancel();

      final path = await _recorder.stop();

      if (path != null && state.currentEncounterId != null) {
        // Send the final audio chunk
        await _sendFinalAudioChunk(state.currentEncounterId!, path);
      }

      state = state.copyWith(
        isRecording: false,
        recordingDuration: Duration.zero,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to stop recording: $e');
    }
  }

  /// Send an audio chunk to the backend for transcription.
  Future<void> _sendAudioChunk(String encounterId) async {
    try {
      // Stop current recording to flush the file
      final path = await _recorder.stop();
      if (path == null) return;

      _chunkIndex++;

      // Restart recording for next chunk
      final dir = await getTemporaryDirectory();
      _currentAudioPath =
          '${dir.path}/linkless_${encounterId}_chunk_$_chunkIndex.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentAudioPath!,
      );

      // Upload chunk to backend for transcription
      state = state.copyWith(isTranscribing: true);

      final newSegments = await _apiClient.transcribeAudioChunk(
        encounterId: encounterId,
        audioFilePath: path,
        chunkIndex: _chunkIndex - 1,
      );

      if (newSegments != null) {
        state = state.copyWith(
          segments: [...state.segments, ...newSegments],
          isTranscribing: false,
        );
      }

      // Clean up the sent chunk file
      try {
        await File(path).delete();
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isTranscribing: false,
        error: 'Transcription error: $e',
      );
    }
  }

  /// Send the final audio chunk and request full transcript processing.
  Future<void> _sendFinalAudioChunk(
      String encounterId, String audioPath) async {
    try {
      state = state.copyWith(isTranscribing: true);

      final newSegments = await _apiClient.transcribeAudioChunk(
        encounterId: encounterId,
        audioFilePath: audioPath,
        chunkIndex: _chunkIndex,
        isFinal: true,
      );

      if (newSegments != null) {
        state = state.copyWith(
          segments: [...state.segments, ...newSegments],
          isTranscribing: false,
        );
      }

      // Clean up audio file
      try {
        await File(audioPath).delete();
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isTranscribing: false,
        error: 'Final transcription error: $e',
      );
    }
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _durationTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

/// Provider for the transcription service.
final transcriptionServiceProvider =
    StateNotifierProvider<TranscriptionService, TranscriptionState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TranscriptionService(apiClient: apiClient);
});
