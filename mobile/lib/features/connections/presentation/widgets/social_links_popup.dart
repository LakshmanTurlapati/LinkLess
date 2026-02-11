import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/connections/domain/models/connection.dart';
import 'package:linkless/features/connections/presentation/widgets/social_link_button.dart';

/// A modal dialog shown when a mutual match is confirmed after accepting
/// a connection request.
///
/// Displays the peer's avatar, name, a celebratory message, and their
/// exchanged social links with tap-to-open support.
class SocialLinksPopup extends StatelessWidget {
  final String peerDisplayName;
  final String? peerInitials;
  final String? peerPhotoUrl;
  final List<ExchangedSocialLink> exchangedLinks;

  const SocialLinksPopup({
    super.key,
    required this.peerDisplayName,
    this.peerInitials,
    this.peerPhotoUrl,
    required this.exchangedLinks,
  });

  /// Shows the popup as a modal dialog.
  static Future<void> show(
    BuildContext context, {
    required String peerDisplayName,
    String? peerInitials,
    String? peerPhotoUrl,
    required List<ExchangedSocialLink> exchangedLinks,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SocialLinksPopup(
        peerDisplayName: peerDisplayName,
        peerInitials: peerInitials,
        peerPhotoUrl: peerPhotoUrl,
        exchangedLinks: exchangedLinks,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: AppColors.backgroundCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Peer avatar
            CircleAvatar(
              radius: 36,
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

            // Success message
            Text(
              "You're linked!",
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You and $peerDisplayName are now connected.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Exchanged social links
            if (exchangedLinks.isNotEmpty) ...[
              Text(
                'Their social links',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              ...exchangedLinks.map(
                (link) => SocialLinkButton(
                  platform: link.platform,
                  handle: link.handle,
                  url: link.platformUrl,
                ),
              ),
            ] else
              Text(
                'No social links shared yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),

            const SizedBox(height: 20),

            // Dismiss button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Awesome!'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
