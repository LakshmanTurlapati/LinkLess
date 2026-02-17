import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/profile/domain/models/user_profile.dart';
import 'package:linkless/features/profile/presentation/providers/peer_profile_provider.dart';
import 'package:linkless/features/recording/domain/models/recording_state.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';

/// Controls whether the full-screen recording overlay is visible.
final liveRecordingOverlayProvider = StateProvider<bool>((ref) => false);

/// Controls whether the compact recording banner is visible.
final liveRecordingBannerProvider = StateProvider<bool>((ref) => false);

/// Ticks every second with the elapsed recording duration.
final recordingElapsedProvider = StreamProvider<Duration>((ref) {
  final recordingState = ref.watch(recordingStateProvider);
  return recordingState.when(
    data: (state) {
      if (state != RecordingState.recording) return const Stream<Duration>.empty();
      final service = ref.read(recordingServiceProvider);
      final startTime = service.recordingStartTime;
      if (startTime == null) return const Stream<Duration>.empty();
      return Stream.periodic(const Duration(seconds: 1), (_) {
        return DateTime.now().difference(startTime);
      });
    },
    loading: () => const Stream<Duration>.empty(),
    error: (_, __) => const Stream<Duration>.empty(),
  );
});

/// Fetches the active peer's profile using the existing peerProfileProvider.
///
/// Watches both activePeerIdProvider (stream-based, emits on every peer ID
/// change) and isPeerIdResolvedProvider (rebuilds when resolution status
/// changes) to ensure the profile is fetched as soon as the peer ID is
/// resolved to a real user ID.
///
/// Only fetches the profile once isPeerIdResolved is true -- before that,
/// the peer ID is a raw BLE device UUID which would cause a 404.
final activePeerProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final peerIdAsync = ref.watch(activePeerIdProvider);

  // Extract the peer ID from the stream, returning null if loading/error/null.
  final peerId = peerIdAsync.valueOrNull;
  if (peerId == null || peerId.isEmpty) return null;

  // Watch the resolved flag reactively. This rebuilds this provider when
  // isPeerIdResolved transitions from false to true.
  final isResolved = ref.watch(isPeerIdResolvedProvider);
  if (!isResolved) {
    debugPrint(
      '[activePeerProfileProvider] Peer ID "$peerId" not yet resolved, '
      'waiting for GATT exchange',
    );
    return null;
  }

  debugPrint('[activePeerProfileProvider] Fetching profile for resolved peer: $peerId');

  try {
    final profile = await ref.watch(peerProfileProvider(peerId).future);
    debugPrint(
      '[activePeerProfileProvider] Profile fetched: '
      '${profile.displayName ?? profile.initials ?? "(no name)"}',
    );
    return profile;
  } catch (e) {
    debugPrint('[activePeerProfileProvider] Profile fetch failed: $e');
    rethrow;
  }
});

/// Side-effect listener that toggles overlay/banner visibility based on
/// recording state changes.
///
/// - On recording start: shows the full-screen overlay.
/// - On recording stop: dismisses both overlay and banner.
final liveRecordingStateListenerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<RecordingState>>(recordingStateProvider, (prev, next) {
    next.whenData((state) {
      if (state == RecordingState.recording) {
        final overlay = ref.read(liveRecordingOverlayProvider);
        final banner = ref.read(liveRecordingBannerProvider);
        // Only show overlay if neither overlay nor banner is already visible
        // (prevents re-showing overlay when user has minimized to banner)
        if (!overlay && !banner) {
          ref.read(liveRecordingOverlayProvider.notifier).state = true;
          ref.read(liveRecordingBannerProvider.notifier).state = false;
        }
      } else {
        // Recording stopped -- dismiss both
        ref.read(liveRecordingOverlayProvider.notifier).state = false;
        ref.read(liveRecordingBannerProvider.notifier).state = false;
      }
    });
  });
});
