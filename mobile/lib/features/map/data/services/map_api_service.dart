import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/map/domain/models/map_conversation.dart';

/// Handles HTTP calls to the map-specific conversation endpoints.
///
/// Uses the authenticated Dio instance matching the existing service pattern
/// established by [ConversationApiService] and [ProfileApiService].
class MapApiService {
  final Dio _dio;

  MapApiService(this._dio);

  /// Fetches conversations formatted for map display on a given date.
  ///
  /// GET /api/v1/conversations/map?date=YYYY-MM-DD
  ///
  /// Returns a list of [MapConversation] with GPS coordinates and peer
  /// profile info. Only conversations with location data are included.
  /// Anonymous masking is applied server-side.
  Future<List<MapConversation>> getMapConversations(String date) async {
    try {
      final response = await _dio.get(
        'api/v1/conversations/map',
        queryParameters: {'date': date},
      );
      final list = response.data as List<dynamic>;
      return list
          .map((e) => MapConversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      // Return empty list for network errors or 404
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.response?.statusCode == 404) {
        return [];
      }
      rethrow;
    }
  }
}

/// Provides the [MapApiService] using the authenticated Dio instance.
///
/// Matches the existing provider pattern from [conversationApiServiceProvider].
final mapApiServiceProvider = Provider<MapApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return MapApiService(dio);
});
