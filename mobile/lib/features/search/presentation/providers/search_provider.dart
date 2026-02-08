import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/search/data/services/search_api_service.dart';
import 'package:linkless/features/search/domain/models/search_result.dart';

/// Holds the current search query text.
///
/// Updated by the SearchScreen TextField as the user types.
/// Watched by [searchResultsProvider] to trigger debounced API calls.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Debounced search results provider.
///
/// Watches [searchQueryProvider] and calls the search API after a 400ms
/// debounce delay. Queries with fewer than 2 characters return an empty
/// list without making an API call. Uses ref.onDispose for cancellation
/// when a new query arrives during the debounce window.
final searchResultsProvider =
    FutureProvider.autoDispose<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return [];

  // Debounce: wait 400ms, cancel if a new query arrives.
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future.delayed(const Duration(milliseconds: 400));
  if (cancelled) throw Exception('Cancelled');

  final apiService = ref.read(searchApiServiceProvider);
  return apiService.searchConversations(query.trim());
});
