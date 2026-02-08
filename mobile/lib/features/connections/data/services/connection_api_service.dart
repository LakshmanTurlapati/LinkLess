import 'package:dio/dio.dart';

/// Handles raw HTTP calls to the connection backend endpoints.
///
/// Maps to the backend routes registered under /api/v1/connections.
/// Uses the authenticated Dio instance with base URL and auth interceptor.
class ConnectionApiService {
  final Dio _dio;

  ConnectionApiService(this._dio);

  /// Creates a new connection request for a conversation.
  ///
  /// POST /api/v1/connections/request
  /// Returns the created (or existing) connection request data.
  Future<Map<String, dynamic>> createRequest(String conversationId) async {
    final response = await _dio.post(
      'api/v1/connections/request',
      data: {'conversation_id': conversationId},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Accepts a connection request.
  ///
  /// POST /api/v1/connections/{id}/accept
  /// Returns the updated request data (may include exchanged links if mutual).
  Future<Map<String, dynamic>> acceptRequest(String requestId) async {
    final response = await _dio.post(
      'api/v1/connections/$requestId/accept',
    );
    return response.data as Map<String, dynamic>;
  }

  /// Declines a connection request.
  ///
  /// POST /api/v1/connections/{id}/decline
  Future<void> declineRequest(String requestId) async {
    await _dio.post(
      'api/v1/connections/$requestId/decline',
    );
  }

  /// Gets the connection status for a specific conversation.
  ///
  /// GET /api/v1/connections/status?conversation_id=X
  /// Returns null if no connection request exists (404).
  Future<Map<String, dynamic>?> getConnectionStatus(
    String conversationId,
  ) async {
    try {
      final response = await _dio.get(
        'api/v1/connections/status',
        queryParameters: {'conversation_id': conversationId},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// Lists all established connections (mutually accepted).
  ///
  /// GET /api/v1/connections
  Future<List<Map<String, dynamic>>> listConnections() async {
    final response = await _dio.get('api/v1/connections');
    final list = response.data as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  /// Lists pending connection requests where the current user is the recipient.
  ///
  /// GET /api/v1/connections/pending
  Future<List<Map<String, dynamic>>> listPending() async {
    final response = await _dio.get('api/v1/connections/pending');
    final list = response.data as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  /// Blocks a user from proximity detection and connection requests.
  ///
  /// POST /api/v1/connections/block
  Future<void> blockUser(String userId) async {
    await _dio.post(
      'api/v1/connections/block',
      data: {'blocked_id': userId},
    );
  }

  /// Unblocks a previously blocked user.
  ///
  /// DELETE /api/v1/connections/block/{userId}
  Future<void> unblockUser(String userId) async {
    await _dio.delete('api/v1/connections/block/$userId');
  }

  /// Lists all blocked user IDs for local cache sync.
  ///
  /// GET /api/v1/connections/blocked
  /// Returns a list of blocked user ID strings.
  Future<List<String>> listBlocked() async {
    final response = await _dio.get('api/v1/connections/blocked');
    final list = response.data as List<dynamic>;
    return list.map((e) => e.toString()).toList();
  }
}
