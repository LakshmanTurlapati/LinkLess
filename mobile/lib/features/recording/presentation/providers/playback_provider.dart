import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Provides an auto-disposing [AudioPlayer] instance for playback.
///
/// Each consumer gets a fresh player that is automatically disposed when the
/// widget tree no longer references it (e.g., when navigating away from the
/// playback screen).
final playbackPlayerProvider = Provider.autoDispose<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});
