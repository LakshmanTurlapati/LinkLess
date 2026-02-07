import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/recording/data/database/conversation_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [ConversationEntries], daos: [ConversationDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'linkless_local');
  }
}
