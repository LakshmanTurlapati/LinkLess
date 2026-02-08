import 'package:flutter/material.dart';

/// Modal bottom sheet dialog prompting the user to connect with a peer.
///
/// Shown on the PlaybackScreen when a conversation has a peer_user_id,
/// a completed transcript, and no existing ConnectionRequest. Provides
/// accept and decline callbacks for the connection flow.
class ConnectPromptDialog extends StatelessWidget {
  final String? peerDisplayName;
  final String? peerInitials;
  final String? peerPhotoUrl;
  final String conversationId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const ConnectPromptDialog({
    super.key,
    this.peerDisplayName,
    this.peerInitials,
    this.peerPhotoUrl,
    required this.conversationId,
    required this.onAccept,
    required this.onDecline,
  });

  /// Shows the connect prompt as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? peerDisplayName,
    String? peerInitials,
    String? peerPhotoUrl,
    required String conversationId,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ConnectPromptDialog(
        peerDisplayName: peerDisplayName,
        peerInitials: peerInitials,
        peerPhotoUrl: peerPhotoUrl,
        conversationId: conversationId,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = peerDisplayName ?? peerInitials ?? 'this person';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Peer avatar
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage:
                peerPhotoUrl != null ? NetworkImage(peerPhotoUrl!) : null,
            child: peerPhotoUrl == null
                ? Text(
                    peerInitials ?? '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'Connect with $name?',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Subtitle
          Text(
            'Exchange social links with this person',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onDecline();
                  },
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onAccept();
                  },
                  child: const Text('Connect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
