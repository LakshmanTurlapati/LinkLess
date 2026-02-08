/// Domain model for a search result from the full-text search endpoint.
///
/// Maps from the backend SearchResultResponse schema. Contains peer profile
/// info (with anonymous masking applied server-side), a text snippet from
/// the matching transcript, and a relevance rank score.
class SearchResult {
  final String id;
  final DateTime startedAt;
  final int? durationSeconds;
  final String? peerDisplayName;
  final String? peerPhotoUrl;
  final bool peerIsAnonymous;
  final String? snippet;
  final double rank;

  const SearchResult({
    required this.id,
    required this.startedAt,
    this.durationSeconds,
    this.peerDisplayName,
    this.peerPhotoUrl,
    this.peerIsAnonymous = false,
    this.snippet,
    this.rank = 0.0,
  });

  /// Parses a [SearchResult] from the backend JSON response.
  ///
  /// Handles the backend UUID id as a string and parses started_at
  /// from an ISO 8601 string. Nullable fields gracefully default.
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'].toString(),
      startedAt: DateTime.parse(json['started_at'] as String),
      durationSeconds: json['duration_seconds'] as int?,
      peerDisplayName: json['peer_display_name'] as String?,
      peerPhotoUrl: json['peer_photo_url'] as String?,
      peerIsAnonymous: json['peer_is_anonymous'] as bool? ?? false,
      snippet: json['snippet'] as String?,
      rank: (json['rank'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Human-readable duration formatted as "Xm Ys", or "--" if unknown.
  ///
  /// Matches the [MapConversation.displayDuration] pattern.
  String get displayDuration {
    if (durationSeconds == null) return '--';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes}m ${seconds}s';
  }
}
