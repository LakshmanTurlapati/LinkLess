import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:linkless/ble/ble_manager.dart';

/// Key used to persist the invisible mode flag in SharedPreferences.
const _kInvisibleModeKey = 'invisible_mode';

/// Provider for the invisible mode state.
///
/// When invisible mode is enabled, BLE scanning and advertising are stopped
/// so the user is not discoverable by nearby peers. The flag is persisted
/// to SharedPreferences so it survives app restarts.
final invisibleModeProvider =
    StateNotifierProvider<InvisibleModeNotifier, bool>((ref) {
  return InvisibleModeNotifier();
});

/// Manages invisible mode state with SharedPreferences persistence
/// and BLE manager start/stop control.
class InvisibleModeNotifier extends StateNotifier<bool> {
  InvisibleModeNotifier() : super(false) {
    _loadFromPrefs();
  }

  /// Load the persisted invisible mode flag from SharedPreferences.
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_kInvisibleModeKey) ?? false;
    if (mounted) {
      state = value;
    }
  }

  /// Toggle invisible mode on or off.
  ///
  /// When [value] is true, BLE scanning and advertising are stopped.
  /// When [value] is false, BLE is restarted with the provided [userId].
  /// The flag is persisted to SharedPreferences.
  Future<void> toggle(bool value, {String? userId}) async {
    // Optimistic state update
    state = value;

    // Persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInvisibleModeKey, value);

    // Control BLE manager
    if (value) {
      await BleManager.instance.stop();
    } else if (userId != null) {
      await BleManager.instance.start(userId);
    }
  }
}
