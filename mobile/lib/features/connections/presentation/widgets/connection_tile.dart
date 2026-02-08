import 'package:flutter/material.dart';

import 'package:linkless/features/connections/domain/models/connection.dart';
import 'package:linkless/features/connections/presentation/widgets/social_link_button.dart';

/// An expandable tile displaying a connected peer with their exchanged
/// social links.
///
/// Shows the peer's avatar (photo or initials), display name, and the
/// number of exchanged social links as a subtitle. Expands on tap to
/// reveal [SocialLinkButton] widgets for each exchanged link.
class ConnectionTile extends StatelessWidget {
  final Connection connection;
  final VoidCallback? onTap;

  const ConnectionTile({
    super.key,
    required this.connection,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkCount = connection.socialLinks.length;
    final subtitle = linkCount == 1
        ? '1 social link exchanged'
        : '$linkCount social links exchanged';

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: connection.peerPhotoUrl != null
            ? NetworkImage(connection.peerPhotoUrl!)
            : null,
        child: connection.peerPhotoUrl == null
            ? Text(
                connection.peerInitials ?? '?',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              )
            : null,
      ),
      title: Text(connection.displayName),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        if (connection.socialLinks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No social links shared'),
          )
        else
          ...connection.socialLinks.map(
            (link) => SocialLinkButton(
              platform: link.platform,
              handle: link.handle,
              url: link.platformUrl,
            ),
          ),
      ],
    );
  }
}
