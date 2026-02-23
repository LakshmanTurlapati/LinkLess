import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/recording/domain/models/conversation_local.dart';
import 'package:linkless/features/recording/presentation/providers/conversation_detail_provider.dart';
import 'package:linkless/features/recording/presentation/widgets/audio_player_widget.dart';
import 'package:linkless/features/sync/presentation/providers/sync_provider.dart';

/// Renders a single debug recording with inline playback, pipeline status,
/// error display, and force-retranscribe button.
///
/// Shows the conversation ID, date, duration, and current pipeline status
/// (Waiting, Uploading, Transcribing, Summarizing, Done, Failed). For failed
/// recordings, the error message from the backend is displayed inline without
/// requiring a tap. A retranscribe button allows force-retranscription of
/// failed recordings.
class DebugRecordingTile extends ConsumerStatefulWidget {
  final ConversationLocal conversation;

  const DebugRecordingTile({super.key, required this.conversation});

  @override
  ConsumerState<DebugRecordingTile> createState() =>
      _DebugRecordingTileState();
}

class _DebugRecordingTileState extends ConsumerState<DebugRecordingTile> {
  AudioPlayer? _player;
  bool _isExpanded = false;
  bool _isRetranscribing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Header
          _buildHeader(c),

          // Row 2: Transcript & summary (completed recordings)
          if (c.syncStatus == 'completed' && c.serverId != null)
            _buildTranscriptSummary(c.serverId!),

          // Row 3: Error display (always visible for failed recordings)
          if (c.syncStatus == 'failed' && c.serverId != null)
            _buildErrorDisplay(c.serverId!),

          // Row 4: Retranscribe button (failed recordings with serverId)
          if (c.syncStatus == 'failed' && c.serverId != null)
            _buildRetranscribeButton(c.serverId!),

          // Row 5: Inline playback (when expanded)
          if (_isExpanded && c.hasAudio) _buildPlayback(c.audioFilePath!),
        ],
      ),
    );
  }

  Widget _buildHeader(ConversationLocal c) {
    final dateStr =
        '${c.startedAt.month}/${c.startedAt.day} '
        '${c.startedAt.hour}:${c.startedAt.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        const Icon(Icons.audio_file, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.id,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                '$dateStr  ${c.displayDuration}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildStatusBadge(c),
      ],
    );
  }

  Widget _buildStatusBadge(ConversationLocal c) {
    final status = c.syncStatus;
    final bool showPlayButton =
        (status == 'completed' || status == 'failed') && c.hasAudio;

    Widget badge;
    switch (status) {
      case 'pending':
        badge = _chip('Waiting...', AppColors.warning);
        break;
      case 'uploading':
        badge = _chipWithSpinner('Uploading...', AppColors.warning);
        break;
      case 'uploaded':
      case 'transcribing':
        badge = _chipWithSpinner('Transcribing...', AppColors.warning);
        break;
      case 'summarizing':
        badge = _chipWithSpinner('Summarizing...', AppColors.warning);
        break;
      case 'completed':
        badge = _chip('Done', AppColors.success);
        break;
      case 'failed':
        badge = _chip('Failed', AppColors.error);
        break;
      default:
        badge = _chip(status, AppColors.textSecondary);
    }

    if (!showPlayButton) return badge;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            _isExpanded ? Icons.expand_less : Icons.play_arrow,
            color: AppColors.textSecondary,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }

  Widget _chipWithSpinner(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptSummary(String serverId) {
    return Consumer(
      builder: (context, ref, _) {
        final detailAsync = ref.watch(conversationDetailProvider(serverId));

        return detailAsync.when(
          data: (data) {
            if (data == null) return const SizedBox.shrink();

            final transcript = data['transcript'];
            final summary = data['summary'];

            if (transcript == null && summary == null) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summary != null && summary['content'] != null) ...[
                    const Text(
                      'Summary',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary['content'] as String,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    if (summary['key_topics'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Topics: ${summary['key_topics']}',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                  if (transcript != null &&
                      transcript['content'] != null) ...[
                    if (summary != null) const SizedBox(height: 8),
                    const Text(
                      'Transcript',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      transcript['content'] as String,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildErrorDisplay(String serverId) {
    return Consumer(
      builder: (context, ref, _) {
        final detailAsync = ref.watch(conversationDetailProvider(serverId));

        return detailAsync.when(
          data: (data) {
            if (data == null) return const SizedBox.shrink();
            final error = data['error'];
            if (error is! Map<String, dynamic>) return const SizedBox.shrink();

            final stage = error['stage'] ?? 'unknown';
            final message = error['message'] ?? 'Unknown error';

            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$stage: $message',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildRetranscribeButton(String serverId) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _isRetranscribing
              ? null
              : () => _handleRetranscribe(serverId),
          child: _isRetranscribing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Retranscribe',
                  style: TextStyle(fontSize: 12),
                ),
        ),
      ),
    );
  }

  Future<void> _handleRetranscribe(String serverId) async {
    setState(() => _isRetranscribing = true);

    try {
      final apiService = ref.read(conversationApiServiceProvider);
      await apiService.retranscribe(serverId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retranscribe queued')),
        );
        ref.invalidate(conversationDetailProvider(serverId));
      }
    } on DioException catch (e) {
      if (mounted) {
        final statusCode = e.response?.statusCode;
        String message;
        switch (statusCode) {
          case 404:
            message = 'Retranscribe unavailable (backend not in debug mode)';
            break;
          case 409:
            message = 'Already in progress';
            break;
          case 400:
            message = 'Conversation not in failed state';
            break;
          default:
            message = e.message ?? 'Unknown error';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetranscribing = false);
      }
    }
  }

  Widget _buildPlayback(String filePath) {
    _player ??= AudioPlayer();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AudioPlayerWidget(
        player: _player!,
        filePath: filePath,
      ),
    );
  }
}
