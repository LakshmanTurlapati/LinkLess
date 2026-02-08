import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/map/data/services/map_api_service.dart';
import 'package:linkless/features/map/domain/models/map_conversation.dart';

/// Fetches map conversations for a given date from the backend API.
///
/// Parameterized by date string (YYYY-MM-DD format). Each unique date creates
/// its own cached future. Auto-disposes when the widget stops listening so
/// stale dates are freed from memory.
///
/// Uses manual provider (not code-gen) matching the existing project pattern
/// established in Phase 3.
final mapConversationsProvider =
    FutureProvider.autoDispose.family<List<MapConversation>, String>(
  (ref, date) async {
    final apiService = ref.read(mapApiServiceProvider);
    return apiService.getMapConversations(date);
  },
);
