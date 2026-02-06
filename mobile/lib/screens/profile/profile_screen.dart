import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          authState.whenOrNull(
                data: (user) => user != null
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(user: user),
                            ),
                          );
                        },
                      )
                    : null,
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: authState.when(
        data: (user) {
          if (user == null) return const Center(child: Text('Not logged in'));
          return _buildProfile(context, user, colorScheme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildProfile(
      BuildContext context, UserModel user, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Profile photo
          CircleAvatar(
            radius: 56,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage:
                user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
            child: user.photoUrl == null
                ? Icon(Icons.person, size: 56, color: colorScheme.primary)
                : null,
          ),

          const SizedBox(height: 16),

          // Name
          Text(
            user.displayName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),

          const SizedBox(height: 4),

          // Email
          Text(
            user.email,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 8),

          // Privacy badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: user.privacyMode == PrivacyMode.public_
                  ? colorScheme.primaryContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user.privacyMode == PrivacyMode.public_
                      ? Icons.visibility
                      : Icons.visibility_off,
                  size: 14,
                  color: user.privacyMode == PrivacyMode.public_
                      ? colorScheme.primary
                      : colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  user.privacyMode == PrivacyMode.public_
                      ? 'Public Profile'
                      : 'Anonymous',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: user.privacyMode == PrivacyMode.public_
                        ? colorScheme.primary
                        : colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),

          // Bio
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              user.bio!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Social links
          if (user.socialLinks != null && user.socialLinks!.hasAny)
            _buildSocialLinks(context, user.socialLinks!, colorScheme),
        ],
      ),
    );
  }

  Widget _buildSocialLinks(
      BuildContext context, SocialLinks links, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Social Links',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (links.instagram != null)
              _linkTile(Icons.camera_alt, 'Instagram', '@${links.instagram!}',
                  'https://instagram.com/${links.instagram}', colorScheme),
            if (links.twitter != null)
              _linkTile(Icons.alternate_email, 'Twitter/X', '@${links.twitter!}',
                  'https://x.com/${links.twitter}', colorScheme),
            if (links.linkedin != null)
              _linkTile(Icons.work_outline, 'LinkedIn', links.linkedin!,
                  'https://linkedin.com/in/${links.linkedin}', colorScheme),
            if (links.github != null)
              _linkTile(Icons.code, 'GitHub', links.github!,
                  'https://github.com/${links.github}', colorScheme),
            if (links.website != null)
              _linkTile(Icons.language, 'Website', links.website!,
                  links.website!, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _linkTile(IconData icon, String label, String display, String url,
      ColorScheme colorScheme) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(label),
      subtitle: Text(display),
      trailing: Icon(Icons.open_in_new, size: 16, color: colorScheme.primary),
      onTap: () async {
        final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}
