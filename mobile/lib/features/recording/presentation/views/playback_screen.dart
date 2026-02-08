import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/recording/domain/models/conversation_local.dart';
import 'package:linkless/features/recording/presentation/providers/conversation_detail_provider.dart';
import 'package:linkless/features/recording/presentation/providers/playback_provider.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';
import 'package:linkless/features/recording/presentation/widgets/audio_player_widget.dart';
import 'package:linkless/features/recording/presentation/widgets/summary_widget.dart';
import 'package:linkless/features/recording/presentation/widgets/transcript_widget.dart';

/// Screen displaying conversation metadata and audio playback controls.
///
/// Takes a [conversationId] parameter (from the route), looks up the
/// conversation from [conversationListProvider], and shows metadata
/// (peer, date, duration, location) along with an audio player widget
/// if the conversation has an associated audio file.
class PlaybackScreen extends ConsumerWidget {
  const PlaybackScreen({
    super.key,
    required this.conversationId,
  });

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationList = ref.watch(conversationListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
      ),
      body: conversationList.when(
        data: (conversations) {
          final conversation = _findConversation(conversations);
          if (conversation == null) {
            return const Center(
              child: Text('Conversation not found'),
            );
          }
          return _buildContent(context, ref, conversation);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }

  ConversationLocal? _findConversation(List<ConversationLocal> conversations) {
    for (final c in conversations) {
      if (c.id == conversationId) return c;
    }
    return null;
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ConversationLocal conversation,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetadataCard(context, conversation),
          const SizedBox(height: 24),
          if (conversation.hasAudio)
            _buildAudioSection(ref, conversation)
          else
            _buildNoAudioMessage(),
          const SizedBox(height: 24),
          _buildTranscriptSummarySection(context, ref, conversation),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(
    BuildContext context,
    ConversationLocal conversation,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _metadataRow('Peer', conversation.peerId),
            _metadataRow('Date', _formatDate(conversation.startedAt)),
            _metadataRow('Duration', conversation.displayDuration),
            _metadataRow(
              'Status',
              conversation.isComplete ? 'Complete' : 'In progress',
            ),
            if (conversation.latitude != null &&
                conversation.longitude != null)
              _metadataRow(
                'Location',
                '${conversation.latitude!.toStringAsFixed(4)}, '
                    '${conversation.longitude!.toStringAsFixed(4)}',
              ),
            _metadataRow('Sync', conversation.syncStatus),
          ],
        ),
      ),
    );
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSection(WidgetRef ref, ConversationLocal conversation) {
    final player = ref.watch(playbackPlayerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audio Playback',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        AudioPlayerWidget(
          player: player,
          filePath: conversation.audioFilePath!,
        ),
      ],
    );
  }

  Widget _buildNoAudioMessage() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(
              Icons.mic_off,
              size: 48,
              color: Colors.grey,
            ),
            SizedBox(height: 12),
            Text(
              'No audio recorded for this conversation',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the transcript and summary section by fetching detail from the
  /// backend API. Shows loading, error, and status-aware states.
  Widget _buildTranscriptSummarySection(
    BuildContext context,
    WidgetRef ref,
    ConversationLocal conversation,
  ) {
    final detail = ref.watch(conversationDetailProvider(conversationId));

    return detail.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 12),
              Text(
                'Loading transcript...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              const Text(
                'Could not load transcript',
                style: TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ref.invalidate(conversationDetailProvider(conversationId));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        final hasTranscript = data != null && data['transcript'] != null;
        final hasSummary = data != null && data['summary'] != null;

        if (!hasTranscript && !hasSummary) {
          return _buildStatusMessage(context, conversation);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTranscript)
              TranscriptWidget(
                transcriptData:
                    data!['transcript'] as Map<String, dynamic>,
              ),
            if (hasTranscript && hasSummary) const SizedBox(height: 16),
            if (hasSummary)
              SummaryWidget(
                summaryData:
                    data!['summary'] as Map<String, dynamic>,
              ),
          ],
        );
      },
    );
  }

  /// Shows a status-aware message based on the conversation sync status
  /// when transcript and summary are not yet available.
  Widget _buildStatusMessage(
    BuildContext context,
    ConversationLocal conversation,
  ) {
    final String message;
    final IconData icon;
    final Color color;

    switch (conversation.syncStatus) {
      case 'pending':
      case 'uploading':
        message = 'Uploading audio...';
        icon = Icons.cloud_upload_outlined;
        color = Colors.blue;
      case 'uploaded':
      case 'transcribing':
        message = 'Transcribing conversation...';
        icon = Icons.hearing;
        color = Colors.orange;
      case 'completed':
        message = 'Processing complete';
        icon = Icons.check_circle_outline;
        color = Colors.green;
      case 'failed':
        message = 'Processing failed';
        icon = Icons.error_outline;
        color = Colors.red;
      default:
        message = 'Waiting to sync...';
        icon = Icons.hourglass_empty;
        color = Colors.grey;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Simple date formatting without intl dependency.
  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[date.month - 1];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$month ${date.day}, ${date.year} $hour:$minute $period';
  }
}
