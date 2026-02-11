import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:linkless/ble/ble_central_service.dart';
import 'package:linkless/ble/ble_constants.dart';
import 'package:linkless/ble/ble_peripheral_service.dart';
import 'package:linkless/ble/platform/android_background_ble.dart';
import 'package:linkless/ble/platform/ios_background_ble.dart';
import 'package:linkless/ble/proximity_state_machine.dart';

/// Combined proximity event from either Central discovery or GATT exchange.
class BleProximityEvent {
  /// The peer's user ID (available after GATT exchange, empty if only scanned).
  final String peerId;

  /// The device identifier (MAC on Android, UUID on iOS).
  final String deviceId;

  /// The RSSI signal strength.
  final int rssi;

  /// When this event occurred.
  final DateTime timestamp;

  /// Whether this event is from a GATT exchange (true) or scan only (false).
  final bool isExchanged;

  const BleProximityEvent({
    required this.peerId,
    required this.deviceId,
    required this.rssi,
    required this.timestamp,
    this.isExchanged = false,
  });

  @override
  String toString() =>
      'BleProximityEvent(peerId: $peerId, deviceId: $deviceId, '
      'rssi: $rssi, exchanged: $isExchanged)';
}

/// Result of BLE permission requests.
class BlePermissionResult {
  final bool allGranted;
  final List<String> deniedPermissions;

  const BlePermissionResult({
    required this.allGranted,
    this.deniedPermissions = const [],
  });

  @override
  String toString() =>
      'BlePermissionResult(allGranted: $allGranted, denied: $deniedPermissions)';
}

/// High-level BLE manager that orchestrates both Central and Peripheral roles,
/// platform-specific background handlers, and the proximity state machine.
///
/// Manages the full BLE lifecycle:
/// - Checks Bluetooth adapter state
/// - Requests runtime permissions
/// - Initializes platform handlers (iOS state restoration, Android foreground service)
/// - Starts both Central scanning and Peripheral advertising simultaneously
/// - Feeds scan results into the proximity state machine for RSSI filtering
/// - Merges discovery and exchange events into a unified proximity stream
/// - Handles adapter state changes (Bluetooth on/off)
/// - Switches scan modes based on foreground/background state (Android)
class BleManager {
  /// Singleton instance for simple access from the debug screen.
  static final BleManager instance = BleManager._internal();

  factory BleManager() => instance;

  BleManager._internal();

  final BleCentralService _centralService = BleCentralService();
  final BlePeripheralService _peripheralService = BlePeripheralService();
  final ProximityStateMachine _stateMachine = ProximityStateMachine(
    enterThreshold: BleConstants.enterRssiThreshold,
    exitThreshold: BleConstants.exitRssiThreshold,
    debounceDuration: BleConstants.debounceTimeout,
  );

  /// iOS-specific background handler. Null on non-iOS platforms.
  IosBackgroundBle? _iosBackgroundBle;

  /// Android-specific background handler. Null on non-Android platforms.
  AndroidBackgroundBle? _androidBackgroundBle;

  final StreamController<BleProximityEvent> _proximityController =
      StreamController<BleProximityEvent>.broadcast();

  /// Controller for log events consumed by the debug screen.
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  StreamSubscription<BleDiscoveryEvent>? _discoverySubscription;
  StreamSubscription<BleExchangeResult>? _exchangeSubscription;
  StreamSubscription<String>? _peripheralExchangeSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<ProximityEvent>? _stateMachineSubscription;
  StreamSubscription<bool>? _backgroundStateSubscription;

  Timer? _scanCycleTimer;
  bool _isRunning = false;
  bool _isInitialized = false;
  String _currentUserId = '';

  /// Set of blocked user IDs. Proximity events from these users are
  /// filtered out before reaching the state machine.
  Set<String> _blockedUserIds = {};

  /// Set of device IDs that have already undergone GATT exchange.
  /// Prevents repeated exchange attempts for the same device in one session.
  final Set<String> _exchangedDeviceIds = {};

  /// Map of device ID to user ID from successful exchanges.
  final Map<String, String> _deviceToUserIdMap = {};

  // ---------------------------------------------------------------------------
  // Public Getters
  // ---------------------------------------------------------------------------

  /// Central service instance (exposed for advanced usage).
  BleCentralService get centralService => _centralService;

  /// Peripheral service instance (exposed for advanced usage).
  BlePeripheralService get peripheralService => _peripheralService;

  /// Proximity state machine instance (exposed for debug screen).
  ProximityStateMachine get stateMachine => _stateMachine;

  /// Unified stream of proximity events from both Central and Peripheral roles.
  Stream<BleProximityEvent> get proximityStream =>
      _proximityController.stream;

  /// Stream of proximity state changes (detected/lost) from the state machine.
  Stream<ProximityEvent> get proximityStateStream => _stateMachine.events;

  /// Stream of log messages for the debug screen.
  Stream<String> get logStream => _logController.stream;

  /// Whether the BLE manager is currently running (scanning + advertising).
  bool get isRunning => _isRunning;

  /// Whether the BLE manager has been initialized.
  bool get isInitialized => _isInitialized;

  /// The current user ID being used for GATT exchange.
  String get currentUserId => _currentUserId;

  /// Map of device ID to exchanged user ID (for debug display).
  Map<String, String> get deviceToUserIdMap =>
      Map.unmodifiable(_deviceToUserIdMap);

  /// iOS background handler (null on non-iOS).
  IosBackgroundBle? get iosBackgroundBle => _iosBackgroundBle;

  /// Android background handler (null on non-Android).
  AndroidBackgroundBle? get androidBackgroundBle => _androidBackgroundBle;

  // ---------------------------------------------------------------------------
  // Blocked Users
  // ---------------------------------------------------------------------------

  /// Update the set of blocked user IDs.
  ///
  /// Proximity events from users in this set are silently dropped
  /// before reaching the state machine.
  void updateBlockedUsers(Set<String> blockedIds) {
    _blockedUserIds = blockedIds;
    _log('Blocked users updated: ${blockedIds.length} user(s)');
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialize the BLE manager with platform-specific handlers.
  ///
  /// On iOS: Creates and initializes IosBackgroundBle for state restoration.
  /// On Android: Creates and initializes AndroidBackgroundBle for foreground service.
  ///
  /// Must be called before [start].
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Platform-specific initialization
    if (Platform.isIOS) {
      _iosBackgroundBle = IosBackgroundBle();
      await _iosBackgroundBle!.initialize();
      await _iosBackgroundBle!.handleStateRestoration();
      _log('iOS background BLE initialized with state restoration');
    } else if (Platform.isAndroid) {
      _androidBackgroundBle = AndroidBackgroundBle();
      await _androidBackgroundBle!.initialize();
      _log('Android background BLE initialized');
    }

    // Initialize Central service (sets up FlutterBluePlus options on iOS)
    await _centralService.initialize();

    // Listen for adapter state changes
    _adapterStateSubscription =
        FlutterBluePlus.adapterState.listen(_onAdapterStateChanged);

    // Listen for proximity state machine events and forward them
    _stateMachineSubscription = _stateMachine.events.listen(_onProximityEvent);

    // Subscribe to platform background state changes
    _subscribeToBackgroundState();

    _isInitialized = true;
    _log('BLE Manager initialized');
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request all BLE-related permissions.
  ///
  /// On Android: requests Bluetooth scan, connect, advertise, and location.
  /// On iOS: Bluetooth permissions are requested implicitly.
  Future<BlePermissionResult> requestPermissions() async {
    final List<Permission> permissions = [];
    final List<String> denied = [];

    if (Platform.isAndroid) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ]);
    } else if (Platform.isIOS) {
      permissions.add(Permission.bluetooth);
    }

    if (permissions.isEmpty) {
      return const BlePermissionResult(allGranted: true);
    }

    final statuses = await permissions.request();

    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        denied.add(entry.key.toString());
      }
    }

    final result = BlePermissionResult(
      allGranted: denied.isEmpty,
      deniedPermissions: denied,
    );

    _log('Permissions requested: ${result.allGranted ? "all granted" : "denied: ${result.deniedPermissions}"}');
    return result;
  }

  /// Check if Bluetooth is currently on.
  Future<bool> isBluetoothOn() async {
    final state = FlutterBluePlus.adapterStateNow;
    return state == BluetoothAdapterState.on;
  }

  // ---------------------------------------------------------------------------
  // Start / Stop
  // ---------------------------------------------------------------------------

  /// Start both Central scanning and Peripheral advertising.
  ///
  /// [userId] is the current user's ID for the GATT exchange.
  /// On Android, starts the foreground service before BLE operations.
  /// On iOS, state preservation is already configured from initialize().
  Future<void> start(String userId) async {
    if (_isRunning) return;

    _currentUserId = userId;
    _isRunning = true;
    _exchangedDeviceIds.clear();
    _deviceToUserIdMap.clear();

    _log('Starting BLE with userId: $userId');

    // Android: start foreground service before BLE scan
    if (Platform.isAndroid && _androidBackgroundBle != null) {
      final started = await _androidBackgroundBle!.startForegroundService();
      _log('Android foreground service ${started ? "started" : "failed to start"}');
    }

    // Subscribe to Central discovery events
    _discoverySubscription =
        _centralService.discoveryStream.listen(_onDiscovery);

    // Subscribe to Central exchange results
    _exchangeSubscription =
        _centralService.exchangeStream.listen(_onExchange);

    // Subscribe to Peripheral peer user ID writes
    _peripheralExchangeSubscription =
        _peripheralService.peerUserIdStream.listen(_onPeripheralExchange);

    // Initialize Peripheral GATT server before advertising
    await _peripheralService.initialize();

    // Start both roles concurrently
    await Future.wait([
      _startScanCycle(),
      _peripheralService.startAdvertising(userId),
    ]);

    _log('BLE started: scanning and advertising');
  }

  /// Stop both Central scanning and Peripheral advertising.
  ///
  /// On Android, stops the foreground service.
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;

    // Cancel scan cycle timer
    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;

    await Future.wait([
      _centralService.stopScanning(),
      _peripheralService.stopAdvertising(),
    ]);

    await _discoverySubscription?.cancel();
    _discoverySubscription = null;

    await _exchangeSubscription?.cancel();
    _exchangeSubscription = null;

    await _peripheralExchangeSubscription?.cancel();
    _peripheralExchangeSubscription = null;

    // Android: stop foreground service
    if (Platform.isAndroid && _androidBackgroundBle != null) {
      await _androidBackgroundBle!.stopForegroundService();
      _log('Android foreground service stopped');
    }

    _log('BLE stopped');
  }

  // ---------------------------------------------------------------------------
  // Scan Cycle Management
  // ---------------------------------------------------------------------------

  /// Start a scan cycle: scan for scanTimeout duration, then repeat.
  Future<void> _startScanCycle() async {
    await _performScan();

    // Schedule next scan cycle after a brief interval
    _scheduleScanCycle();
  }

  /// Perform a single scan cycle.
  Future<void> _performScan() async {
    if (!_isRunning) return;

    try {
      _log('Scan started');
      await _centralService.startScanning();
      _log('Scan completed');
    } catch (e) {
      _log('Scan error: $e');
      // Scan may fail if adapter is off or permissions denied.
      // The adapter state listener will restart scanning when
      // Bluetooth is turned back on.
    }
  }

  /// Schedule the next scan cycle after a brief interval.
  void _scheduleScanCycle() {
    if (!_isRunning) return;

    _scanCycleTimer?.cancel();
    _scanCycleTimer = Timer(BleConstants.scanInterval, () {
      if (_isRunning) {
        _startScanCycle();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Background Mode Switching
  // ---------------------------------------------------------------------------

  /// Subscribe to platform-specific background state changes.
  void _subscribeToBackgroundState() {
    if (Platform.isIOS && _iosBackgroundBle != null) {
      _backgroundStateSubscription =
          _iosBackgroundBle!.isInBackground.listen((isBackground) {
        if (isBackground) {
          _log('iOS entered background -- scan interval will increase to ~30-60s');
          // iOS manages BLE throttling automatically, no action needed
        } else {
          _log('iOS returned to foreground');
          // Restart scan cycle for faster detection in foreground
          if (_isRunning) {
            _restartScanCycle();
          }
        }
      });
    } else if (Platform.isAndroid && _androidBackgroundBle != null) {
      _backgroundStateSubscription =
          _androidBackgroundBle!.backgroundStateStream.listen((isBackground) {
        if (isBackground) {
          _log('Android entered background -- switching to LOW_POWER scan mode');
        } else {
          _log('Android returned to foreground -- switching to BALANCED scan mode');
        }
        // Restart scan cycle with appropriate mode
        if (_isRunning) {
          _restartScanCycle();
        }
      });
    }
  }

  /// Restart the scan cycle (e.g., when switching foreground/background).
  void _restartScanCycle() {
    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;
    _centralService.stopScanning().then((_) {
      if (_isRunning) {
        _startScanCycle();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Event Handlers
  // ---------------------------------------------------------------------------

  /// Handle Central discovery events -- feed into state machine.
  void _onDiscovery(BleDiscoveryEvent event) {
    // Filter blocked users if their user ID is already known
    final knownUserId = _deviceToUserIdMap[event.deviceId];
    if (knownUserId != null && _blockedUserIds.contains(knownUserId)) {
      return;
    }

    // Feed RSSI into the proximity state machine
    _stateMachine.onPeerDiscovered(event.deviceId, event.rssi);

    // Emit raw proximity event
    _proximityController.add(BleProximityEvent(
      peerId: _deviceToUserIdMap[event.deviceId] ?? '',
      deviceId: event.deviceId,
      rssi: event.rssi,
      timestamp: event.timestamp,
      isExchanged: false,
    ));

    _log('Peer discovered: ${_truncateId(event.deviceId)} RSSI: ${event.rssi}');

    // Attempt GATT exchange for new peers
    if (!_exchangedDeviceIds.contains(event.deviceId)) {
      _attemptGattExchange(event.deviceId, event.rssi);
    }
  }

  /// Handle Central GATT exchange results -- update state machine identity.
  void _onExchange(BleExchangeResult result) {
    _exchangedDeviceIds.add(result.deviceId);
    _deviceToUserIdMap[result.deviceId] = result.peerUserId;

    // Filter blocked users before emitting proximity events
    if (_blockedUserIds.contains(result.peerUserId)) {
      _log('Blocked user filtered from exchange: ${_truncateId(result.peerUserId)}');
      return;
    }

    _proximityController.add(BleProximityEvent(
      peerId: result.peerUserId,
      deviceId: result.deviceId,
      rssi: result.rssi,
      timestamp: result.timestamp,
      isExchanged: true,
    ));

    _log('GATT exchange: sent $_currentUserId, received ${result.peerUserId}');
  }

  /// Handle Peripheral peer user ID writes.
  void _onPeripheralExchange(String peerUserId) {
    // Filter blocked users before emitting proximity events
    if (_blockedUserIds.contains(peerUserId)) {
      _log('Blocked user filtered from peripheral exchange: ${_truncateId(peerUserId)}');
      return;
    }

    _proximityController.add(BleProximityEvent(
      peerId: peerUserId,
      deviceId: '',
      rssi: 0,
      timestamp: DateTime.now(),
      isExchanged: true,
    ));

    _log('Peripheral received peer userId: $peerUserId');
  }

  /// Handle proximity state machine events (detected/lost).
  void _onProximityEvent(ProximityEvent event) {
    final userId = _deviceToUserIdMap[event.peerId] ?? event.peerId;
    final eventType = event.type == ProximityEventType.detected
        ? 'DETECTED'
        : 'LOST';
    _log('Proximity $eventType: ${_truncateId(userId)}');
  }

  /// Attempt GATT exchange with a discovered device.
  Future<void> _attemptGattExchange(String deviceId, int rssi) async {
    if (_exchangedDeviceIds.contains(deviceId)) return;

    // Mark as attempted to prevent duplicate attempts
    _exchangedDeviceIds.add(deviceId);

    try {
      final device = BluetoothDevice.fromId(deviceId);
      await _centralService.exchangeUserIds(
        device,
        _currentUserId,
        rssi: rssi,
      );
    } catch (e) {
      // Exchange failed -- remove from exchanged set so it can be retried
      // on next discovery. This handles transient connection failures.
      _exchangedDeviceIds.remove(deviceId);
      _log('GATT exchange failed for ${_truncateId(deviceId)}: $e');
    }
  }

  /// Handle Bluetooth adapter state changes.
  void _onAdapterStateChanged(BluetoothAdapterState state) {
    _log('Bluetooth adapter state: $state');

    if (state == BluetoothAdapterState.on && _isRunning) {
      // Bluetooth turned back on while we should be running,
      // restart scanning and advertising.
      _startScanCycle();
      _peripheralService.startAdvertising(_currentUserId);
    } else if (state != BluetoothAdapterState.on && _isRunning) {
      // Bluetooth turned off, scanning and advertising will
      // automatically stop. We keep _isRunning = true so we
      // restart when Bluetooth is turned back on.
      _scanCycleTimer?.cancel();
      _scanCycleTimer = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Clean up all resources.
  Future<void> dispose() async {
    await stop();

    await _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;

    await _stateMachineSubscription?.cancel();
    _stateMachineSubscription = null;

    await _backgroundStateSubscription?.cancel();
    _backgroundStateSubscription = null;

    _stateMachine.dispose();

    await _centralService.dispose();
    await _peripheralService.dispose();

    // Dispose platform handlers
    _iosBackgroundBle?.dispose();
    _iosBackgroundBle = null;

    await _androidBackgroundBle?.dispose();
    _androidBackgroundBle = null;

    await _proximityController.close();
    await _logController.close();

    _isInitialized = false;
    _isRunning = false;
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Emit a timestamped log message.
  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logLine = '[$timestamp] $message';
    debugPrint('[BleManager] $logLine');
    if (!_logController.isClosed) {
      _logController.add(logLine);
    }
  }

  /// Truncate a device/user ID for readable log output.
  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}...';
  }
}
