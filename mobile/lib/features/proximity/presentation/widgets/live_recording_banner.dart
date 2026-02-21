import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/recording/presentation/providers/live_recording_provider.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';
import 'package:linkless/features/proximity/presentation/widgets/elapsed_timer_text.dart';
import 'package:linkless/features/proximity/presentation/widgets/pulsing_recording_dot.dart';

/// Compact recording banner displayed at the top of the screen.
///
/// Shows the peer's initials, a pulsing red dot, "Recording" text, and an
/// elapsed timer. Tapping the banner re-opens the full-screen overlay.
///
/// During the pending state (identity chain resolving), the profile is null
/// and a placeholder '?' is shown. Once the identity chain completes and
/// recording starts, the resolved profile data is displayed.
class LiveRecordingBanner extends ConsumerWidget {
  const LiveRecordingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activePeerProfileProvider);

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
                  // Peer initials avatar
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.accentBlue,
                    backgroundImage: profile?.photoUrl != null
                        ? NetworkImage(profile!.photoUrl!)
                        : null,
                    child: profile?.photoUrl == null
                        ? Text(
                            profile?.initials ??
                                (profile?.displayName != null
                                    ? profile!.displayName![0].toUpperCase()
                                    : '?'),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
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
}
