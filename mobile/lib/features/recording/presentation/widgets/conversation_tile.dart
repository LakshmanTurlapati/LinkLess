import 'package:flutter/material.dart';

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
      trailing: _buildStatusIcon(),
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

  /// Status icon based on conversation state:
  /// - Play icon if complete with audio
  /// - Red dot if still recording (no endedAt)
  /// - Orange warning if completed without audio
  Widget _buildStatusIcon() {
    if (conversation.isComplete && conversation.hasAudio) {
      return const Icon(Icons.play_circle_outline, color: Colors.green);
    }
    if (!conversation.isComplete) {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      );
    }
    // Completed but no audio
    return const Icon(Icons.warning_amber_rounded, color: Colors.orange);
  }
}
