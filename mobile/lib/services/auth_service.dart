import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user_model.dart';
import 'api_client.dart';

const _tokenKey = 'linkless_auth_token';
const _refreshTokenKey = 'linkless_refresh_token';
const _userKey = 'linkless_user';

/// Authentication service handling login, registration, and token management.
class AuthService extends StateNotifier<AsyncValue<UserModel?>> {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthService({required ApiClient apiClient})
      : _apiClient = apiClient,
        super(const AsyncValue.loading()) {
    _loadSavedUser();
  }

  /// Check for a saved session on startup.
  Future<void> _loadSavedUser() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final userJson = await _storage.read(key: _userKey);

      if (token != null && userJson != null) {
        _apiClient.setAuthToken(token);
        final user = UserModel.fromJson(jsonDecode(userJson));

        // Verify the token is still valid
        try {
          final refreshedUser = await _apiClient.getCurrentUser();
          if (refreshedUser != null) {
            state = AsyncValue.data(refreshedUser);
            await _storage.write(
              key: _userKey,
              value: jsonEncode(refreshedUser.toJson()),
            );
            return;
          }
        } catch (_) {
          // Token might be expired, try refresh
          final refreshToken = await _storage.read(key: _refreshTokenKey);
          if (refreshToken != null) {
            final success = await _refreshToken(refreshToken);
            if (success) return;
          }
        }

        // Fallback to cached user data
        state = AsyncValue.data(user);
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e) {
      state = const AsyncValue.data(null);
    }
  }

  /// Register a new user account.
  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      state = const AsyncValue.loading();

      final result = await _apiClient.register(
        email: email,
        password: password,
        displayName: displayName,
      );

      if (result != null) {
        await _saveSession(result['token'], result['refresh_token'], result['user']);
        final user = UserModel.fromJson(result['user']);
        state = AsyncValue.data(user);
        return true;
      }

      state = const AsyncValue.data(null);
      return false;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  /// Log in with email and password.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      state = const AsyncValue.loading();

      final result = await _apiClient.login(
        email: email,
        password: password,
      );

      if (result != null) {
        await _saveSession(result['token'], result['refresh_token'], result['user']);
        final user = UserModel.fromJson(result['user']);
        state = AsyncValue.data(user);
        return true;
      }

      state = const AsyncValue.data(null);
      return false;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  /// Log out and clear saved session.
  Future<void> logout() async {
    try {
      await _apiClient.logout();
    } catch (_) {}

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userKey);
    _apiClient.clearAuthToken();
    state = const AsyncValue.data(null);
  }

  /// Update the current user's profile.
  Future<bool> updateProfile(UserModel updatedUser) async {
    try {
      final result = await _apiClient.updateProfile(updatedUser);
      if (result != null) {
        state = AsyncValue.data(result);
        await _storage.write(
          key: _userKey,
          value: jsonEncode(result.toJson()),
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Upload a profile photo.
  Future<String?> uploadProfilePhoto(String imagePath) async {
    try {
      return await _apiClient.uploadProfilePhoto(imagePath);
    } catch (e) {
      return null;
    }
  }

  Future<bool> _refreshToken(String refreshToken) async {
    try {
      final result = await _apiClient.refreshToken(refreshToken);
      if (result != null) {
        await _saveSession(result['token'], result['refresh_token'], result['user']);
        final user = UserModel.fromJson(result['user']);
        state = AsyncValue.data(user);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveSession(
      String token, String? refreshToken, Map<String, dynamic> userJson) async {
    await _storage.write(key: _tokenKey, value: token);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _storage.write(key: _userKey, value: jsonEncode(userJson));
    _apiClient.setAuthToken(token);
  }
}

/// Provider for the auth service.
final authServiceProvider =
    StateNotifierProvider<AuthService, AsyncValue<UserModel?>>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthService(apiClient: apiClient);
});
