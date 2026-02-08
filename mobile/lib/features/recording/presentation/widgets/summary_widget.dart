import 'dart:convert';

import 'package:flutter/material.dart';

/// Displays a conversation summary with key topic chips.
///
/// Parses the summary response from the API and renders the summary text
/// followed by key topic chips parsed from the key_topics JSON string.
class SummaryWidget extends StatelessWidget {
  const SummaryWidget({
    super.key,
    required this.summaryData,
  });

  /// The summary response map from the API.
  /// Expected keys: content (String), key_topics (JSON string), provider (String).
  final Map<String, dynamic> summaryData;

  @override
  Widget build(BuildContext context) {
    final content = summaryData['content'] as String?;
    final provider = summaryData['provider'] as String? ?? 'unknown';

    if (content == null || content.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Summary',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              const Text(
                'No summary available',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final keyTopics = _parseKeyTopics();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Text(content),
            if (keyTopics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Key Topics',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: keyTopics
                    .map((topic) => Chip(label: Text(topic)))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Summarized by $provider',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parses the key_topics field from a JSON string to a list of strings.
  ///
  /// Handles both JSON string encoding (e.g., '["topic1", "topic2"]')
  /// and direct List values.
  List<String> _parseKeyTopics() {
    final keyTopicsRaw = summaryData['key_topics'];
    if (keyTopicsRaw == null) return [];

    if (keyTopicsRaw is List) {
      return keyTopicsRaw.map((e) => e.toString()).toList();
    }

    if (keyTopicsRaw is String && keyTopicsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(keyTopicsRaw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        // Not valid JSON, ignore
      }
    }

    return [];
  }
}
