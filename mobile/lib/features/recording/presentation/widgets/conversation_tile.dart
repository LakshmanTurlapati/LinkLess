import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/recording/domain/models/conversation_local.dart';

/// A list tile displaying a conversation summary.
///
/// Shows peer ID, formatted date, duration, and a status icon indicating
/// whether the conversation has audio, is actively recording, or errored.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
  });

  final ConversationLocal conversation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.accentBlue,
        child: Text(
          conversation.peerId.isNotEmpty
              ? conversation.peerId[0].toUpperCase()
              : '?',
        ),
      ),
      title: Text(
        _truncatedPeerId,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatDate(conversation.startedAt)} -- ${conversation.displayDuration}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSyncStatusIcon(),
          const SizedBox(width: 8),
          _buildStatusIcon(),
        ],
      ),
      onTap: onTap,
    );
  }

  /// Peer ID truncated to 8 characters.
  String get _truncatedPeerId {
    if (conversation.peerId.length <= 8) return conversation.peerId;
    return '${conversation.peerId.substring(0, 8)}...';
  }

  /// Simple date formatting without intl dependency.
  ///
  /// Returns format: "Feb 7, 2026 3:45 PM"
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

  /// Sync status icon showing the cloud sync state of the conversation:
  /// - pending: grey cloud upload icon
  /// - uploading: small blue spinner
  /// - uploaded: orange cloud done icon (transcription in progress)
  /// - completed: green check icon
  /// - failed: red error icon
  Widget _buildSyncStatusIcon() {
    switch (conversation.syncStatus) {
      case 'pending':
        return Icon(
          Icons.cloud_upload_outlined,
          size: 18,
          color: AppColors.textSecondary,
        );
      case 'uploading':
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accentBlue,
          ),
        );
      case 'uploaded':
      case 'transcribing':
        return Icon(
          Icons.cloud_done_outlined,
          size: 18,
          color: AppColors.warning,
        );
      case 'completed':
        return Icon(
          Icons.check_circle_outline,
          size: 18,
          color: AppColors.success,
        );
      case 'failed':
        return Icon(
          Icons.error_outline,
          size: 18,
          color: AppColors.error,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Status icon based on conversation state:
  /// - Play icon if complete with audio
  /// - Red dot if still recording (no endedAt)
  /// - Orange warning if completed without audio
  Widget _buildStatusIcon() {
    if (conversation.isComplete && conversation.hasAudio) {
      return Icon(Icons.play_circle_outline, color: AppColors.success);
    }
    if (!conversation.isComplete) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
      );
    }
    // Completed but no audio
    return Icon(Icons.warning_amber_rounded, color: AppColors.warning);
  }
}
