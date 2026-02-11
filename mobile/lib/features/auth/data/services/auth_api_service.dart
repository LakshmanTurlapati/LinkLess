import 'package:dio/dio.dart';

import 'package:linkless/features/auth/domain/models/auth_token.dart';
import 'package:linkless/features/auth/domain/models/user.dart';

/// Response from the verify-otp endpoint containing tokens and user data.
class VerifyOtpResponse {
  final AuthToken token;
  final User user;
  final bool isNewUser;

  const VerifyOtpResponse({
    required this.token,
    required this.user,
    this.isNewUser = false,
  });

  factory VerifyOtpResponse.fromJson(Map<String, dynamic> json) {
    return VerifyOtpResponse(
      token: AuthToken.fromJson(json),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      isNewUser: json['is_new_user'] as bool? ?? false,
    );
  }
}

/// Handles raw HTTP calls to the authentication API endpoints.
///
/// Does NOT manage token storage or app state -- that is the
/// responsibility of [AuthRepository].
class AuthApiService {
  final Dio _dio;

  AuthApiService(this._dio);

  /// Requests an OTP to be sent to [phoneNumber].
  ///
  /// POST /auth/send-otp
  Future<void> sendOtp(String phoneNumber) async {
    await _dio.post(
      '/auth/send-otp',
      data: {'phone_number': phoneNumber},
    );
  }

  /// Verifies the OTP [code] for [phoneNumber] and returns tokens + user.
  ///
  /// POST /auth/verify-otp
  Future<VerifyOtpResponse> verifyOtp(String phoneNumber, String code) async {
    final response = await _dio.post(
      '/auth/verify-otp',
      data: {
        'phone_number': phoneNumber,
        'code': code,
      },
    );
    return VerifyOtpResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Exchanges a refresh token for a new token pair.
  ///
  /// POST /auth/refresh
  Future<AuthToken> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return AuthToken.fromJson(response.data as Map<String, dynamic>);
  }

  /// Logs out the current user (invalidates refresh token server-side).
  ///
  /// POST /auth/logout
  /// Requires Authorization: Bearer header (added by interceptor).
  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }
}
