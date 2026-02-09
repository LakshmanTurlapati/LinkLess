import 'dart:async';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'package:linkless/core/theme/app_colors.dart';

/// A self-contained audio player widget with play/pause, seek bar, and skip
/// controls.
///
/// Uses [AudioPlayer] from just_audio and [ProgressBar] from
/// audio_video_progress_bar. Manages its own stream subscriptions and
/// disposes them on widget removal.
class AudioPlayerWidget extends StatefulWidget {
  const AudioPlayerWidget({
    super.key,
    required this.player,
    required this.filePath,
  });

  /// The just_audio player instance to control.
  final AudioPlayer player;

  /// Absolute file path to the audio file to play.
  final String filePath;

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  PlayerState? _playerState;
  bool _loadError = false;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<Duration> _bufferedSub;
  late final StreamSubscription<PlayerState> _stateSub;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await widget.player.setFilePath(widget.filePath);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = true);
      }
      return;
    }

    _positionSub = widget.player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _durationSub = widget.player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });

    _bufferedSub = widget.player.bufferedPositionStream.listen((buf) {
      if (mounted) setState(() => _buffered = buf);
    });

    _stateSub = widget.player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
  }

  @override
  void dispose() {
    if (!_loadError) {
      _positionSub.cancel();
      _durationSub.cancel();
      _bufferedSub.cancel();
      _stateSub.cancel();
    }
    super.dispose();
  }

  bool get _isPlaying =>
      _playerState?.playing == true &&
      _playerState?.processingState != ProcessingState.completed;

  @override
  Widget build(BuildContext context) {
    if (_loadError) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Failed to load audio file',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressBar(
            progress: _position,
            buffered: _buffered,
            total: _duration,
            onSeek: (position) => widget.player.seek(position),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 10 seconds
              IconButton(
                icon: const Icon(Icons.replay_10),
                iconSize: 36,
                onPressed: () {
                  final newPos = _position - const Duration(seconds: 10);
                  widget.player.seek(
                    newPos < Duration.zero ? Duration.zero : newPos,
                  );
                },
              ),
              const SizedBox(width: 16),
              // Play / Pause
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                iconSize: 56,
                onPressed: () async {
                  if (_playerState?.processingState ==
                      ProcessingState.completed) {
                    await widget.player.seek(Duration.zero);
                    await widget.player.play();
                  } else if (_isPlaying) {
                    await widget.player.pause();
                  } else {
                    await widget.player.play();
                  }
                },
              ),
              const SizedBox(width: 16),
              // Forward 10 seconds
              IconButton(
                icon: const Icon(Icons.forward_10),
                iconSize: 36,
                onPressed: () {
                  final newPos = _position + const Duration(seconds: 10);
                  widget.player.seek(
                    newPos > _duration ? _duration : newPos,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
