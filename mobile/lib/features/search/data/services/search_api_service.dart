import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/search/domain/models/search_result.dart';

/// Handles HTTP calls to the conversation search endpoint.
///
/// Uses the authenticated Dio instance matching the existing service pattern
/// established by [MapApiService] and [ConversationApiService].
class SearchApiService {
  final Dio _dio;

  SearchApiService(this._dio);

  /// Searches conversations by full-text query.
  ///
  /// GET /api/v1/conversations/search?q=...&limit=...&offset=...
  ///
  /// Returns a list of [SearchResult] with peer info, transcript snippets,
  /// and relevance rank. Anonymous masking is applied server-side.
  Future<List<SearchResult>> searchConversations(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        '/conversations/search',
        queryParameters: {
          'q': query,
          'limit': limit,
          'offset': offset,
        },
      );
      final list = response.data as List<dynamic>;
      return list
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return [];
      }
      rethrow;
    }
  }
}

/// Provides the [SearchApiService] using the authenticated Dio instance.
///
/// Matches the existing provider pattern from [mapApiServiceProvider].
final searchApiServiceProvider = Provider<SearchApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return SearchApiService(dio);
});
