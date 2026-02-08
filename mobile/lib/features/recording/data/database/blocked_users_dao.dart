import 'package:drift/drift.dart';

import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/recording/data/database/blocked_users_table.dart';

part 'blocked_users_dao.g.dart';

/// Data access object for the blocked users local cache.
///
/// Provides CRUD operations for the [BlockedUserEntries] table.
/// The block list is synced from the backend and used by [BleManager]
/// to filter proximity events from blocked users.
@DriftAccessor(tables: [BlockedUserEntries])
class BlockedUsersDao extends DatabaseAccessor<AppDatabase>
    with _$BlockedUsersDaoMixin {
  BlockedUsersDao(super.db);

  /// Get all blocked user entries.
  Future<List<BlockedUserEntry>> getAllBlocked() {
    return select(blockedUserEntries).get();
  }

  /// Get all blocked user IDs as a flat list.
  Future<List<String>> getAllBlockedUserIds() async {
    final entries = await select(blockedUserEntries).get();
    return entries.map((e) => e.blockedUserId).toList();
  }

  /// Add a user to the blocked list.
  Future<void> addBlocked(String userId) {
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_$userId';
    return into(blockedUserEntries).insert(
      BlockedUserEntriesCompanion.insert(
        id: id,
        blockedUserId: userId,
        blockedAt: now,
      ),
    );
  }

  /// Remove a user from the blocked list.
  Future<void> removeBlocked(String userId) {
    return (delete(blockedUserEntries)
          ..where((t) => t.blockedUserId.equals(userId)))
        .go();
  }

  /// Replace the entire blocked list with a new set of user IDs.
  ///
  /// Used when syncing the full block list from the backend.
  Future<void> replaceAll(List<String> userIds) async {
    await transaction(() async {
      await delete(blockedUserEntries).go();
      final now = DateTime.now();
      for (final userId in userIds) {
        final id = '${now.millisecondsSinceEpoch}_$userId';
        await into(blockedUserEntries).insert(
          BlockedUserEntriesCompanion.insert(
            id: id,
            blockedUserId: userId,
            blockedAt: now,
          ),
        );
      }
    });
  }
}
