import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/encounter_model.dart';
import '../../services/api_client.dart';
import 'encounter_detail_screen.dart';

/// Provider to fetch encounters list.
final encountersProvider = FutureProvider<List<EncounterModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getEncounters();
});

class EncountersScreen extends ConsumerWidget {
  const EncountersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final encountersAsync = ref.watch(encountersProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encounters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(encountersProvider),
          ),
        ],
      ),
      body: encountersAsync.when(
        data: (encounters) {
          if (encounters.isEmpty) {
            return _buildEmptyState(context, colorScheme);
          }
          return _buildEncountersList(context, encounters, colorScheme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load encounters',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.refresh(encountersProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 72,
              color: colorScheme.onSurfaceVariant.withAlpha(128),
            ),
            const SizedBox(height: 24),
            Text(
              'No encounters yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'When you\'re near another LinkLess user, your conversation will be automatically captured here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncountersList(BuildContext context,
      List<EncounterModel> encounters, ColorScheme colorScheme) {
    // Group encounters by date
    final grouped = <String, List<EncounterModel>>{};
    for (final encounter in encounters) {
      final key = DateFormat('MMMM d, yyyy').format(encounter.startedAt);
      grouped.putIfAbsent(key, () => []).add(encounter);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final date = grouped.keys.elementAt(index);
        final dayEncounters = grouped[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                date,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            ...dayEncounters.map((encounter) => _buildEncounterCard(
                  context, encounter, colorScheme)),
          ],
        );
      },
    );
  }

  Widget _buildEncounterCard(BuildContext context, EncounterModel encounter,
      ColorScheme colorScheme) {
    final peerName = encounter.peerUser?.displayName ?? 'Unknown User';
    final time = DateFormat('h:mm a').format(encounter.startedAt);
    final hasTranscript = encounter.transcript.isNotEmpty;
    final topicChips = encounter.topics.take(3).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  EncounterDetailScreen(encounterId: encounter.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: encounter.peerUser?.photoUrl != null
                        ? NetworkImage(encounter.peerUser!.photoUrl!)
                        : null,
                    child: encounter.peerUser?.photoUrl == null
                        ? Icon(Icons.person, color: colorScheme.primary)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$time  •  ${encounter.formattedDuration}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(encounter.status, colorScheme),
                ],
              ),

              // Summary preview
              if (encounter.summary != null) ...[
                const SizedBox(height: 12),
                Text(
                  encounter.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],

              // Topics
              if (topicChips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: topicChips
                      .map((topic) => Chip(
                            label: Text(topic),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              color: colorScheme.primary,
                            ),
                            backgroundColor: colorScheme.primaryContainer,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ],

              // Transcript indicator
              if (hasTranscript) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.notes_rounded,
                        size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '${encounter.transcript.length} transcript segments',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(EncounterStatus status, ColorScheme colorScheme) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case EncounterStatus.active:
        bg = Colors.green.withAlpha(26);
        fg = Colors.green;
        label = 'Active';
        break;
      case EncounterStatus.completed:
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
        label = 'Done';
        break;
      case EncounterStatus.cancelled:
        bg = colorScheme.errorContainer;
        fg = colorScheme.onErrorContainer;
        label = 'Cancelled';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
