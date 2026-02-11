import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/connections/domain/models/connection.dart';
import 'package:linkless/features/connections/domain/models/connection_request.dart';
import 'package:linkless/features/connections/presentation/providers/connection_provider.dart';
import 'package:linkless/features/connections/presentation/widgets/connection_tile.dart';
import 'package:linkless/features/connections/presentation/widgets/social_links_popup.dart';

/// The Links screen — replaces the old Conversations tab.
///
/// Contains two toggle tabs:
/// - **Successful Links**: Mutually accepted connections with peer profiles
/// - **Pending**: Incoming connection requests awaiting the user's response
class ConnectionsListScreen extends ConsumerStatefulWidget {
  const ConnectionsListScreen({super.key});

  @override
  ConsumerState<ConnectionsListScreen> createState() =>
      _ConnectionsListScreenState();
}

class _ConnectionsListScreenState
    extends ConsumerState<ConnectionsListScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Links'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Toggle bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Successful')),
                ButtonSegment(value: 1, label: Text('Pending')),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selected) {
                setState(() => _selectedTab = selected.first);
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.accentBlue.withOpacity(0.15);
                  }
                  return AppColors.backgroundDarker;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.accentBlue;
                  }
                  return AppColors.textSecondary;
                }),
                side: WidgetStateProperty.all(
                  const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          // Tab content
          Expanded(
            child: _selectedTab == 0
                ? _SuccessfulLinksTab()
                : _PendingLinksTab(),
          ),
        ],
      ),
    );
  }
}

/// Displays established (mutually accepted) connections.
class _SuccessfulLinksTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(connectionsListProvider);

    return connectionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: 'Failed to load connections',
        onRetry: () => ref.invalidate(connectionsListProvider),
      ),
      data: (connections) {
        if (connections.isEmpty) {
          return _EmptyState(
            icon: Icons.link_off,
            title: 'No links yet',
            subtitle: 'Connect with people after your conversations',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(connectionsListProvider),
          child: ListView.builder(
            itemCount: connections.length,
            itemBuilder: (context, index) {
              return ConnectionTile(connection: connections[index]);
            },
          ),
        );
      },
    );
  }
}

/// Displays incoming pending connection requests with accept/decline actions.
class _PendingLinksTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingConnectionsProvider);

    return pendingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: 'Failed to load pending requests',
        onRetry: () => ref.invalidate(pendingConnectionsProvider),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return _EmptyState(
            icon: Icons.hourglass_empty,
            title: 'No pending link requests',
            subtitle: 'When someone wants to connect, it will appear here',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pendingConnectionsProvider),
          child: ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              return _PendingRequestCard(request: requests[index]);
            },
          ),
        );
      },
    );
  }
}

/// Card for a single pending connection request with accept/decline buttons.
class _PendingRequestCard extends ConsumerStatefulWidget {
  final ConnectionRequest request;

  const _PendingRequestCard({required this.request});

  @override
  ConsumerState<_PendingRequestCard> createState() =>
      _PendingRequestCardState();
}

class _PendingRequestCardState extends ConsumerState<_PendingRequestCard> {
  bool _isLoading = false;

  Future<void> _handleAccept() async {
    setState(() => _isLoading = true);
    try {
      final response = await acceptConnection(
        ref,
        widget.request.id,
        conversationId: widget.request.conversationId,
      );

      if (!mounted) return;

      final isMutual = response['is_mutual'] as bool? ?? false;
      if (isMutual) {
        final linksJson =
            response['exchanged_links'] as List<dynamic>? ?? [];
        final exchangedLinks = linksJson
            .map((e) =>
                ExchangedSocialLink.fromJson(e as Map<String, dynamic>))
            .toList();

        await SocialLinksPopup.show(
          context,
          peerDisplayName: widget.request.displayName,
          peerInitials: widget.request.requesterInitials,
          peerPhotoUrl: widget.request.requesterPhotoUrl,
          exchangedLinks: exchangedLinks,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to accept request')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDecline() async {
    setState(() => _isLoading = true);
    try {
      await declineConnection(
        ref,
        widget.request.id,
        conversationId: widget.request.conversationId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to decline request')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final req = widget.request;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: req.requesterPhotoUrl != null
                  ? NetworkImage(req.requesterPhotoUrl!)
                  : null,
              child: req.requesterPhotoUrl == null
                  ? Text(
                      req.requesterInitials ?? '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Text(
                req.displayName,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),

            // Action buttons
            if (_isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              OutlinedButton(
                onPressed: _handleDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Decline'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _handleAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Link'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable error view with retry button.
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Reusable empty state with icon, title, and subtitle.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              subtitle,
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
