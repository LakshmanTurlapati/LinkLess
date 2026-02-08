import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/features/search/presentation/providers/search_provider.dart';
import 'package:linkless/features/search/presentation/widgets/search_result_tile.dart';

/// Full-screen search screen for finding conversations by person, topic,
/// or keyword.
///
/// Uses a TextField in the AppBar for search input with autofocus. Watches
/// [searchResultsProvider] for debounced API results and navigates to the
/// conversation detail/playback screen on result tap.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Clear search state before navigating back.
            ref.read(searchQueryProvider.notifier).state = '';
            context.pop();
          },
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search conversations...',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            ref.read(searchQueryProvider.notifier).state = value;
          },
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: _buildBody(context, query, searchResults),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String query,
    AsyncValue<List<dynamic>> searchResults,
  ) {
    // Show hint when query is too short.
    if (query.trim().length < 2) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Search by person, topic, or keyword',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return searchResults.when(
      data: (results) {
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.search_off,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No conversations found for "$query"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final result = results[index];
            return SearchResultTile(
              result: result,
              onTap: () {
                context.push('/conversations/${result.id}');
              },
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) {
        // Debounce cancellations are not real errors.
        if (error.toString().contains('Cancelled')) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Search failed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    ref.invalidate(searchResultsProvider);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
