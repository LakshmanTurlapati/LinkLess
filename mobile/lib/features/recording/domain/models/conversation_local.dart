import 'package:linkless/features/recording/data/database/app_database.dart';

/// Domain model for a locally stored conversation.
///
/// Maps from the Drift-generated [ConversationEntry] to provide a clean
/// domain interface with convenience getters for duration formatting,
/// audio availability, and completion status.
class ConversationLocal {
  final String id;
  final String peerId;
  final String? audioFilePath;
  final double? latitude;
  final double? longitude;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String syncStatus;

  const ConversationLocal({
    required this.id,
    required this.peerId,
    this.audioFilePath,
    this.latitude,
    this.longitude,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
    required this.syncStatus,
  });

  /// Create a [ConversationLocal] from a Drift-generated [ConversationEntry].
  factory ConversationLocal.fromEntry(ConversationEntry entry) {
    return ConversationLocal(
      id: entry.id,
      peerId: entry.peerId,
      audioFilePath: entry.audioFilePath,
      latitude: entry.latitude,
      longitude: entry.longitude,
      startedAt: entry.startedAt,
      endedAt: entry.endedAt,
      durationSeconds: entry.durationSeconds,
      syncStatus: entry.syncStatus,
    );
  }

  /// The conversation duration as a [Duration], or null if not yet complete.
  Duration? get duration =>
      durationSeconds != null ? Duration(seconds: durationSeconds!) : null;

  /// Whether this conversation has an associated audio file.
  bool get hasAudio => audioFilePath != null;

  /// Whether this conversation has been completed (recording stopped).
  bool get isComplete => endedAt != null;

  /// Human-readable duration string formatted as "Xm Ys", or "--" if unknown.
  String get displayDuration {
    if (durationSeconds == null) return '--';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes}m ${seconds}s';
  }
}
