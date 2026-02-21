import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';
import 'package:linkless/features/proximity/presentation/widgets/shimmer_avatar.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';
import 'package:linkless/features/recording/presentation/providers/live_recording_provider.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';
import 'package:linkless/features/proximity/presentation/widgets/elapsed_timer_text.dart';
import 'package:linkless/features/proximity/presentation/widgets/pulsing_recording_dot.dart';

/// Full-screen overlay shown when a proximity-triggered recording is active.
///
/// During the pending state (identity chain resolving), displays a pulsing
/// [ShimmerAvatar] placeholder and "Linking..." text. Once the identity chain
/// completes and the peer profile is resolved, an [AnimatedSwitcher] fades
/// from shimmer to the resolved profile photo (via [CachedNetworkImage]) or
/// initials fallback.
///
/// The user can minimize to the compact banner via the top-right button.
class LiveRecordingOverlay extends ConsumerWidget {
  const LiveRecordingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(recordingStateProvider);
    final currentState = stateAsync.valueOrNull;
    final profile = ref.watch(activePeerProfileProvider);

    final isLoading =
        currentState == RecordingState.pending || profile == null;

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
                  // Profile photo / shimmer placeholder
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: isLoading
                        ? const ShimmerAvatar(
                            key: ValueKey('shimmer'),
                            radius: 60,
                          )
                        : _buildResolvedAvatar(profile),
                  ),
                  const SizedBox(height: 24),
                  // Display name
                  Text(
                    isLoading
                        ? 'Linking...'
                        : 'Linking with ${profile.initials ?? '...'}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
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

  /// Builds the resolved peer avatar with photo or initials fallback.
  ///
  /// Uses [CachedNetworkImageProvider] for photo display, which provides
  /// disk caching and built-in fade-in from CDN. Anonymous peers always
  /// have initials and photoUrl from the backend, so they display correctly
  /// without special handling.
  Widget _buildResolvedAvatar(UserProfile? profile) {
    return CircleAvatar(
      key: const ValueKey('resolved'),
      radius: 60,
      backgroundColor: AppColors.backgroundCard,
      backgroundImage: profile?.photoUrl != null
          ? CachedNetworkImageProvider(profile!.photoUrl!)
          : null,
      child: profile?.photoUrl == null
          ? Text(
              profile?.initials ?? '?',
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
