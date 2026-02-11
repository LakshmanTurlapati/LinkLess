import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/map/domain/models/map_conversation.dart';
import 'package:linkless/features/recording/presentation/providers/conversation_detail_provider.dart';
import 'package:linkless/features/recording/presentation/widgets/summary_widget.dart';
import 'package:linkless/features/recording/presentation/widgets/transcript_widget.dart';

/// Bottom sheet that displays conversation details when a map pin is tapped.
///
/// Shows the peer's identity (photo/initials, name), conversation metadata
/// (date, duration), and fetches the transcript and AI summary from the
/// backend via [conversationDetailProvider].
class ConversationDetailSheet extends ConsumerWidget {
  const ConversationDetailSheet({
    super.key,
    required this.conversation,
  });

  /// The map conversation whose details to display.
  final MapConversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(conversationDetailProvider(conversation.id));
    final peerUserId = detail.whenOrNull(
      data: (data) => data?['peer_user_id'] as String?,
    );
    final canViewProfile =
        !conversation.peerIsAnonymous && peerUserId != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Peer info row
              _buildPeerInfoRow(context, canViewProfile, peerUserId),

              const SizedBox(height: 12),

              // Date and duration row
              _buildMetadataRow(context),

              const Divider(height: 24),

              // Transcript and summary from backend
              _buildTranscriptSummary(context, ref, detail),
            ],
          ),
        );
      },
    );
  }

  /// Builds the peer identity row with avatar and display name.
  ///
  /// When [canViewProfile] is true the row becomes tappable and navigates
  /// to the encounter card for [peerUserId].
  Widget _buildPeerInfoRow(
    BuildContext context,
    bool canViewProfile,
    String? peerUserId,
  ) {
    final displayName = _peerDisplayName;
    final initialsText = conversation.peerInitials ?? '?';

    final row = Row(
      children: [
        // Circular avatar with photo or initials
        CircleAvatar(
          radius: 24,
          backgroundColor: conversation.peerIsAnonymous
              ? AppColors.textTertiary
              : AppColors.accentBlue,
          backgroundImage: (!conversation.peerIsAnonymous &&
                  conversation.peerPhotoUrl != null &&
                  conversation.peerPhotoUrl!.isNotEmpty)
              ? NetworkImage(conversation.peerPhotoUrl!)
              : null,
          child: (conversation.peerIsAnonymous ||
                  conversation.peerPhotoUrl == null ||
                  conversation.peerPhotoUrl!.isEmpty)
              ? Text(
                  initialsText,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (conversation.peerIsAnonymous)
                Text(
                  'Anonymous',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              if (canViewProfile)
                Text(
                  'View Profile',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.accentBlue,
                      ),
                ),
            ],
          ),
        ),
        if (canViewProfile)
          const Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
          ),
      ],
    );

    if (!canViewProfile) return row;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        context.push(
          '/profile/encounter/$peerUserId?conversationId=${conversation.id}',
        );
      },
      child: row,
    );
  }

  /// Builds the date and duration metadata row.
  Widget _buildMetadataRow(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          _formatDateTime(conversation.startedAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(width: 16),
        const Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          conversation.displayDuration,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }

  /// Displays the transcript and summary from the pre-fetched detail data.
  Widget _buildTranscriptSummary(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, dynamic>?> detail,
  ) {
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
                'Loading details...',
                style: TextStyle(color: AppColors.textTertiary),
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
                'Could not load conversation details',
                style: TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ref.invalidate(conversationDetailProvider(conversation.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        if (data == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No details available',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          );
        }

        final hasTranscript = data['transcript'] != null;
        final hasSummary = data['summary'] != null;

        if (!hasTranscript && !hasSummary) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Transcript and summary not yet available',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTranscript)
              TranscriptWidget(
                transcriptData:
                    data['transcript'] as Map<String, dynamic>,
              ),
            if (hasTranscript && hasSummary) const SizedBox(height: 16),
            if (hasSummary)
              SummaryWidget(
                summaryData:
                    data['summary'] as Map<String, dynamic>,
              ),
          ],
        );
      },
    );
  }

  /// The display name for the peer, with fallbacks.
  String get _peerDisplayName {
    if (conversation.peerIsAnonymous) return 'Anonymous';
    if (conversation.peerDisplayName != null &&
        conversation.peerDisplayName!.isNotEmpty) {
      return conversation.peerDisplayName!;
    }
    return 'Unknown';
  }

  /// Simple date+time formatting without intl dependency.
  String _formatDateTime(DateTime date) {
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
