import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/connections/data/services/connection_api_service.dart';
import 'package:linkless/features/connections/domain/models/connection.dart';
import 'package:linkless/features/connections/domain/models/connection_request.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

/// Provides [ConnectionApiService] using the authenticated Dio client.
final connectionApiServiceProvider = Provider<ConnectionApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ConnectionApiService(dio);
});

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

/// Fetches the connection status for a specific conversation.
///
/// Returns a [ConnectionRequest] if one exists for the conversation,
/// or null if no request has been made yet. Auto-disposes when the
/// widget watching it is unmounted.
final connectionStatusProvider =
    FutureProvider.autoDispose.family<ConnectionRequest?, String>(
  (ref, conversationId) async {
    final apiService = ref.watch(connectionApiServiceProvider);
    final data = await apiService.getConnectionStatus(conversationId);
    if (data == null) return null;
    return ConnectionRequest.fromJson(data);
  },
);

/// Fetches the list of established (mutually accepted) connections.
///
/// Each connection includes peer display info and exchanged social links.
/// Auto-disposes when the widget watching it is unmounted.
final connectionsListProvider =
    FutureProvider.autoDispose<List<Connection>>((ref) async {
  final apiService = ref.watch(connectionApiServiceProvider);
  final dataList = await apiService.listConnections();
  return dataList.map((json) => Connection.fromJson(json)).toList();
});

/// Fetches the list of pending connection requests where the current
/// user is the recipient.
///
/// Auto-disposes when the widget watching it is unmounted.
final pendingConnectionsProvider =
    FutureProvider.autoDispose<List<ConnectionRequest>>((ref) async {
  final apiService = ref.watch(connectionApiServiceProvider);
  final dataList = await apiService.listPending();
  return dataList
      .map((json) => ConnectionRequest.fromJson(json))
      .toList();
});

// ---------------------------------------------------------------------------
// Action functions
// ---------------------------------------------------------------------------

/// Sends a connection request for a conversation and invalidates
/// the relevant providers so they refetch.
Future<void> sendConnectionRequest(
  WidgetRef ref,
  String conversationId,
) async {
  final apiService = ref.read(connectionApiServiceProvider);
  await apiService.createRequest(conversationId);
  ref.invalidate(connectionStatusProvider(conversationId));
  ref.invalidate(pendingConnectionsProvider);
}

/// Accepts a connection request and invalidates the relevant providers.
///
/// Returns the raw response map containing `is_mutual` and `exchanged_links`
/// so callers can show a social links popup on mutual acceptance.
Future<Map<String, dynamic>> acceptConnection(
  WidgetRef ref,
  String requestId, {
  String? conversationId,
}) async {
  final apiService = ref.read(connectionApiServiceProvider);
  final response = await apiService.acceptRequest(requestId);
  if (conversationId != null) {
    ref.invalidate(connectionStatusProvider(conversationId));
  }
  ref.invalidate(connectionsListProvider);
  ref.invalidate(pendingConnectionsProvider);
  return response;
}

/// Declines a connection request and invalidates the relevant providers.
Future<void> declineConnection(
  WidgetRef ref,
  String requestId, {
  String? conversationId,
}) async {
  final apiService = ref.read(connectionApiServiceProvider);
  await apiService.declineRequest(requestId);
  if (conversationId != null) {
    ref.invalidate(connectionStatusProvider(conversationId));
  }
  ref.invalidate(pendingConnectionsProvider);
}
