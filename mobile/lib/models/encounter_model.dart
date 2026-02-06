import 'user_model.dart';

class EncounterModel {
  final String id;
  final String userId;
  final String peerId;
  final UserModel? peerUser;
  final DateTime startedAt;
  final DateTime? endedAt;
  final EncounterStatus status;
  final List<TranscriptSegment> transcript;
  final String? summary;
  final List<String> topics;
  final double? proximityDistance;

  const EncounterModel({
    required this.id,
    required this.userId,
    required this.peerId,
    this.peerUser,
    required this.startedAt,
    this.endedAt,
    this.status = EncounterStatus.active,
    this.transcript = const [],
    this.summary,
    this.topics = const [],
    this.proximityDistance,
  });

  factory EncounterModel.fromJson(Map<String, dynamic> json) {
    return EncounterModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      peerId: json['peer_id'] as String,
      peerUser: json['peer_user'] != null
          ? UserModel.fromJson(json['peer_user'] as Map<String, dynamic>)
          : null,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      status: EncounterStatus.fromString(json['status'] as String? ?? 'active'),
      transcript: (json['transcript'] as List<dynamic>?)
              ?.map((e) =>
                  TranscriptSegment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      summary: json['summary'] as String?,
      topics: (json['topics'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      proximityDistance: (json['proximity_distance'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'peer_id': peerId,
      'peer_user': peerUser?.toJson(),
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'status': status.value,
      'transcript': transcript.map((e) => e.toJson()).toList(),
      'summary': summary,
      'topics': topics,
      'proximity_distance': proximityDistance,
    };
  }

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  String get formattedDuration {
    final d = duration;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
}

enum EncounterStatus {
  active('active'),
  completed('completed'),
  cancelled('cancelled');

  final String value;
  const EncounterStatus(this.value);

  static EncounterStatus fromString(String value) {
    return EncounterStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => EncounterStatus.active,
    );
  }
}

class TranscriptSegment {
  final String id;
  final String speakerId;
  final String speakerName;
  final String text;
  final DateTime timestamp;
  final double confidence;

  const TranscriptSegment({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.timestamp,
    this.confidence = 1.0,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      id: json['id'] as String,
      speakerId: json['speaker_id'] as String,
      speakerName: json['speaker_name'] as String,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'speaker_id': speakerId,
      'speaker_name': speakerName,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
    };
  }
}
