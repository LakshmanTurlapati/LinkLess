import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/core/services/notification_service.dart';
import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/proximity/services/proximity_notification_handler.dart';
import 'package:linkless/features/connections/presentation/providers/block_provider.dart';
import 'package:linkless/features/profile/presentation/view_models/profile_view_model.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';

// ---------------------------------------------------------------------------
// App initialization provider
// ---------------------------------------------------------------------------

/// Guards against double execution of _initializeServices.
bool _initializing = false;

/// Orchestrates post-authentication service initialization.
///
/// Watches [authProvider] and triggers initialization when the user
/// transitions to [AuthStatus.authenticated]. On logout
/// ([AuthStatus.unauthenticated]), stops BLE scanning.
///
/// Initialization sequence:
/// 1. Request core permissions (microphone + location + notification)
/// 2. Fetch user profile for user ID
/// 3. Sync blocked users list from backend
/// 4. Check invisible mode preference
/// 5. Conditionally initialize and start BLE
///
/// This provider is side-effect-only (returns void), matching the
/// pattern used by [syncEngineProvider].
final appInitProvider = Provider<void>((ref) {
  final authState = ref.watch(authProvider);

  if (authState.status == AuthStatus.authenticated) {
    Future.microtask(() => _initializeServices(ref));
  } else if (authState.status == AuthStatus.unauthenticated) {
    // Teardown: stop BLE on logout
    Future.microtask(() async {
      try {
        await BleManager.instance.stop();
        debugPrint('[AppInit] BLE stopped on logout');
      } catch (e) {
        debugPrint('[AppInit] Failed to stop BLE on logout: $e');
      }
    });
  }
});

/// Performs the post-auth initialization sequence.
///
/// Fetches the user profile for the user ID, syncs the blocked users
/// list, checks invisible mode, and conditionally starts BLE.
///
/// Guarded by [_initializing] to prevent double execution. BleManager
/// also has its own [_isInitialized] and [_isRunning] guards as
/// secondary protection.
Future<void> _initializeServices(Ref ref) async {
  if (_initializing) return;
  _initializing = true;

  try {
    // Step 1: Request core app permissions (microphone + location).
    // Requested upfront so the user is prompted immediately after login,
    // rather than waiting until proximity triggers recording.
    // Placed before any early-return guards so every authenticated user
    // (new, invisible, network-error) still sees the permission dialogs.
    final corePermissions = await [
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();

    for (final entry in corePermissions.entries) {
      debugPrint('[AppInit] ${entry.key}: ${entry.value}');
    }

    // Step 1b: Initialize notification service + request notification permission.
    await NotificationService.instance.initialize();
    await Permission.notification.request();

    // Step 1c: Clean up incomplete conversations from previous crash/force-close.
    try {
      final dao = ref.read(conversationDaoProvider);
      final cleaned = await dao.cleanupIncompleteConversations();
      if (cleaned > 0) {
        debugPrint('[AppInit] Cleaned up $cleaned incomplete conversation(s)');
      }
      // Dismiss any stale recording notification from previous session
      await NotificationService.instance.dismissRecordingNotification();
    } catch (e) {
      debugPrint('[AppInit] Conversation cleanup failed (non-fatal): $e');
    }

    // If already marked as new user, skip initialization -- router will
    // redirect to profile creation. Avoids redundant API calls.
    if (ref.read(authProvider).isNewUser) {
      debugPrint('[AppInit] New user detected, skipping init');
      return;
    }

    // Step 2: Get user ID via profile fetch.
    // The profile endpoint is authenticated (auth interceptor attaches
    // Bearer token from TokenStorageService). If the profile fetch fails
    // with 404 (new user who hasn't created a profile yet), mark as new
    // user so the router redirects to profile creation. For other errors,
    // return early without marking -- avoids blocking returning users on
    // network issues.
    final String userId;
    try {
      final profile = await ref.read(profileApiServiceProvider).getProfile();
      userId = profile.id;
      debugPrint('[AppInit] Profile fetched, userId: $userId');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint('[AppInit] Profile not found (new user), redirecting');
        ref.read(authProvider.notifier).markAsNewUser();
      } else {
        debugPrint('[AppInit] Profile fetch failed (network?): $e');
      }
      return;
    } catch (e) {
      debugPrint('[AppInit] Profile fetch failed: $e');
      return;
    }

    // Step 3: Sync blocked users list (GAP 3 fix).
    // Must complete before BLE starts so blocked users are filtered
    // from the very first scan cycle.
    try {
      await ref.read(syncBlockListProvider.future);
      debugPrint('[AppInit] Blocked users synced');
    } catch (e) {
      // Non-fatal -- syncBlockListProvider has its own local fallback.
      debugPrint('[AppInit] Block list sync error (using fallback): $e');
    }

    // Step 4: Check invisible mode preference.
    final prefs = await SharedPreferences.getInstance();
    final isInvisible = prefs.getBool('invisible_mode') ?? false;

    if (isInvisible) {
      debugPrint('[AppInit] Invisible mode enabled -- skipping BLE start');
      return;
    }

    // Step 5: Initialize and start BLE (GAP 1 fix).
    await BleManager.instance.initialize();
    final permissions = await BleManager.instance.requestPermissions();

    if (permissions.allGranted) {
      await BleManager.instance.start(userId);
      debugPrint('[AppInit] BLE initialized and started');

      final proximityHandler = ProximityNotificationHandler();
      await proximityHandler.initialize();
      debugPrint('[AppInit] Proximity notification handler initialized');
    } else {
      debugPrint(
        '[AppInit] BLE permissions denied: ${permissions.deniedPermissions}',
      );
    }
  } catch (e) {
    // Initialization failure is non-fatal -- the app still works
    // for manual workflows (viewing past conversations, profile, etc.).
    debugPrint('[AppInit] Initialization failed: $e');
  } finally {
    _initializing = false;
  }
}
