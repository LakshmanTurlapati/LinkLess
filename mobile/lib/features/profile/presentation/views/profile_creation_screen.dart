import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/profile/presentation/view_models/profile_view_model.dart';
import 'package:linkless/features/profile/presentation/widgets/avatar_picker.dart';

/// First-time profile setup screen shown after authentication.
///
/// Requires the user to enter a display name (1-100 characters).
/// Photo is optional but encouraged via the avatar picker.
/// After creation, navigates to the main app.
class ProfileCreationScreen extends ConsumerStatefulWidget {
  const ProfileCreationScreen({super.key});

  @override
  ConsumerState<ProfileCreationScreen> createState() =>
      _ProfileCreationScreenState();
}

class _ProfileCreationScreenState
    extends ConsumerState<ProfileCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final theme = Theme.of(context);

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),

                // Welcome text
                Text(
                  'Set up your profile',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add a name and photo so others can recognize you.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Avatar picker (optional photo)
                AvatarPicker(
                  photoUrl: profileState.profile?.photoUrl,
                  initials: null,
                  isUploading: profileState.isUploading,
                  onPhotoSelected: (source) {
                    ref.read(profileProvider.notifier).uploadPhoto(source);
                  },
                ),
                const SizedBox(height: 32),

                // Display name field (required) -- pill-shaped
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'Enter your name',
                    filled: true,
                    fillColor: AppColors.inputBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: AppColors.accentPurple,
                        width: 2,
                      ),
                    ),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
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
                  onFieldSubmitted: (_) => _handleCreate(),
                ),
                const SizedBox(height: 32),

                // Create button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: profileState.isLoading ? null : _handleCreate,
                    child: profileState.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Profile'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final success =
        await ref.read(profileProvider.notifier).createProfile(name);

    if (success && mounted) {
      // Navigate to main app after profile creation
      context.go('/profile');
    }
  }
}
