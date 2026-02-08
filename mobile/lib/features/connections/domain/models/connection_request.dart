/// A connection request between two users for a specific conversation.
///
/// Represents one user's intent to connect with another after a conversation.
/// Each conversation can produce two ConnectionRequest rows (one per participant).
/// When both have status 'accepted', social links are exchanged.
class ConnectionRequest {
  final String id;
  final String requesterId;
  final String recipientId;
  final String conversationId;
  final String status;
  final DateTime createdAt;

  const ConnectionRequest({
    required this.id,
    required this.requesterId,
    required this.recipientId,
    required this.conversationId,
    required this.status,
    required this.createdAt,
  });

  /// Creates a [ConnectionRequest] from a JSON map returned by the API.
  factory ConnectionRequest.fromJson(Map<String, dynamic> json) {
    return ConnectionRequest(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      recipientId: json['recipient_id'] as String,
      conversationId: json['conversation_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Whether this request is still pending.
  bool get isPending => status == 'pending';

  /// Whether this request has been accepted.
  bool get isAccepted => status == 'accepted';

  /// Whether this request has been declined.
  bool get isDeclined => status == 'declined';
}
