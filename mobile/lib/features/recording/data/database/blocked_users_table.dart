import 'package:drift/drift.dart';

/// Drift table for locally cached blocked user IDs.
///
/// Each row represents a user that the current user has blocked.
/// The block list is synced from the backend on login and updated
/// when the user blocks or unblocks someone.
class BlockedUserEntries extends Table {
  /// Local row ID (UUID string).
  TextColumn get id => text()();

  /// The blocked user's UUID.
  TextColumn get blockedUserId => text()();

  /// When this user was blocked.
  DateTimeColumn get blockedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
