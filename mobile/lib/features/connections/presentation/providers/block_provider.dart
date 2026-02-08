import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/features/connections/presentation/providers/connection_provider.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// Blocked users data provider
// ---------------------------------------------------------------------------

/// Provides the list of blocked user IDs from the local Drift cache.
///
/// Returns a list of user ID strings. This provider is invalidated
/// whenever a block or unblock action completes.
final blockedUsersProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.blockedUsersDao.getAllBlockedUserIds();
});

// ---------------------------------------------------------------------------
// Sync provider
// ---------------------------------------------------------------------------

/// Fetches the blocked user list from the backend and syncs it to
/// the local Drift cache and BLE manager.
///
/// This should be called during app initialization after authentication
/// succeeds, so the BLE manager has the blocked list before any
/// proximity events are processed.
final syncBlockListProvider = FutureProvider<void>((ref) async {
  final apiService = ref.watch(connectionApiServiceProvider);
  final db = ref.watch(appDatabaseProvider);

  try {
    final blockedIds = await apiService.listBlocked();
    await db.blockedUsersDao.replaceAll(blockedIds);
    BleManager.instance.updateBlockedUsers(blockedIds.toSet());
  } catch (e) {
    // Sync failure is non-fatal; the local cache will be used as fallback.
    debugPrint('[BlockProvider] Failed to sync block list: $e');
    // Load from local cache as fallback
    final localIds = await db.blockedUsersDao.getAllBlockedUserIds();
    BleManager.instance.updateBlockedUsers(localIds.toSet());
  }
});

// ---------------------------------------------------------------------------
// Action functions
// ---------------------------------------------------------------------------

/// Block a user: calls backend API, updates local Drift cache,
/// and updates the BLE manager filter.
Future<void> blockUser(WidgetRef ref, String userId) async {
  final apiService = ref.read(connectionApiServiceProvider);
  final db = ref.read(appDatabaseProvider);

  await apiService.blockUser(userId);
  await db.blockedUsersDao.addBlocked(userId);

  // Update BLE manager with the new blocked set
  final allBlocked = await db.blockedUsersDao.getAllBlockedUserIds();
  BleManager.instance.updateBlockedUsers(allBlocked.toSet());

  ref.invalidate(blockedUsersProvider);
}

/// Unblock a user: calls backend API, removes from local Drift cache,
/// and updates the BLE manager filter.
Future<void> unblockUser(WidgetRef ref, String userId) async {
  final apiService = ref.read(connectionApiServiceProvider);
  final db = ref.read(appDatabaseProvider);

  await apiService.unblockUser(userId);
  await db.blockedUsersDao.removeBlocked(userId);

  // Update BLE manager with the updated blocked set
  final allBlocked = await db.blockedUsersDao.getAllBlockedUserIds();
  BleManager.instance.updateBlockedUsers(allBlocked.toSet());

  ref.invalidate(blockedUsersProvider);
}
