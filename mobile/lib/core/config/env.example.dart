/// Local environment secrets -- DO NOT commit this file.
/// Copy this file to env.dart and fill in your values.
///
///   cp lib/core/config/env.example.dart lib/core/config/env.dart
class Env {
  Env._();

  /// LinkLess API base URL (Fly.io production).
  /// For local dev, use 'http://localhost:8000/api/v1'.
  static const String apiBaseUrl = 'https://linkless-api.fly.dev/api/v1';

  /// Mapbox public access token for map rendering.
  /// Get yours at https://account.mapbox.com/access-tokens/
  static const String mapboxAccessToken = 'pk.your_mapbox_public_token_here';
}
