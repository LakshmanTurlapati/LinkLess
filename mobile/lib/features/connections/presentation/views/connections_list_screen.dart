import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/connections/presentation/providers/connection_provider.dart';
import 'package:linkless/features/connections/presentation/widgets/connection_tile.dart';

/// Screen displaying the list of established (mutually accepted) connections.
///
/// Watches [connectionsListProvider] and renders a list of [ConnectionTile]
/// widgets. Shows loading, error, and empty states as appropriate.
class ConnectionsListScreen extends ConsumerWidget {
  const ConnectionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(connectionsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
      ),
      body: connectionsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => Center(
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
                  'Failed to load connections',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(connectionsListProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (connections) {
          if (connections.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(connectionsListProvider);
            },
            child: ListView.builder(
              itemCount: connections.length,
              itemBuilder: (context, index) {
                return ConnectionTile(connection: connections[index]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No connections yet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Connect with people after your conversations',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
