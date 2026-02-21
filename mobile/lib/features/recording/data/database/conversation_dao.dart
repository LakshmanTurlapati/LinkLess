import 'package:drift/drift.dart';

import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/recording/data/database/conversation_table.dart';

part 'conversation_dao.g.dart';

@DriftAccessor(tables: [ConversationEntries])
class ConversationDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationDaoMixin {
  ConversationDao(super.db);

  /// Watch all conversations ordered by most recent first.
  Stream<List<ConversationEntry>> watchAllConversations() {
    return (select(conversationEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .watch();
  }

  /// Get all conversations ordered by most recent first.
  Future<List<ConversationEntry>> getAllConversations() {
    return (select(conversationEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .get();
  }

  /// Get a single conversation by its ID.
  Future<ConversationEntry?> getConversation(String id) {
    return (select(conversationEntries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Insert a new conversation entry.
  Future<void> insertConversation(ConversationEntriesCompanion entry) {
    return into(conversationEntries).insert(entry);
  }

  /// Update a conversation when recording completes.
  Future<void> completeConversation(
    String id, {
    required String audioFilePath,
    required DateTime endedAt,
    required int durationSeconds,
  }) {
    return (update(conversationEntries)..where((t) => t.id.equals(id))).write(
      ConversationEntriesCompanion(
        audioFilePath: Value(audioFilePath),
        endedAt: Value(endedAt),
        durationSeconds: Value(durationSeconds),
      ),
    );
  }

  /// Update the peer ID of a conversation (e.g., when GATT exchange resolves
  /// a device ID to a real user ID).
  Future<void> updatePeerId(String id, String peerId) {
    return (update(conversationEntries)..where((t) => t.id.equals(id))).write(
      ConversationEntriesCompanion(peerId: Value(peerId)),
    );
  }

  /// Delete a conversation by its ID.
  Future<void> deleteConversation(String id) {
    return (delete(conversationEntries)..where((t) => t.id.equals(id))).go();
  }

  /// Get conversations pending upload, oldest first.
  ///
  /// Returns conversations where syncStatus is 'pending' and an audio file
  /// path exists, ordered by startedAt ascending so the oldest are uploaded
  /// first.
  Future<List<ConversationEntry>> getPendingUploads() {
    return (select(conversationEntries)
          ..where((t) =>
              t.syncStatus.equals('pending') &
              t.audioFilePath.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
        .get();
  }

  /// Store the server-assigned conversation ID after upload.
  Future<void> updateServerId(String localId, String serverId) {
    return (update(conversationEntries)..where((t) => t.id.equals(localId)))
        .write(
      ConversationEntriesCompanion(
        serverId: Value(serverId),
      ),
    );
  }

  /// Get conversations with 'uploaded' sync status, oldest first.
  ///
  /// Returns conversations whose audio has been uploaded but whose
  /// transcription has not yet completed, ordered by startedAt ascending.
  Future<List<ConversationEntry>> getUploadedConversations() {
    return (select(conversationEntries)
          ..where((t) => t.syncStatus.equals('uploaded'))
          ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
        .get();
  }

  /// Clean up conversations left incomplete by app crash or force-close.
  ///
  /// Finds conversations where endedAt is null (recording was active when
  /// app died), sets endedAt to startedAt (zero duration), and clears
  /// syncStatus to 'failed' so they are not uploaded with corrupt audio.
  Future<int> cleanupIncompleteConversations() async {
    final incomplete = await (select(conversationEntries)
          ..where((t) => t.endedAt.isNull()))
        .get();
    for (final conv in incomplete) {
      await (update(conversationEntries)
            ..where((t) => t.id.equals(conv.id)))
          .write(ConversationEntriesCompanion(
        endedAt: Value(conv.startedAt),
        durationSeconds: const Value(0),
        syncStatus: const Value('failed'),
      ));
    }
    return incomplete.length;
  }

  /// Update the sync status of a conversation by its ID.
  Future<void> updateSyncStatus(String id, String status) {
    return (update(conversationEntries)..where((t) => t.id.equals(id))).write(
      ConversationEntriesCompanion(
        syncStatus: Value(status),
      ),
    );
  }
}
