import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:linkless/features/recording/data/database/blocked_users_dao.dart';
import 'package:linkless/features/recording/data/database/blocked_users_table.dart';
import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/recording/data/database/conversation_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [ConversationEntries, BlockedUserEntries],
  daos: [ConversationDao, BlockedUsersDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(blockedUserEntries);
          }
          if (from < 3) {
            await m.addColumn(
                conversationEntries, conversationEntries.serverId);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'linkless_local');
  }
}
