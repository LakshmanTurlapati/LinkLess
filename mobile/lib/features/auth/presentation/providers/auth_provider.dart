import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/config/app_config.dart';
import 'package:linkless/core/network/auth_interceptor.dart';
import 'package:linkless/core/network/dio_client.dart';
import 'package:linkless/features/auth/data/repositories/auth_repository.dart';
import 'package:linkless/features/auth/data/services/auth_api_service.dart';
import 'package:linkless/features/auth/data/services/token_storage_service.dart';
import 'package:linkless/features/auth/domain/models/user.dart';

// ---------------------------------------------------------------------------
// Auth status enum
// ---------------------------------------------------------------------------

/// Possible states for the authentication flow.
enum AuthStatus {
  /// Initial state before any auth check has been performed.
  initial,

  /// An async auth operation is in progress.
  loading,

  /// OTP was sent successfully; waiting for user to enter code.
  otpSent,

  /// User is authenticated with valid tokens.
  authenticated,

  /// User is not authenticated (no tokens or tokens expired).
  unauthenticated,

  /// An error occurred during an auth operation.
  error,
}

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

/// Immutable state for the authentication flow.
class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final String? phoneNumber;
  final bool isNewUser;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.phoneNumber,
    this.isNewUser = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    String? phoneNumber,
    bool? isNewUser,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isNewUser: isNewUser ?? this.isNewUser,
    );
  }
}

// ---------------------------------------------------------------------------
// Auth notifier
// ---------------------------------------------------------------------------

/// Manages authentication state transitions and coordinates with [AuthRepository].
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AuthState());

  /// Checks whether the user has a stored session (tokens in secure storage).
  Future<void> checkAuthStatus() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final hasSession = await _repository.hasStoredSession();
      state = state.copyWith(
        status: hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Failed to check auth status',
      );
    }
  }

  /// Sends an OTP to [phoneNumber].
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(status: AuthStatus.loading, phoneNumber: phoneNumber);
    try {
      await _repository.sendOtp(phoneNumber);
      state = state.copyWith(status: AuthStatus.otpSent);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e) ?? 'Failed to send OTP';
      state = state.copyWith(status: AuthStatus.error, errorMessage: message);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Failed to send OTP',
      );
    }
  }

  /// Verifies the OTP [code] for the current phone number.
  Future<void> verifyOtp(String code) async {
    final phone = state.phoneNumber;
    if (phone == null) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Phone number not set',
      );
      return;
    }

    state = state.copyWith(status: AuthStatus.loading);
    try {
      final result = await _repository.verifyOtp(phone, code);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isNewUser: result.isNewUser,
      );
    } on DioException catch (e) {
      final message = _extractErrorMessage(e) ?? 'Invalid verification code';
      state = state.copyWith(status: AuthStatus.error, errorMessage: message);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Verification failed',
      );
    }
  }

  /// Logs out the user and resets state.
  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading);
    await _repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Marks the user as no longer new (profile has been created).
  void setProfileCreated() {
    state = state.copyWith(isNewUser: false);
  }

  /// Marks the user as new (e.g. when app restart detects no profile).
  void markAsNewUser() {
    state = state.copyWith(isNewUser: true);
  }

  /// Clears the current error, returning to the previous non-error status.
  void clearError() {
    if (state.status == AuthStatus.error) {
      // If we had sent an OTP before the error, go back to otpSent.
      // Otherwise, go to unauthenticated.
      final previousStatus = state.phoneNumber != null
          ? AuthStatus.otpSent
          : AuthStatus.unauthenticated;
      state = state.copyWith(status: previousStatus, errorMessage: null);
    }
  }

  /// Extracts a user-facing error message from a Dio exception.
  String? _extractErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data.containsKey('detail')) {
      return data['detail'] as String?;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provides [TokenStorageService] as a singleton.
final tokenStorageProvider = Provider<TokenStorageService>((ref) {
  return TokenStorageService();
});

/// Provides the main Dio client with auth interceptor attached.
final authenticatedDioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final dio = createDioClient();

  // A separate Dio instance for refresh requests (no auth interceptor to avoid recursion).
  final refreshDio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeoutMs),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeoutMs),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  if (kDebugMode) {
    refreshDio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) => debugPrint(object.toString()),
      ),
    );
  }

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: tokenStorage,
      refreshDio: refreshDio,
    ),
  );

  return dio;
});

/// Provides [AuthApiService].
final authApiServiceProvider = Provider<AuthApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return AuthApiService(dio);
});

/// Provides [AuthRepository].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiService = ref.watch(authApiServiceProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return AuthRepository(apiService: apiService, tokenStorage: tokenStorage);
});

/// The main auth state provider.
///
/// Manages the full authentication lifecycle:
/// check status, send OTP, verify OTP, logout.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthNotifier(repository);
});

// ---------------------------------------------------------------------------
// GoRouter refresh listenable adapter
// ---------------------------------------------------------------------------

/// Adapts the [authProvider] state changes to a [Listenable] that GoRouter
/// can use for its refreshListenable parameter.
///
/// This triggers GoRouter redirect evaluation whenever auth state changes.
class AuthStateListenable extends ChangeNotifier {
  late final ProviderSubscription<AuthState> _subscription;

  AuthStateListenable(Ref ref) {
    _subscription = ref.listen<AuthState>(authProvider, (previous, next) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
