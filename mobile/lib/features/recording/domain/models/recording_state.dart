/// Represents the current state of the audio recording lifecycle.
///
/// Used by RecordingService to track and communicate recording status
/// to the UI layer via Riverpod providers.
enum RecordingState {
  /// No recording in progress. Ready to start.
  idle,

  /// Proximity detected, waiting for identity chain (GATT exchange + profile
  /// fetch) to complete before recording starts. Overlay shows shimmer.
  pending,

  /// Actively recording audio to file.
  recording,

  /// Recording is temporarily paused (e.g., audio interruption).
  paused,

  /// An error occurred during recording.
  error,
}
