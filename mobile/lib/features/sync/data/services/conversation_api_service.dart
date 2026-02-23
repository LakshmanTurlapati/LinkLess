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
      'started_at': startedAt.toUtc().toIso8601String(),
    };

    // Only send peer_user_id if it looks like a valid UUID
    // (not a raw BLE device ID like 42:7E:1D:38:E0:7B)
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (uuidPattern.hasMatch(peerId)) {
      data['peer_user_id'] = peerId;
    }

    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (endedAt != null) {
      data['ended_at'] = endedAt.toUtc().toIso8601String();
    }
    if (durationSeconds != null) {
      data['duration_seconds'] = durationSeconds;
    }

    final response = await _dio.post(
      '/conversations',
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
      '/conversations/$conversationId/confirm-upload',
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
      '/conversations/$conversationId',
    );
    return response.data as Map<String, dynamic>;
  }

  /// Lists all conversations for the authenticated user.
  ///
  /// GET /api/v1/conversations
  Future<List<Map<String, dynamic>>> listConversations() async {
    final response = await _dio.get('/conversations');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  /// Fetches backend health status for all infrastructure components.
  ///
  /// GET /api/v1/health
  /// Requires authentication. Results are cached for 30s on backend.
  /// Returns the full HealthResponse JSON with component-level status for
  /// Database, Redis, Tigris, ARQ worker, PostGIS, and API keys.
  ///
  /// The health endpoint may return HTTP 503 for degraded/unhealthy status.
  /// This method accepts 503 responses and still returns the response body,
  /// since the health data is present regardless of HTTP status.
  Future<Map<String, dynamic>> getHealthStatus() async {
    final response = await _dio.get(
      '/health',
      options: Options(
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Triggers force retranscription for a failed conversation.
  ///
  /// POST /api/v1/conversations/{conversationId}/retranscribe
  /// Debug-only endpoint. Requires DEBUG_MODE=true on the backend.
  ///
  /// Lets DioException propagate naturally for error handling in the UI layer:
  /// - 404: Backend not in debug mode (endpoint hidden)
  /// - 409: A retranscribe job is already in progress for this conversation
  /// - 400: Conversation is not in a failed state
  Future<Map<String, dynamic>> retranscribe(String conversationId) async {
    final response = await _dio.post(
      '/conversations/$conversationId/retranscribe',
    );
    return response.data as Map<String, dynamic>;
  }
}
