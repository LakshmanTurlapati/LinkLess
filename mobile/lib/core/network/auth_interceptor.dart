import 'package:dio/dio.dart';

import 'package:linkless/features/auth/data/services/token_storage_service.dart';

/// Dio interceptor that handles JWT authentication automatically.
///
/// - Attaches Bearer token to every outgoing request.
/// - On 401 responses, attempts to refresh the token and retry the request.
/// - Uses [QueuedInterceptor] so concurrent 401s only trigger one refresh.
class AuthInterceptor extends QueuedInterceptor {
  final TokenStorageService _tokenStorage;

  /// A separate Dio instance used exclusively for token refresh requests.
  /// This avoids interceptor recursion (the main Dio has this interceptor).
  final Dio _refreshDio;

  AuthInterceptor({
    required TokenStorageService tokenStorage,
    required Dio refreshDio,
  })  : _tokenStorage = tokenStorage,
        _refreshDio = refreshDio;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await _tokenStorage.getAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Attempt to refresh the token.
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null) {
      await _tokenStorage.clearTokens();
      return handler.next(err);
    }

    try {
      final response = await _refreshDio.post(
        'auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final newAccessToken = response.data['access_token'] as String;
      final newRefreshToken = response.data['refresh_token'] as String;

      await _tokenStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );

      // Retry the original request with the new access token.
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $newAccessToken';

      final retryResponse = await _refreshDio.fetch(options);
      return handler.resolve(retryResponse);
    } catch (_) {
      // Refresh failed -- clear tokens and propagate the original error.
      await _tokenStorage.clearTokens();
      return handler.next(err);
    }
  }
}
