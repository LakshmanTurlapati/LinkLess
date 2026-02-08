import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/connections/presentation/providers/block_provider.dart';
import 'package:linkless/features/profile/presentation/view_models/profile_view_model.dart';

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
/// 1. Fetch user profile for user ID
/// 2. Sync blocked users list from backend
/// 3. Check invisible mode preference
/// 4. Conditionally initialize and start BLE
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
    // Step 1: Get user ID via profile fetch.
    // The profile endpoint is authenticated (auth interceptor attaches
    // Bearer token from TokenStorageService). If the profile fetch fails
    // (e.g., new user who hasn't created a profile yet), return early --
    // BLE init will be retried when the provider re-evaluates after
    // profile creation.
    final String userId;
    try {
      final profile = await ref.read(profileApiServiceProvider).getProfile();
      userId = profile.id;
      debugPrint('[AppInit] Profile fetched, userId: $userId');
    } catch (e) {
      debugPrint('[AppInit] Profile fetch failed (new user?): $e');
      return;
    }

    // Step 2: Sync blocked users list (GAP 3 fix).
    // Must complete before BLE starts so blocked users are filtered
    // from the very first scan cycle.
    try {
      await ref.read(syncBlockListProvider.future);
      debugPrint('[AppInit] Blocked users synced');
    } catch (e) {
      // Non-fatal -- syncBlockListProvider has its own local fallback.
      debugPrint('[AppInit] Block list sync error (using fallback): $e');
    }

    // Step 3: Check invisible mode preference.
    final prefs = await SharedPreferences.getInstance();
    final isInvisible = prefs.getBool('invisible_mode') ?? false;

    if (isInvisible) {
      debugPrint('[AppInit] Invisible mode enabled -- skipping BLE start');
      return;
    }

    // Step 4: Initialize and start BLE (GAP 1 fix).
    await BleManager.instance.initialize();
    final permissions = await BleManager.instance.requestPermissions();

    if (permissions.allGranted) {
      await BleManager.instance.start(userId);
      debugPrint('[AppInit] BLE initialized and started');
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
