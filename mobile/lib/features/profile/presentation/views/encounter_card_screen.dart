import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/presentation/providers/peer_profile_provider.dart';

/// Tinder-style encounter card for viewing another user's profile.
///
/// Displays the peer's photo (or a large fallback avatar) in the top half,
/// with a purple header bar showing name and platform chips, and a white
/// body card with social links below.
class EncounterCardScreen extends ConsumerWidget {
  final String userId;

  const EncounterCardScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerAsync = ref.watch(peerProfileProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: peerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Could not load profile',
                style: TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(peerProfileProvider(userId)),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
        data: (profile) => _buildCard(context, profile),
      ),
    );
  }

  Widget _buildCard(BuildContext context, dynamic profile) {
    final screenHeight = MediaQuery.of(context).size.height;
    final photoHeight = screenHeight * 0.5;

    return Stack(
      children: [
        // Top photo section
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: photoHeight,
          child: profile.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: profile.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppColors.backgroundCard,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) =>
                      _buildFallbackAvatar(profile),
                )
              : _buildFallbackAvatar(profile),
        ),

        // Back button overlay
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: AppColors.textPrimary,
                size: 28,
              ),
              onPressed: () => context.pop(),
            ),
          ),
        ),

        // Card overlay from 45% down
        Positioned(
          top: photoHeight - 40,
          left: 0,
          right: 0,
          bottom: 0,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Purple header bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.encounterHeader,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName ?? 'Anonymous',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (profile.socialLinks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: profile.socialLinks
                              .map<Widget>(
                                (SocialLink link) => Chip(
                                  backgroundColor: AppColors.chipBackground,
                                  label: Text(
                                    link.platform.displayName,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // White body card with social links
                Container(
                  color: AppColors.backgroundDark,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile.socialLinks.isNotEmpty) ...[
                        const Text(
                          'Social Links',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...profile.socialLinks.map<Widget>(
                          (SocialLink link) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                link.platform.iconData,
                                color: AppColors.textSecondary,
                              ),
                              title: Text(
                                link.platform.displayName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '@${link.handle}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              tileColor: AppColors.backgroundCard,
                            ),
                          ),
                        ),
                      ] else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No social links shared',
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom-left dismiss button
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close,
                  color: AppColors.backgroundDark,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackAvatar(dynamic profile) {
    return Container(
      color: AppColors.backgroundCard,
      child: Center(
        child: CircleAvatar(
          radius: 60,
          backgroundColor: AppColors.accentPurple,
          child: Text(
            profile.initials ?? '?',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
