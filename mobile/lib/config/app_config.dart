/// App-wide configuration constants.
class AppConfig {
  AppConfig._();

  /// Backend API base URL.
  /// Change this to your deployed server URL in production.
  static const String apiBaseUrl = 'http://localhost:8000/v1';

  /// BLE scanning interval in seconds.
  static const int bleScanIntervalSeconds = 1;

  /// RSSI threshold for "in proximity" (closer = higher value).
  /// -65 dBm roughly corresponds to ~2-3 meters.
  static const int proximityRssiThreshold = -65;

  /// Minimum seconds in proximity before triggering an encounter.
  static const int proximityMinDurationSeconds = 5;

  /// Audio chunk duration in seconds for near-real-time transcription.
  static const int audioChunkDurationSeconds = 10;

  /// Maximum audio recording duration in minutes (safety limit).
  static const int maxRecordingDurationMinutes = 120;

  /// App version.
  static const String version = '1.0.0';
}
