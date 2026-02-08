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

  /// Update the sync status of a conversation by its ID.
  Future<void> updateSyncStatus(String id, String status) {
    return (update(conversationEntries)..where((t) => t.id.equals(id))).write(
      ConversationEntriesCompanion(
        syncStatus: Value(status),
      ),
    );
  }
}
