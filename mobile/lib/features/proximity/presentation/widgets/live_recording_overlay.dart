import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/recording/presentation/providers/live_recording_provider.dart';
import 'package:linkless/features/proximity/presentation/widgets/elapsed_timer_text.dart';
import 'package:linkless/features/proximity/presentation/widgets/pulsing_recording_dot.dart';

/// Full-screen overlay shown when a proximity-triggered recording is active.
///
/// Displays the peer's profile photo (or initials fallback), a pulsing red
/// recording dot, and a live elapsed timer. The user can minimize to the
/// compact banner via the top-right button.
class LiveRecordingOverlay extends ConsumerWidget {
  const LiveRecordingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerAsync = ref.watch(activePeerProfileProvider);

    return Material(
      color: AppColors.backgroundDarker,
      child: SafeArea(
        child: Stack(
          children: [
            // Minimize button
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                color: AppColors.textSecondary,
                onPressed: () {
                  ref.read(liveRecordingOverlayProvider.notifier).state = false;
                  ref.read(liveRecordingBannerProvider.notifier).state = true;
                },
              ),
            ),
            // Centered content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Profile photo / initials
                  peerAsync.when(
                    data: (profile) => _buildAvatar(profile?.photoUrl,
                        profile?.initials, profile?.displayName),
                    loading: () => _buildAvatar(null, null, null),
                    error: (_, __) => _buildAvatar(null, null, null),
                  ),
                  const SizedBox(height: 24),
                  // Display name
                  peerAsync.when(
                    data: (profile) => Text(
                      profile != null
                          ? 'Linking with ${profile.initials ?? '...'}'
                          : 'Linking...',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    loading: () => const Text(
                      'Linking...',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    error: (_, __) => const Text(
                      'Linking...',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Recording indicator row
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulsingRecordingDot(size: 12),
                      SizedBox(width: 8),
                      Text(
                        'Recording',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Elapsed timer
                  const ElapsedTimerText(
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 40,
                      fontWeight: FontWeight.w300,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, String? initials, String? name) {
    final fallbackText = initials ?? (name != null ? name[0].toUpperCase() : '?');

    return CircleAvatar(
      radius: 60,
      backgroundColor: AppColors.backgroundCard,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
      child: photoUrl == null
          ? Text(
              fallbackText,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
