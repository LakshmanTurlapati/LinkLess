/// Domain model for a conversation formatted for map display.
///
/// Maps from the backend MapConversationResponse schema. Contains GPS
/// coordinates, peer profile info (with anonymous masking applied
/// server-side), and basic conversation metadata for rendering map pins.
class MapConversation {
  final String id;
  final double latitude;
  final double longitude;
  final DateTime startedAt;
  final int? durationSeconds;
  final String? peerDisplayName;
  final String? peerInitials;
  final String? peerPhotoUrl;
  final bool peerIsAnonymous;

  const MapConversation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    this.durationSeconds,
    this.peerDisplayName,
    this.peerInitials,
    this.peerPhotoUrl,
    this.peerIsAnonymous = false,
  });

  /// Parses a [MapConversation] from the backend JSON response.
  ///
  /// Handles the backend UUID id as a string and parses started_at
  /// from an ISO 8601 string. Nullable fields gracefully default.
  factory MapConversation.fromJson(Map<String, dynamic> json) {
    return MapConversation(
      id: json['id'].toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      startedAt: DateTime.parse(json['started_at'] as String),
      durationSeconds: json['duration_seconds'] as int?,
      peerDisplayName: json['peer_display_name'] as String?,
      peerInitials: json['peer_initials'] as String?,
      peerPhotoUrl: json['peer_photo_url'] as String?,
      peerIsAnonymous: json['peer_is_anonymous'] as bool? ?? false,
    );
  }

  /// Human-readable duration formatted as "Xm Ys", or "--" if unknown.
  ///
  /// Matches the [ConversationLocal.displayDuration] pattern.
  String get displayDuration {
    if (durationSeconds == null) return '--';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes}m ${seconds}s';
  }
}
