/// Environment configuration for the LinkLess app.
///
/// Provides API base URL and other environment-specific settings.
/// No Riverpod needed here -- this is a simple configuration class.
class AppConfig {
  AppConfig._();

  /// Base URL for the LinkLess API.
  /// Defaults to local development server.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  /// Mapbox public access token for map rendering.
  /// Pass via --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx at build time.
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  /// Connection timeout for HTTP requests in milliseconds.
  static const int connectTimeoutMs = 10000;

  /// Receive timeout for HTTP requests in milliseconds.
  static const int receiveTimeoutMs = 15000;
}
