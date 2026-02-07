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

  /// Connection timeout for HTTP requests in milliseconds.
  static const int connectTimeoutMs = 10000;

  /// Receive timeout for HTTP requests in milliseconds.
  static const int receiveTimeoutMs = 15000;
}
