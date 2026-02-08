import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:linkless/features/profile/domain/models/social_link.dart';

/// A tappable list tile that opens a social platform profile URL.
///
/// Displays the platform icon, name, and handle. Tapping the tile
/// opens the URL using [url_launcher], which will deep-link to the
/// native app if installed or fall back to the browser.
class SocialLinkButton extends StatelessWidget {
  final String platform;
  final String handle;
  final String url;

  const SocialLinkButton({
    super.key,
    required this.platform,
    required this.handle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    // Try to resolve the platform to get the icon and display name.
    SocialPlatform? socialPlatform;
    try {
      socialPlatform = SocialPlatform.fromString(platform);
    } catch (_) {
      // Unknown platform -- use fallback icon.
    }

    return ListTile(
      leading: Icon(
        socialPlatform?.iconData ?? Icons.link,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(socialPlatform?.displayName ?? platform),
      subtitle: Text('@$handle'),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _openUrl(context),
    );
  }

  Future<void> _openUrl(BuildContext context) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $platform link')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $platform link')),
        );
      }
    }
  }
}
