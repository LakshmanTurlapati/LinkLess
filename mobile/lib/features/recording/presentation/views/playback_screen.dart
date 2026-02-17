import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/connections/presentation/providers/connection_provider.dart';
import 'package:linkless/features/connections/presentation/widgets/connect_prompt_dialog.dart';
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
          const SizedBox(height: 24),
          _buildConnectionSection(context, ref, conversation),
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
                color: AppColors.textSecondary,
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
            color: AppColors.textSecondary,
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
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'No audio recorded for this conversation',
              style: TextStyle(color: AppColors.textSecondary),
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
    final detailId = conversation.serverId ?? conversationId;
    final detail = ref.watch(conversationDetailProvider(detailId));

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
                style: TextStyle(color: AppColors.textSecondary),
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
              Text(
                'Could not load transcript',
                style: TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ref.invalidate(conversationDetailProvider(detailId));
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
        color = AppColors.accentBlue;
      case 'uploaded':
      case 'transcribing':
        message = 'Transcribing conversation...';
        icon = Icons.hearing;
        color = AppColors.warning;
      case 'completed':
        message = 'Processing complete';
        icon = Icons.check_circle_outline;
        color = AppColors.success;
      case 'failed':
        message = 'Processing failed';
        icon = Icons.error_outline;
        color = AppColors.error;
      default:
        message = 'Waiting to sync...';
        icon = Icons.hourglass_empty;
        color = AppColors.textSecondary;
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

  /// Builds the connection UI section with two-gate eligibility check.
  ///
  /// Gate 1: Conversation must have a peer_user_id AND a completed transcript.
  /// Gate 2: Connection status determines what UI to show (prompt, chip, etc).
  Widget _buildConnectionSection(
    BuildContext context,
    WidgetRef ref,
    ConversationLocal conversation,
  ) {
    final detailId = conversation.serverId ?? conversationId;
    final detail = ref.watch(conversationDetailProvider(detailId));

    return detail.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();

        // Gate 1: Must have peer_user_id AND transcript
        final peerUserId = data['peer_user_id'] as String?;
        final hasTranscript = data['transcript'] != null;
        if (peerUserId == null || !hasTranscript) {
          return const SizedBox.shrink();
        }

        // Extract peer info for the connect prompt
        final peerDisplayName = data['peer_display_name'] as String?;
        final peerInitials = data['peer_initials'] as String?;
        final peerPhotoUrl = data['peer_photo_url'] as String?;
        final currentUserId = data['user_id'] as String?;

        // Gate 2: Status-based rendering
        return _buildConnectionStatus(
          context,
          ref,
          peerDisplayName: peerDisplayName,
          peerInitials: peerInitials,
          peerPhotoUrl: peerPhotoUrl,
          currentUserId: currentUserId,
        );
      },
    );
  }

  /// Renders connection UI based on the current connection status.
  Widget _buildConnectionStatus(
    BuildContext context,
    WidgetRef ref, {
    String? peerDisplayName,
    String? peerInitials,
    String? peerPhotoUrl,
    String? currentUserId,
  }) {
    final connectionStatus =
        ref.watch(connectionStatusProvider(conversationId));

    return connectionStatus.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (request) {
        // (a) No request exists: show connect prompt banner
        if (request == null) {
          return _buildConnectBanner(
            context,
            ref,
            peerDisplayName: peerDisplayName,
            peerInitials: peerInitials,
            peerPhotoUrl: peerPhotoUrl,
          );
        }

        // (d) Accepted: show connected chip
        if (request.isAccepted) {
          return _buildStatusChip(
            context,
            icon: Icons.check_circle,
            label: 'Connected',
            color: AppColors.success,
          );
        }

        // (e) Declined: show nothing
        if (request.isDeclined) {
          return const SizedBox.shrink();
        }

        // (b) Pending and current user is the requester: show sent chip
        if (request.isPending && currentUserId == request.requesterId) {
          return _buildStatusChip(
            context,
            icon: Icons.send,
            label: 'Connection request sent',
            color: AppColors.accentBlue,
          );
        }

        // (c) Pending and current user is the recipient: show accept/decline
        if (request.isPending && currentUserId == request.recipientId) {
          return _buildIncomingRequestCard(
            context,
            ref,
            request.id,
            peerDisplayName: peerDisplayName,
            peerInitials: peerInitials,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  /// Banner card inviting the user to connect with the peer.
  Widget _buildConnectBanner(
    BuildContext context,
    WidgetRef ref, {
    String? peerDisplayName,
    String? peerInitials,
    String? peerPhotoUrl,
  }) {
    final name = peerDisplayName ?? peerInitials ?? 'this person';
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ConnectPromptDialog.show(
            context,
            peerDisplayName: peerDisplayName,
            peerInitials: peerInitials,
            peerPhotoUrl: peerPhotoUrl,
            conversationId: conversationId,
            onAccept: () async {
              await sendConnectionRequest(ref, conversationId);
            },
            onDecline: () {
              // No action needed -- user just dismissed the prompt.
              // The prompt won't re-appear because the request will
              // now exist with status 'pending'.
            },
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.person_add,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect with $name',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Exchange social links',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card for incoming connection request with accept/decline buttons.
  Widget _buildIncomingRequestCard(
    BuildContext context,
    WidgetRef ref,
    String requestId, {
    String? peerDisplayName,
    String? peerInitials,
  }) {
    final name = peerDisplayName ?? peerInitials ?? 'Someone';
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_add,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$name wants to connect',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Accept to exchange social links',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await declineConnection(
                      ref,
                      requestId,
                      conversationId: conversationId,
                    );
                  },
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await acceptConnection(
                      ref,
                      requestId,
                      conversationId: conversationId,
                    );
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Small status chip for connection state indication.
  Widget _buildStatusChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Chip(
          avatar: Icon(icon, size: 18, color: color),
          label: Text(label),
          backgroundColor: color.withValues(alpha: 0.1),
          side: BorderSide.none,
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
