import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android-specific background BLE handler with foreground service management.
///
/// Android kills background BLE scanning without a foreground service. Doze
/// mode and app standby terminate scanning within minutes. This class manages
/// a foreground service with type "connectedDevice" and a persistent
/// notification to keep BLE scanning alive in the background.
///
/// Key behaviors:
/// - Foreground service uses connectedDevice type (required for Android 14+)
/// - Background scanning uses SCAN_MODE_LOW_POWER (~10% duty cycle)
/// - Foreground scanning uses SCAN_MODE_BALANCED for responsiveness
/// - Auto-restarts foreground service after device reboot
/// - Requests battery optimization exemption to survive Doze mode
class AndroidBackgroundBle with WidgetsBindingObserver {
  /// Notification channel ID for the foreground service.
  static const String _notificationChannelId = 'linkless_ble';

  /// Notification channel name shown in Android settings.
  static const String _notificationChannelName = 'LinkLess BLE';

  /// Notification channel description shown in Android settings.
  static const String _notificationChannelDescription =
      'Detecting nearby LinkLess users';

  /// Notification title shown in the persistent notification.
  static const String _notificationTitle = 'LinkLess Active';

  /// Notification body text shown in the persistent notification.
  static const String _notificationBody = 'Detecting nearby users...';

  bool _isInitialized = false;
  bool _isForegroundServiceRunning = false;

  final StreamController<bool> _backgroundStateController =
      StreamController<bool>.broadcast();

  bool _isInBackground = false;

  /// Whether the foreground service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Whether the foreground service is currently running.
  bool get isForegroundServiceRunning => _isForegroundServiceRunning;

  /// Whether the app is currently in the background.
  bool get isInBackground => _isInBackground;

  /// Stream that emits true when the app enters the background,
  /// and false when the app returns to the foreground.
  Stream<bool> get backgroundStateStream => _backgroundStateController.stream;

  // ---------------------------------------------------------------------------
  // Foreground Service Initialization
  // ---------------------------------------------------------------------------

  /// Initialize the foreground service configuration.
  ///
  /// Configures the notification channel, notification appearance, and
  /// foreground task options. Must be called before [startForegroundService].
  ///
  /// No-op on non-Android platforms.
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _notificationChannelId,
        channelName: _notificationChannelName,
        channelDescription: _notificationChannelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    // Register as app lifecycle observer for background/foreground transitions.
    WidgetsBinding.instance.addObserver(this);

    _isInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Foreground Service Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the foreground service with a persistent notification.
  ///
  /// The service uses foreground service type "connectedDevice" which is
  /// required for BLE operations on Android 14+. The notification is
  /// non-dismissible to keep the service alive.
  ///
  /// Idempotent: returns immediately if the service is already running.
  /// No-op on non-Android platforms.
  Future<bool> startForegroundService() async {
    if (!Platform.isAndroid) return false;
    if (!_isInitialized) return false;

    // Check if already running to make this idempotent.
    final bool alreadyRunning = await FlutterForegroundTask.isRunningService;
    if (alreadyRunning) {
      _isForegroundServiceRunning = true;
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.connectedDevice],
      notificationTitle: _notificationTitle,
      notificationText: _notificationBody,
    );

    _isForegroundServiceRunning = result is ServiceRequestSuccess;
    return _isForegroundServiceRunning;
  }

  /// Stop the foreground service.
  ///
  /// Idempotent: returns immediately if the service is not running.
  /// No-op on non-Android platforms.
  Future<bool> stopForegroundService() async {
    if (!Platform.isAndroid) return false;

    final bool isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) {
      _isForegroundServiceRunning = false;
      return true;
    }

    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestSuccess) {
      _isForegroundServiceRunning = false;
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Background Scan Configuration
  // ---------------------------------------------------------------------------

  /// Returns the BLE scan mode appropriate for background scanning.
  ///
  /// Uses LOW_POWER mode (~10% duty cycle: scans for ~0.5s every ~5s) to
  /// conserve battery while still detecting nearby devices within a
  /// reasonable time window.
  AndroidScanMode getBackgroundScanMode() {
    return AndroidScanMode.lowPower;
  }

  /// Returns the BLE scan mode appropriate for foreground scanning.
  ///
  /// Uses BALANCED mode (~33% duty cycle) for a good balance between
  /// detection latency and battery consumption when the user has the app
  /// open.
  AndroidScanMode getForegroundScanMode() {
    return AndroidScanMode.balanced;
  }

  /// Returns the recommended scan mode based on current app state.
  ///
  /// Automatically selects LOW_POWER when backgrounded and BALANCED when
  /// in the foreground. This method is intended to be called by BleManager
  /// when starting or restarting scans.
  AndroidScanMode getRecommendedScanMode() {
    return _isInBackground ? getBackgroundScanMode() : getForegroundScanMode();
  }

  // ---------------------------------------------------------------------------
  // Battery Optimization Exemption
  // ---------------------------------------------------------------------------

  /// Request exemption from Android battery optimization (Doze mode).
  ///
  /// When granted, the system will not restrict the app's background
  /// execution, allowing the foreground service to maintain BLE scanning
  /// without interruption.
  ///
  /// Returns true if the app is already exempt or if the request was shown
  /// to the user. Note: the user may still deny the request.
  ///
  /// No-op on non-Android platforms (returns true).
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;

    final bool isAlreadyExempt =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (isAlreadyExempt) {
      return true;
    }

    return FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  /// Check if the app is currently exempt from battery optimization.
  ///
  /// No-op on non-Android platforms (returns true).
  Future<bool> isBatteryOptimizationExempt() async {
    if (!Platform.isAndroid) return true;

    return FlutterForegroundTask.isIgnoringBatteryOptimizations;
  }

  // ---------------------------------------------------------------------------
  // App Lifecycle Integration
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _setBackgroundState(true);
        break;
      case AppLifecycleState.resumed:
        _setBackgroundState(false);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // No state change for inactive (transitional) or detached (pre-exit).
        break;
    }
  }

  void _setBackgroundState(bool inBackground) {
    if (_isInBackground == inBackground) return;
    _isInBackground = inBackground;
    _backgroundStateController.add(inBackground);
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Dispose of resources and stop the foreground service.
  ///
  /// Removes the app lifecycle observer and closes the background state
  /// stream. Should be called when BLE proximity detection is permanently
  /// stopped.
  Future<void> dispose() async {
    if (Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
      await stopForegroundService();
    }

    _isInitialized = false;
    _isForegroundServiceRunning = false;
    _isInBackground = false;
    await _backgroundStateController.close();
  }
}
