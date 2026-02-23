import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/recording/domain/models/conversation_local.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';
import 'package:linkless/features/sync/presentation/providers/sync_provider.dart';

/// Fetches backend health status for all infrastructure components.
///
/// Returns the raw HealthResponse JSON as a [Map]. Auto-disposes so it
/// re-fetches each time the debug panel opens. Manual refresh is supported
/// via `ref.invalidate(healthCheckProvider)`.
final healthCheckProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final apiService = ref.watch(conversationApiServiceProvider);
  return apiService.getHealthStatus();
});

/// Streams only debug-tagged conversations from the local database.
///
/// Debug recordings use a "debug_" prefix on peerId to distinguish them
/// from real BLE-triggered conversations. This provider filters to include
/// only those debug conversations, sorted by startedAt descending.
final debugConversationListProvider =
    StreamProvider.autoDispose<List<ConversationLocal>>((ref) {
  final dao = ref.watch(conversationDaoProvider);
  return dao.watchAllConversations().map(
        (entries) => entries
            .map(ConversationLocal.fromEntry)
            .where((c) => c.peerId.startsWith('debug_'))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      );
});

/// Triggers force retranscription for a failed conversation.
///
/// Takes the server-side conversation ID as the family parameter.
/// Returns the response map on success, or throws a descriptive error
/// for known error codes:
/// - 404: Backend not in debug mode (endpoint hidden)
/// - 409: A retranscribe job is already in progress
/// - 400: Conversation is not in a failed state
final retranscribeProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, conversationId) async {
  final apiService = ref.watch(conversationApiServiceProvider);
  try {
    return await apiService.retranscribe(conversationId);
  } on DioException catch (e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 404) {
      throw Exception(
          'Retranscribe unavailable (backend not in debug mode)');
    }
    if (statusCode == 409) {
      throw Exception('A retranscribe job is already in progress');
    }
    if (statusCode == 400) {
      throw Exception('Conversation is not in a failed state');
    }
    rethrow;
  }
});
