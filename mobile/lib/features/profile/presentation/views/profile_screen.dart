import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/presentation/view_models/profile_view_model.dart';
import 'package:linkless/features/profile/presentation/widgets/invisible_mode_toggle.dart';

/// Main profile tab screen.
///
/// Displays the current user's profile information and provides
/// navigation to the edit screen. Also includes a logout button.
///
/// Loads profile data on first build and shows a loading indicator
/// while fetching.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Load profile data when screen is first shown
    Future.microtask(() {
      ref.read(profileProvider.notifier).loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final profile = profileState.profile;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (profile != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
              onPressed: () => context.push('/profile/edit'),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      body: _buildBody(theme, profileState, profile),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ProfileState profileState,
    dynamic profile,
  ) {
    // Loading state
    if (profileState.isLoading && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error state with no profile (likely needs creation)
    if (profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_add_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Set up your profile',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a profile so others can find and connect with you.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/profile/create'),
                icon: const Icon(Icons.person_add),
                label: const Text('Create Profile'),
              ),
            ],
          ),
        ),
      );
    }

    // Profile loaded -- display it
    return RefreshIndicator(
      onRefresh: () => ref.read(profileProvider.notifier).loadProfile(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Profile photo
            CircleAvatar(
              radius: 60,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              backgroundImage: profile.photoUrl != null
                  ? CachedNetworkImageProvider(profile.photoUrl!)
                  : null,
              child: profile.photoUrl == null
                  ? Text(
                      profile.initials ?? '?',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),

            // Display name (or anonymous indicator)
            if (profile.isAnonymous) ...[
              Text(
                profile.initials ?? 'Anonymous',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Anonymous mode',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ] else ...[
              Text(
                profile.displayName ?? 'No name',
                style: theme.textTheme.headlineSmall,
              ),
            ],
            const SizedBox(height: 32),

            // Social links section
            if (profile.socialLinks.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Social Links',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              ...profile.socialLinks.map<Widget>(
                (SocialLink link) => ListTile(
                  leading: Icon(link.platform.iconData),
                  title: Text(link.platform.displayName),
                  subtitle: Text('@${link.handle}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],

            // Privacy section
            const Divider(),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Privacy',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const InvisibleModeToggle(),
            const SizedBox(height: 16),

            // Edit profile button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/profile/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
