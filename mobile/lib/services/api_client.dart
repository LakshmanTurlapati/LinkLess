import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../models/encounter_model.dart';

/// API client for communicating with the LinkLess backend.
class ApiClient {
  final Dio _dio;

  ApiClient({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? 'https://api.linkless.app/v1',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ));

  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  // ─── Authentication ───────────────────────────────────────────────

  Future<Map<String, dynamic>?> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'display_name': displayName,
    });
    return response.data;
  }

  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return response.data;
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }

  Future<Map<String, dynamic>?> refreshToken(String refreshToken) async {
    final response = await _dio.post('/auth/refresh', data: {
      'refresh_token': refreshToken,
    });
    return response.data;
  }

  // ─── User Profile ─────────────────────────────────────────────────

  Future<UserModel?> getCurrentUser() async {
    final response = await _dio.get('/users/me');
    if (response.data != null) {
      return UserModel.fromJson(response.data);
    }
    return null;
  }

  Future<UserModel?> updateProfile(UserModel user) async {
    final response = await _dio.put('/users/me', data: user.toJson());
    if (response.data != null) {
      return UserModel.fromJson(response.data);
    }
    return null;
  }

  Future<String?> uploadProfilePhoto(String imagePath) async {
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(imagePath),
    });
    final response = await _dio.post('/users/me/photo', data: formData);
    return response.data?['photo_url'];
  }

  Future<UserModel?> getUserById(String userId) async {
    final response = await _dio.get('/users/$userId');
    if (response.data != null) {
      return UserModel.fromJson(response.data);
    }
    return null;
  }

  // ─── Encounters ───────────────────────────────────────────────────

  Future<EncounterModel?> createEncounter({
    required String peerId,
    double? proximityDistance,
  }) async {
    final response = await _dio.post('/encounters', data: {
      'peer_id': peerId,
      'proximity_distance': proximityDistance,
    });
    if (response.data != null) {
      return EncounterModel.fromJson(response.data);
    }
    return null;
  }

  Future<EncounterModel?> getEncounter(String encounterId) async {
    final response = await _dio.get('/encounters/$encounterId');
    if (response.data != null) {
      return EncounterModel.fromJson(response.data);
    }
    return null;
  }

  Future<List<EncounterModel>> getEncounters({
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _dio.get('/encounters', queryParameters: {
      'page': page,
      'per_page': perPage,
    });
    if (response.data != null) {
      return (response.data['encounters'] as List)
          .map((e) => EncounterModel.fromJson(e))
          .toList();
    }
    return [];
  }

  Future<void> endEncounter(String encounterId) async {
    await _dio.post('/encounters/$encounterId/end');
  }

  // ─── Transcription ────────────────────────────────────────────────

  Future<List<TranscriptSegment>?> transcribeAudioChunk({
    required String encounterId,
    required String audioFilePath,
    required int chunkIndex,
    bool isFinal = false,
  }) async {
    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(audioFilePath),
      'chunk_index': chunkIndex,
      'is_final': isFinal,
    });

    final response = await _dio.post(
      '/encounters/$encounterId/transcribe',
      data: formData,
    );

    if (response.data != null && response.data['segments'] != null) {
      return (response.data['segments'] as List)
          .map((e) => TranscriptSegment.fromJson(e))
          .toList();
    }
    return null;
  }

  /// Request AI summary of an encounter's transcript.
  Future<Map<String, dynamic>?> summarizeEncounter(
      String encounterId) async {
    final response =
        await _dio.post('/encounters/$encounterId/summarize');
    return response.data;
  }
}

/// Provider for the API client.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
