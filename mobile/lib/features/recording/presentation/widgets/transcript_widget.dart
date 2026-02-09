import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';

/// Displays a conversation transcript with speaker-labeled utterances.
///
/// Parses the transcript content field (a JSON string of utterances) and
/// renders each utterance as a card with speaker label, colored indicator,
/// text, and timestamp range.
class TranscriptWidget extends StatelessWidget {
  const TranscriptWidget({
    super.key,
    required this.transcriptData,
  });

  /// The transcript response map from the API.
  /// Expected keys: content (JSON string), provider (String).
  final Map<String, dynamic> transcriptData;

  /// Colors assigned to speakers for visual differentiation.
  static const _speakerColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
  ];

  @override
  Widget build(BuildContext context) {
    final utterances = _parseUtterances();
    final provider = transcriptData['provider'] as String? ?? 'unknown';

    if (utterances.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transcript',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              Text(
                'No transcript available',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transcript',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            ...utterances.map((u) => _buildUtterance(context, u)),
            const SizedBox(height: 8),
            Text(
              'Transcribed by $provider',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parses the content JSON string into a list of utterance maps.
  ///
  /// Each utterance has: speaker (int), text (String), start (double),
  /// end (double).
  List<Map<String, dynamic>> _parseUtterances() {
    final content = transcriptData['content'];
    if (content == null || content is! String || content.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Widget _buildUtterance(BuildContext context, Map<String, dynamic> utterance) {
    final speaker = (utterance['speaker'] as num?)?.toInt() ?? 0;
    final text = utterance['text'] as String? ?? '';
    final start = (utterance['start'] as num?)?.toDouble() ?? 0.0;
    final end = (utterance['end'] as num?)?.toDouble() ?? 0.0;

    final color = _speakerColors[speaker % _speakerColors.length];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colored speaker indicator
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Speaker ${speaker + 1}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                ),
                const SizedBox(height: 2),
                Text(text),
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(start)} - ${_formatTime(end)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Formats seconds into "MM:SS" display.
  String _formatTime(double seconds) {
    final totalSeconds = seconds.round();
    final minutes = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
