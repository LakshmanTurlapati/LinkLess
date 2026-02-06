import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/encounter_model.dart';
import '../../models/user_model.dart';
import '../../services/api_client.dart';

/// Provider for a single encounter's details.
final encounterDetailProvider =
    FutureProvider.family<EncounterModel?, String>((ref, encounterId) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getEncounter(encounterId);
});

class EncounterDetailScreen extends ConsumerStatefulWidget {
  final String encounterId;

  const EncounterDetailScreen({super.key, required this.encounterId});

  @override
  ConsumerState<EncounterDetailScreen> createState() =>
      _EncounterDetailScreenState();
}

class _EncounterDetailScreenState
    extends ConsumerState<EncounterDetailScreen> {
  bool _isSummarizing = false;

  Future<void> _summarize() async {
    setState(() => _isSummarizing = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.summarizeEncounter(widget.encounterId);
      // Refresh the encounter data
      ref.refresh(encounterDetailProvider(widget.encounterId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate summary: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final encounterAsync =
        ref.watch(encounterDetailProvider(widget.encounterId));
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encounter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'AI Summary',
            onPressed: _isSummarizing ? null : _summarize,
          ),
        ],
      ),
      body: encounterAsync.when(
        data: (encounter) {
          if (encounter == null) {
            return const Center(child: Text('Encounter not found'));
          }
          return _buildContent(encounter, colorScheme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildContent(EncounterModel encounter, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Peer info card
          _buildPeerCard(encounter, colorScheme),

          const SizedBox(height: 16),

          // Encounter info
          _buildInfoCard(encounter, colorScheme),

          // AI Summary
          if (encounter.summary != null) ...[
            const SizedBox(height: 16),
            _buildSummaryCard(encounter, colorScheme),
          ],

          // Topics
          if (encounter.topics.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTopicsSection(encounter, colorScheme),
          ],

          // Transcript
          if (encounter.transcript.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTranscriptSection(encounter, colorScheme),
          ],

          // Social links
          if (encounter.peerUser?.socialLinks != null &&
              encounter.peerUser!.socialLinks!.hasAny) ...[
            const SizedBox(height: 16),
            _buildSocialLinksCard(encounter.peerUser!, colorScheme),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPeerCard(EncounterModel encounter, ColorScheme colorScheme) {
    final peer = encounter.peerUser;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage:
                  peer?.photoUrl != null ? NetworkImage(peer!.photoUrl!) : null,
              child: peer?.photoUrl == null
                  ? Icon(Icons.person, size: 32, color: colorScheme.primary)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peer?.displayName ?? 'Unknown User',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (peer?.bio != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      peer!.bio!,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (peer?.privacyMode == PrivacyMode.anonymous) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.visibility_off,
                            size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Anonymous user',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(EncounterModel encounter, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoRow(
              Icons.calendar_today,
              'Date',
              DateFormat('MMMM d, yyyy').format(encounter.startedAt),
              colorScheme,
            ),
            const Divider(height: 24),
            _infoRow(
              Icons.access_time,
              'Time',
              DateFormat('h:mm a').format(encounter.startedAt),
              colorScheme,
            ),
            const Divider(height: 24),
            _infoRow(
              Icons.timer_outlined,
              'Duration',
              encounter.formattedDuration,
              colorScheme,
            ),
            if (encounter.proximityDistance != null) ...[
              const Divider(height: 24),
              _infoRow(
                Icons.straighten,
                'Proximity',
                '~${encounter.proximityDistance!.toStringAsFixed(1)}m',
                colorScheme,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(EncounterModel encounter, ColorScheme colorScheme) {
    return Card(
      color: colorScheme.primaryContainer.withAlpha(128),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'AI Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              encounter.summary!,
              style: TextStyle(
                color: colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicsSection(
      EncounterModel encounter, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Topics Discussed',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: encounter.topics
              .map((topic) => Chip(
                    label: Text(topic),
                    backgroundColor: colorScheme.secondaryContainer,
                    labelStyle:
                        TextStyle(color: colorScheme.onSecondaryContainer),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTranscriptSection(
      EncounterModel encounter, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transcript',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        ...encounter.transcript.map((segment) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Text(
                      segment.speakerName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              segment.speakerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('h:mm a').format(segment.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          segment.text,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildSocialLinksCard(UserModel peer, ColorScheme colorScheme) {
    final links = peer.socialLinks!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (links.instagram != null)
              _socialLinkRow(
                  Icons.camera_alt, 'Instagram', links.instagram!, colorScheme),
            if (links.twitter != null)
              _socialLinkRow(
                  Icons.alternate_email, 'Twitter/X', links.twitter!, colorScheme),
            if (links.linkedin != null)
              _socialLinkRow(
                  Icons.work_outline, 'LinkedIn', links.linkedin!, colorScheme),
            if (links.github != null)
              _socialLinkRow(
                  Icons.code, 'GitHub', links.github!, colorScheme),
            if (links.website != null)
              _socialLinkRow(
                  Icons.language, 'Website', links.website!, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _socialLinkRow(
      IconData icon, String label, String handle, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openSocialLink(label, handle),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text(
                handle,
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 14, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSocialLink(String platform, String handle) async {
    String? url;
    switch (platform) {
      case 'Instagram':
        url = 'https://instagram.com/$handle';
        break;
      case 'Twitter/X':
        url = 'https://x.com/$handle';
        break;
      case 'LinkedIn':
        url = 'https://linkedin.com/in/$handle';
        break;
      case 'GitHub':
        url = 'https://github.com/$handle';
        break;
      case 'Website':
        url = handle.startsWith('http') ? handle : 'https://$handle';
        break;
    }

    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
