import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:linkless/ble/ble_constants.dart';

/// iOS-specific background BLE configuration and state restoration handling.
///
/// iOS imposes strict constraints on BLE operations when the app is backgrounded
/// or terminated by the system. This class manages those constraints:
///
/// **Background Scanning Limitations:**
/// - iOS increases scan intervals from ~1-2s (foreground) to ~30-60s (background).
/// - Duplicate device reports are suppressed (CBCentralManagerScanOptionAllowDuplicatesKey
///   is ignored in background mode).
/// - Scanning MUST use a specific service UUID filter. Scanning with nil/wildcard
///   service UUIDs returns zero results when the app is in the background.
///
/// **Background Advertising Limitations (Overflow Area):**
/// - When backgrounded, iOS moves the advertising service UUID into the
///   "overflow area" of the BLE advertisement packet.
/// - Other iOS devices scanning for that exact service UUID CAN still discover
///   this device, because iOS checks the overflow area during filtered scans.
/// - Android devices CANNOT see overflow area data. They will not discover an
///   iOS device that is advertising in the background. The workaround is
///   GATT connection-based exchange (implemented in BleCentralService), where
///   a foreground Android scanner connects to the iOS peripheral to read its
///   user ID directly.
/// - If the user force-quits the app, Core Bluetooth state preservation is
///   disabled entirely. There is no workaround -- the app must be relaunched
///   manually.
///
/// **State Preservation/Restoration:**
/// - Calling FlutterBluePlus.setOptions(restoreState: true) enables Core Bluetooth
///   state preservation. When iOS terminates the app (e.g., for memory pressure),
///   the system will relaunch it in the background when a relevant BLE event occurs
///   (e.g., a peripheral advertising the scanned service UUID is discovered).
/// - Upon relaunch, the system restores the CBCentralManager and CBPeripheralManager
///   state, including pending connections and active scans.
/// - flutter_blue_plus handles most of the low-level restoration internally when
///   restoreState: true is set. This class provides application-level hooks for
///   re-initializing state that was lost during termination.
class IosBackgroundBle with WidgetsBindingObserver {
  final StreamController<bool> _backgroundController =
      StreamController<bool>.broadcast();

  bool _isInitialized = false;
  bool _isInBackground = false;

  /// Stream that emits true when the app enters background, false when it
  /// returns to foreground. Other services can listen to this to adjust
  /// their behavior (e.g., logging, scan interval expectations).
  Stream<bool> get isInBackground => _backgroundController.stream;

  /// Whether the app is currently in the background.
  bool get isCurrentlyInBackground => _isInBackground;

  /// Whether this handler has been initialized.
  bool get isInitialized => _isInitialized;

  /// Initialize iOS-specific BLE configuration.
  ///
  /// MUST be called before any other FlutterBluePlus operations to ensure
  /// Core Bluetooth state preservation is enabled. On non-iOS platforms,
  /// this is a no-op.
  ///
  /// This method:
  /// 1. Enables state restoration via FlutterBluePlus.setOptions(restoreState: true)
  /// 2. Registers for app lifecycle events to track foreground/background transitions
  Future<void> initialize() async {
    if (!Platform.isIOS) {
      _isInitialized = true;
      return;
    }

    if (_isInitialized) return;

    // Enable Core Bluetooth state preservation/restoration.
    // This allows iOS to relaunch the app after system termination
    // when BLE events matching our scan filter occur.
    await FlutterBluePlus.setOptions(restoreState: true);

    // Register for app lifecycle callbacks
    WidgetsBinding.instance.addObserver(this);

    _isInitialized = true;
  }

  /// Provide background-aware scan configuration for BLE scanning.
  ///
  /// Returns the service UUID list that MUST be used when starting a scan.
  /// On iOS, scanning without a specific service UUID filter returns zero
  /// results when the app is in the background. This method ensures the
  /// correct filter is always applied.
  ///
  /// On non-iOS platforms, this still returns the service UUID filter as a
  /// best practice (reduces noise from non-Linkless devices).
  ///
  /// Note on background scan behavior:
  /// - CBCentralManagerScanOptionAllowDuplicatesKey is automatically ignored
  ///   by iOS when the app is in the background. This means each unique
  ///   peripheral is reported only once per scan session, rather than on
  ///   every advertisement packet.
  /// - Scan intervals increase from ~1-2s to ~30-60s in background.
  /// - These are OS-level constraints and cannot be overridden.
  List<Guid> configureBackgroundScan() {
    // Return the Linkless service UUID as the required scan filter.
    // This is mandatory for iOS background scanning and recommended
    // for all platforms to reduce scan noise.
    return [BleConstants.serviceUuid];
  }

  /// Handle app lifecycle state changes.
  ///
  /// Tracks when the app moves between foreground and background states.
  /// iOS automatically adjusts BLE behavior when backgrounded:
  /// - Scan intervals increase to ~30-60 seconds
  /// - Advertising frequency is reduced by the OS
  /// - Duplicate scan reports are suppressed
  /// - Service UUIDs move to the overflow area in advertisements
  ///
  /// These changes are automatic and cannot be prevented. This method
  /// tracks the transitions for logging and to notify other services
  /// via the [isInBackground] stream.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        if (!_isInBackground) {
          _isInBackground = true;
          _backgroundController.add(true);
          debugPrint(
            '[IosBackgroundBle] App entered background. '
            'iOS will reduce scan interval to ~30-60s and move '
            'advertised service UUIDs to the overflow area.',
          );
        }
      case AppLifecycleState.resumed:
        if (_isInBackground) {
          _isInBackground = false;
          _backgroundController.add(false);
          debugPrint(
            '[IosBackgroundBle] App returned to foreground. '
            'BLE scanning and advertising resume at normal intervals.',
          );
        }
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // detached: app is being destroyed. State preservation handles
        // continuation if needed.
        // hidden: intermediate state, no action needed.
        break;
    }
  }

  /// Handle state restoration after iOS relaunches the app.
  ///
  /// When iOS terminates the app (e.g., due to memory pressure) and later
  /// relaunches it for a BLE event, Core Bluetooth restores the
  /// CBCentralManager and CBPeripheralManager state automatically.
  /// flutter_blue_plus handles the low-level restoration internally when
  /// restoreState: true was set during initialization.
  ///
  /// This method handles application-level restoration:
  /// - Logs the restoration event for debugging
  /// - Returns true if restoration was detected, false otherwise
  ///
  /// Call this during app startup (after initialize()) to detect and handle
  /// the restoration scenario. On non-iOS platforms, this is a no-op that
  /// returns false.
  ///
  /// Note: If the user force-quits the app, state preservation is disabled
  /// entirely by iOS. There is no workaround -- the user must relaunch
  /// the app manually. Force-quit is treated as an explicit user action
  /// to stop all background activity.
  Future<bool> handleStateRestoration() async {
    if (!Platform.isIOS) return false;

    // Check if we were relaunched by the system.
    // flutter_blue_plus internally checks for restoration keys on iOS.
    // If the app was relaunched for a BLE event, FlutterBluePlus will
    // have already restored pending connections and active scans.
    //
    // We detect this by checking if BLE operations were in progress
    // before our initialize() was called in this new process.
    final wasRestored = FlutterBluePlus.isScanningNow;

    if (wasRestored) {
      debugPrint(
        '[IosBackgroundBle] State restoration detected. '
        'iOS relaunched the app for a BLE event. '
        'Core Bluetooth state has been restored by the system.',
      );
    }

    return wasRestored;
  }

  /// Clean up resources and unregister lifecycle observer.
  ///
  /// Call this when the BLE system is being shut down.
  /// On non-iOS platforms, this only closes the stream controller.
  void dispose() {
    if (Platform.isIOS) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _backgroundController.close();
    _isInitialized = false;
    _isInBackground = false;
  }
}
