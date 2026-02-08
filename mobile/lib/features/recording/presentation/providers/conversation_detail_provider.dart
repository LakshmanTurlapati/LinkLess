import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/sync/presentation/providers/sync_provider.dart';

/// Fetches conversation detail (including transcript and summary) from the
/// backend API.
///
/// Takes a conversation ID as the family parameter and returns the full
/// response map containing conversation metadata, transcript, and summary.
///
/// Returns null if the conversation is not found (404) or if a network
/// error occurs. Auto-disposes so it refetches each time the screen opens.
final conversationDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, conversationId) async {
    final apiService = ref.watch(conversationApiServiceProvider);
    try {
      final response = await apiService.getConversationDetail(conversationId);
      return response;
    } on DioException catch (e) {
      // Return null for 404 (not found) or network errors
      if (e.response?.statusCode == 404 ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return null;
      }
      rethrow;
    }
  },
);
