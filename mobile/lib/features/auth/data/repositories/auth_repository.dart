import 'package:linkless/features/auth/data/services/auth_api_service.dart';
import 'package:linkless/features/auth/data/services/token_storage_service.dart';
import 'package:linkless/features/auth/domain/models/user.dart';

/// Coordinates authentication operations between the API and local storage.
///
/// This is the single source of truth for auth state at the data layer.
/// The presentation layer should interact with auth through this repository.
class AuthRepository {
  final AuthApiService _apiService;
  final TokenStorageService _tokenStorage;

  AuthRepository({
    required AuthApiService apiService,
    required TokenStorageService tokenStorage,
  })  : _apiService = apiService,
        _tokenStorage = tokenStorage;

  /// Requests an OTP for [phoneNumber].
  Future<void> sendOtp(String phoneNumber) async {
    await _apiService.sendOtp(phoneNumber);
  }

  /// Verifies the OTP [code] for [phoneNumber].
  ///
  /// On success, saves tokens to secure storage and returns the [User]
  /// along with whether this is a new user who needs to create a profile.
  Future<({User user, bool isNewUser})> verifyOtp(
    String phoneNumber,
    String code,
  ) async {
    final response = await _apiService.verifyOtp(phoneNumber, code);
    await _tokenStorage.saveTokens(
      accessToken: response.token.accessToken,
      refreshToken: response.token.refreshToken,
    );
    return (user: response.user, isNewUser: response.isNewUser);
  }

  /// Checks if the user has stored tokens (i.e., was previously logged in).
  Future<bool> hasStoredSession() async {
    return _tokenStorage.hasTokens();
  }

  /// Logs out: clears local tokens and notifies the server.
  ///
  /// Server-side logout is best-effort -- tokens are always cleared locally.
  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (_) {
      // Server logout is best-effort. Even if it fails (e.g., network error),
      // we still clear local tokens so the user is logged out locally.
    }
    await _tokenStorage.clearTokens();
  }

  /// Refreshes the stored tokens using the current refresh token.
  ///
  /// Returns true on success, false on failure (tokens cleared on failure).
  Future<bool> refreshTokens() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final newTokens = await _apiService.refreshToken(refreshToken);
      await _tokenStorage.saveTokens(
        accessToken: newTokens.accessToken,
        refreshToken: newTokens.refreshToken,
      );
      return true;
    } catch (_) {
      await _tokenStorage.clearTokens();
      return false;
    }
  }
}
