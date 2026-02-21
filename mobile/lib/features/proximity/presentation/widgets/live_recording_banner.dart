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

/// Compact recording banner displayed at the top of the screen.
///
/// During the pending state (identity chain resolving), displays a pulsing
/// [ShimmerAvatar] placeholder. Once the identity chain completes and the
/// peer profile is resolved, an [AnimatedSwitcher] fades from shimmer to
/// the resolved profile photo (via [CachedNetworkImage]) or initials.
///
/// Shows the peer avatar, a pulsing red dot, "Recording" text, and an
/// elapsed timer. Tapping the banner re-opens the full-screen overlay.
class LiveRecordingBanner extends ConsumerWidget {
  const LiveRecordingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(recordingStateProvider);
    final currentState = stateAsync.valueOrNull;
    final profile = ref.watch(activePeerProfileProvider);

    final isLoading =
        currentState == RecordingState.pending || profile == null;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: GestureDetector(
          onTap: () {
            ref.read(liveRecordingBannerProvider.notifier).state = false;
            ref.read(liveRecordingOverlayProvider.notifier).state = true;
          },
          child: AnimatedSlide(
            offset: Offset.zero,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // Peer avatar with shimmer/resolved fade
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: isLoading
                        ? const ShimmerAvatar(
                            key: ValueKey('shimmer-banner'),
                            radius: 12,
                          )
                        : _buildBannerAvatar(profile),
                  ),
                  const SizedBox(width: 10),
                  const PulsingRecordingDot(size: 8),
                  const SizedBox(width: 6),
                  const Text(
                    'Recording',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const ElapsedTimerText(
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the resolved peer avatar for the compact banner.
  ///
  /// Uses [CachedNetworkImageProvider] for photo display with caching.
  /// Anonymous peers always have initials and photoUrl from the backend.
  Widget _buildBannerAvatar(UserProfile? profile) {
    return CircleAvatar(
      key: const ValueKey('resolved-banner'),
      radius: 12,
      backgroundColor: AppColors.accentBlue,
      backgroundImage: profile?.photoUrl != null
          ? CachedNetworkImageProvider(profile!.photoUrl!)
          : null,
      child: profile?.photoUrl == null
          ? Text(
              profile?.initials ?? '?',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
