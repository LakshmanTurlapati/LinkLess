import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/presentation/view_models/profile_view_model.dart';
import 'package:linkless/features/profile/presentation/widgets/anonymous_mode_toggle.dart';
import 'package:linkless/features/profile/presentation/widgets/avatar_picker.dart';
import 'package:linkless/features/profile/presentation/widgets/social_link_tile.dart';

/// Edit screen for an existing user profile.
///
/// Allows editing: display name, profile photo, social links
/// (Instagram, LinkedIn, X, Snapchat), and anonymous mode toggle.
///
/// Photo upload happens immediately on selection (no save required).
/// Anonymous mode toggle fires immediately (optimistic update).
/// Name and social links are saved on "Save" button tap.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  // Controllers for each social platform
  final _instagramController = TextEditingController();
  final _linkedinController = TextEditingController();
  final _xController = TextEditingController();
  final _snapchatController = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _instagramController.dispose();
    _linkedinController.dispose();
    _xController.dispose();
    _snapchatController.dispose();
    super.dispose();
  }

  /// Initializes form fields from the current profile state.
  void _initializeFromProfile(ProfileState profileState) {
    if (_initialized || profileState.profile == null) return;
    _initialized = true;

    final profile = profileState.profile!;
    _nameController.text = profile.displayName ?? '';

    // Pre-fill social link controllers
    for (final link in profile.socialLinks) {
      switch (link.platform) {
        case SocialPlatform.instagram:
          _instagramController.text = link.handle;
        case SocialPlatform.linkedin:
          _linkedinController.text = link.handle;
        case SocialPlatform.x:
          _xController.text = link.handle;
        case SocialPlatform.snapchat:
          _snapchatController.text = link.handle;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final theme = Theme.of(context);

    // Initialize form fields from profile data
    _initializeFromProfile(profileState);

    // Listen for errors to show snackbar
    ref.listen<ProfileState>(profileProvider, (previous, next) {
      if (next.error != null && previous?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(profileProvider.notifier).clearError();
      }
    });

    final profile = profileState.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: profileState.isLoading && profile == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar picker (centered)
                      Center(
                        child: AvatarPicker(
                          photoUrl: profile?.photoUrl,
                          initials: profile?.initials,
                          isUploading: profileState.isUploading,
                          onPhotoSelected: (source) {
                            ref
                                .read(profileProvider.notifier)
                                .uploadPhoto(source);
                          },
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Display name field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          hintText: 'Enter your name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'Display name is required';
                          }
                          if (trimmed.length > 100) {
                            return 'Display name must be 100 characters or less';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Social Links section
                      Text(
                        'Social Links',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add your social handles so connections can find you.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),

                      SocialLinkTile(
                        platform: SocialPlatform.instagram,
                        currentHandle: _instagramController.text,
                        controller: _instagramController,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 8),
                      SocialLinkTile(
                        platform: SocialPlatform.linkedin,
                        currentHandle: _linkedinController.text,
                        controller: _linkedinController,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 8),
                      SocialLinkTile(
                        platform: SocialPlatform.x,
                        currentHandle: _xController.text,
                        controller: _xController,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 8),
                      SocialLinkTile(
                        platform: SocialPlatform.snapchat,
                        currentHandle: _snapchatController.text,
                        controller: _snapchatController,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 32),

                      // Privacy section
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Privacy',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),

                      // Anonymous mode toggle (fires immediately)
                      AnonymousModeToggle(
                        isAnonymous: profile?.isAnonymous ?? false,
                        onToggled: (_) {
                          ref
                              .read(profileProvider.notifier)
                              .toggleAnonymousMode();
                        },
                      ),
                      const SizedBox(height: 32),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: profileState.isSaving
                              ? null
                              : _handleSave,
                          child: profileState.isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(profileProvider.notifier);
    final currentProfile = ref.read(profileProvider).profile;
    bool success = true;

    // Update display name if changed
    final newName = _nameController.text.trim();
    if (currentProfile != null && newName != currentProfile.displayName) {
      success = await notifier.updateDisplayName(newName);
    }

    if (!success) return;

    // Collect social links from controllers
    final links = <SocialLink>[];

    final instagramHandle = _instagramController.text.trim();
    if (instagramHandle.isNotEmpty) {
      links.add(SocialLink(
        platform: SocialPlatform.instagram,
        handle: instagramHandle,
      ));
    }

    final linkedinHandle = _linkedinController.text.trim();
    if (linkedinHandle.isNotEmpty) {
      links.add(SocialLink(
        platform: SocialPlatform.linkedin,
        handle: linkedinHandle,
      ));
    }

    final xHandle = _xController.text.trim();
    if (xHandle.isNotEmpty) {
      links.add(SocialLink(
        platform: SocialPlatform.x,
        handle: xHandle,
      ));
    }

    final snapchatHandle = _snapchatController.text.trim();
    if (snapchatHandle.isNotEmpty) {
      links.add(SocialLink(
        platform: SocialPlatform.snapchat,
        handle: snapchatHandle,
      ));
    }

    success = await notifier.saveSocialLinks(links);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
