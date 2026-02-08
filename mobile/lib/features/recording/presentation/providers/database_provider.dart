import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/recording/data/database/blocked_users_dao.dart';
import 'package:linkless/features/recording/data/database/conversation_dao.dart';

/// Provides the singleton Drift database instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Provides the ConversationDao from the database for data access.
final conversationDaoProvider = Provider<ConversationDao>((ref) {
  return ref.watch(appDatabaseProvider).conversationDao;
});

/// Provides the BlockedUsersDao from the database for block list access.
final blockedUsersDaoProvider = Provider<BlockedUsersDao>((ref) {
  return ref.watch(appDatabaseProvider).blockedUsersDao;
});
