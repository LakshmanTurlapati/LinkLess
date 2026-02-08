import 'package:dio/dio.dart';

/// Handles raw HTTP calls to the conversation backend endpoints.
///
/// Maps to the backend routes registered under /api/v1/conversations.
/// Uses the authenticated Dio instance with base URL and auth interceptor.
class ConversationApiService {
  final Dio _dio;

  ConversationApiService(this._dio);

  /// Creates a new conversation on the backend and receives upload URLs.
  ///
  /// POST /api/v1/conversations
  /// Returns the full response data including conversation metadata and
  /// presigned upload URLs for audio file upload.
  Future<Map<String, dynamic>> createConversation({
    required String localId,
    required String peerId,
    double? latitude,
    double? longitude,
    required DateTime startedAt,
    DateTime? endedAt,
    int? durationSeconds,
  }) async {
    final data = <String, dynamic>{
      'local_id': localId,
      'peer_id': peerId,
      'started_at': startedAt.toUtc().toIso8601String(),
    };

    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (endedAt != null) {
      data['ended_at'] = endedAt.toUtc().toIso8601String();
    }
    if (durationSeconds != null) {
      data['duration_seconds'] = durationSeconds;
    }

    final response = await _dio.post(
      'api/v1/conversations',
      data: data,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Confirms that the audio file has been uploaded to Tigris.
  ///
  /// POST /api/v1/conversations/{conversationId}/confirm-upload
  /// Triggers the backend transcription pipeline.
  Future<Map<String, dynamic>> confirmUpload(String conversationId) async {
    final response = await _dio.post(
      'api/v1/conversations/$conversationId/confirm-upload',
    );
    return response.data as Map<String, dynamic>;
  }

  /// Fetches a conversation with its transcript and summary.
  ///
  /// GET /api/v1/conversations/{conversationId}
  Future<Map<String, dynamic>> getConversationDetail(
    String conversationId,
  ) async {
    final response = await _dio.get(
      'api/v1/conversations/$conversationId',
    );
    return response.data as Map<String, dynamic>;
  }

  /// Lists all conversations for the authenticated user.
  ///
  /// GET /api/v1/conversations
  Future<List<Map<String, dynamic>>> listConversations() async {
    final response = await _dio.get('api/v1/conversations');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }
}
