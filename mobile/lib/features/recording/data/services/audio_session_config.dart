import 'package:audio_session/audio_session.dart';

/// Configures the shared audio session for recording and playback.
///
/// Sets AVAudioSession category to playAndRecord with options for
/// speaker output, Bluetooth routing, and mixing with other audio.
/// This configuration supports the "foreground-initiated,
/// background-continued" recording pattern required for App Store
/// compliance.
///
/// Must be called once before starting any recording session.
Future<void> configureAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.mixWithOthers,
    avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  ));
  await session.setActive(true);
}
