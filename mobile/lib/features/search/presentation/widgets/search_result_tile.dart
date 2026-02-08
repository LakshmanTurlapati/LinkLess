import 'package:flutter/material.dart';

import 'package:linkless/features/search/domain/models/search_result.dart';

/// A list tile displaying a single search result.
///
/// Shows peer avatar (photo or initials), peer display name, a snippet
/// of matching transcript text, date, and duration. The snippet has
/// HTML bold tags stripped for clean display.
class SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAvatar(),
      title: Text(
        _displayName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cleanSnippet.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                _cleanSnippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          Text(
            '${_formatDate(result.startedAt)} -- ${result.displayDuration}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
      isThreeLine: _cleanSnippet.isNotEmpty,
      onTap: onTap,
    );
  }

  /// Builds the avatar widget: NetworkImage if photo URL exists, or initials.
  Widget _buildAvatar() {
    if (result.peerPhotoUrl != null && result.peerPhotoUrl!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(result.peerPhotoUrl!),
      );
    }
    return CircleAvatar(
      child: Text(_initials),
    );
  }

  /// Display name: peer name, "Anonymous" if anonymous, or "Unknown".
  String get _displayName {
    if (result.peerIsAnonymous) return 'Anonymous';
    if (result.peerDisplayName != null &&
        result.peerDisplayName!.isNotEmpty) {
      return result.peerDisplayName!;
    }
    return 'Unknown';
  }

  /// Initials derived from display name for avatar fallback.
  String get _initials {
    final name = _displayName;
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  /// Snippet with HTML bold tags stripped for clean display.
  String get _cleanSnippet {
    if (result.snippet == null) return '';
    return result.snippet!.replaceAll(RegExp(r'</?b>'), '');
  }

  /// Simple date formatting without intl dependency.
  ///
  /// Returns format: "MMM d, yyyy" -- e.g. "Feb 7, 2026".
  /// Matches the existing manual date formatting pattern in ConversationTile.
  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }
}
