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
  Timer? _peerStalenessTimer;
  bool _isRunning = false;
  bool _isInitialized = false;
  String _currentUserId = '';

  /// Cached Bluetooth adapter state, updated by _onAdapterStateChanged.
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  /// Set of blocked user IDs. Proximity events from these users are
  /// filtered out before reaching the state machine.
  Set<String> _blockedUserIds = {};

  /// Set of device IDs that have already undergone GATT exchange.
  /// Prevents repeated exchange attempts for the same device in one session.
  final Set<String> _exchangedDeviceIds = {};

  /// Map of device ID to user ID from successful exchanges.
  final Map<String, String> _deviceToUserIdMap = {};

  /// Cooldown tracker: last GATT exchange attempt time per device.
  final Map<String, DateTime> _lastExchangeAttempt = {};

  /// Set of device IDs already logged this scan cycle (avoids log flooding).
  final Set<String> _discoveryLoggedThisCycle = {};

  /// Set of resolved peer IDs seen during the current scan cycle.
  /// Used at scan cycle end to detect peers that have disappeared.
  final Set<String> _peerIdsSeenThisCycle = {};

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

  /// Current Bluetooth adapter state (updated via adapter state listener).
  BluetoothAdapterState get adapterState => _adapterState;

  /// The current user ID being used for GATT exchange.
  String get currentUserId => _currentUserId;

  /// Map of device ID to exchanged user ID (for debug display).
  Map<String, String> get deviceToUserIdMap =>
      Map.unmodifiable(_deviceToUserIdMap);

  /// Number of devices that have completed GATT exchange this session.
  int get exchangedDeviceCount => _exchangedDeviceIds.length;

  /// Whether a device has completed GATT exchange.
  bool isDeviceExchanged(String deviceId) =>
      _exchangedDeviceIds.contains(deviceId);

  /// Clear exchanged device tracking (for debug/testing).
  void clearExchangedDevices() {
    _exchangedDeviceIds.clear();
    _deviceToUserIdMap.clear();
    _log('Exchanged devices cleared');
  }

  /// Remove a peer from the proximity state machine so it can be
  /// re-detected on the next BLE scan cycle.
  ///
  /// Called after an identity chain failure so the peer is not stuck
  /// in DETECTED state permanently. The next scan that discovers the
  /// peer will create a fresh entry and emit a new DETECTED event.
  void resetPeerTracking(String peerId) {
    _stateMachine.resetPeer(peerId);
    _log('Peer tracking reset: ${_truncateId(peerId)}');
  }

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
    }

    // On iOS, Bluetooth authorization is handled via Info.plist declarations
    // and Core Bluetooth internally -- there is no runtime permission dialog.
    // permission_handler falsely reports it as permanentlyDenied.
    // Instead, check the actual adapter state. We only flag it as denied when
    // the adapter is explicitly off or unauthorized -- 'unknown' just means
    // Core Bluetooth hasn't finished initializing yet.
    if (Platform.isIOS) {
      final adapterState = FlutterBluePlus.adapterStateNow;
      if (adapterState == BluetoothAdapterState.off ||
          adapterState == BluetoothAdapterState.unauthorized) {
        denied.add('Bluetooth (adapter ${adapterState.name})');
      }
    }

    if (permissions.isNotEmpty) {
      final statuses = await permissions.request();

      for (final entry in statuses.entries) {
        if (!entry.value.isGranted) {
          denied.add(entry.key.toString());
        }
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

    // Wait for Bluetooth adapter to be powered on before starting peripheral.
    // On iOS, CBPeripheralManager needs poweredOn state before addService/
    // startAdvertising -- calling too early causes "API MISUSE" and timeouts.
    try {
      final currentState = FlutterBluePlus.adapterStateNow;
      if (currentState != BluetoothAdapterState.on) {
        _log('Waiting for Bluetooth adapter to power on (current: $currentState)...');
        await FlutterBluePlus.adapterState
            .firstWhere((s) => s == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 10));
        _log('Bluetooth adapter powered on');
      }
    } on TimeoutException {
      _log('Bluetooth adapter power-on timed out -- skipping peripheral advertising');
      // Still start scanning even if advertising can't start
      await _startScanCycle();
      _peerStalenessTimer?.cancel();
      _peerStalenessTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkPeerStaleness(),
      );
      _log('BLE started: scanning only (advertising skipped)');
      return;
    }

    // Start both roles concurrently
    await Future.wait([
      _startScanCycle(),
      _peripheralService.startAdvertising(userId),
    ]);

    // Start periodic staleness check for faster peer-lost detection
    _peerStalenessTimer?.cancel();
    _peerStalenessTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkPeerStaleness(),
    );

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

    // Cancel staleness timer
    _peerStalenessTimer?.cancel();
    _peerStalenessTimer = null;

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

    // After scan completes, check for detected peers that were NOT seen
    // during this cycle. If a peer disappeared (e.g., other device turned
    // off Bluetooth), start their debounce timer via onPeerLost().
    _checkForAbsentPeers();

    // Schedule next scan cycle after a brief interval
    _scheduleScanCycle();
  }

  /// Perform a single scan cycle.
  Future<void> _performScan() async {
    if (!_isRunning) return;

    _discoveryLoggedThisCycle.clear();
    _peerIdsSeenThisCycle.clear();

    try {
      final scanMode = Platform.isAndroid
          ? _androidBackgroundBle?.getRecommendedScanMode()
          : null;
      _log('Scan started${scanMode != null ? ' (mode: $scanMode)' : ''}');
      await _centralService.startScanning(scanMode: scanMode);
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

  /// Check for detected peers not seen during the last scan cycle.
  ///
  /// When a peer disappears from BLE scans (e.g., the other device turned
  /// off Bluetooth or walked out of range), this triggers the debounce
  /// timer via onPeerLost(). After the debounce expires without the peer
  /// reappearing, a LOST event is emitted and RecordingService stops
  /// recording. This ensures the disconnect is mutual -- both devices
  /// stop recording even if only one side turned off Bluetooth.
  void _checkForAbsentPeers() {
    final detectedPeers = _stateMachine.detectedPeerIds;
    if (detectedPeers.isEmpty) return;

    for (final peerId in detectedPeers) {
      if (!_peerIdsSeenThisCycle.contains(peerId)) {
        _stateMachine.onPeerLost(peerId);
        _log('Peer absent from scan: ${_truncateId(peerId)} -- debounce started');
      }
    }
  }

  /// Periodically check for stale peers that haven't been seen in 10+ seconds.
  ///
  /// Runs every 5 seconds to detect peer absence faster than the end-of-cycle
  /// _checkForAbsentPeers(). If a peer hasn't been seen in 10 seconds, starts
  /// debounce via onPeerLost(). Combined with the 5s debounce, worst-case stop
  /// latency drops from ~40s to ~15s.
  void _checkPeerStaleness() {
    if (!_isRunning) return;
    final now = DateTime.now();
    for (final peerId in _stateMachine.detectedPeerIds) {
      final lastSeen = _stateMachine.getLastSeenAt(peerId);
      if (lastSeen == null) continue;
      if (now.difference(lastSeen).inSeconds >= 10) {
        _stateMachine.onPeerLost(peerId);
        _log('Peer stale (${now.difference(lastSeen).inSeconds}s): '
            '${_truncateId(peerId)} -- debounce started');
      }
    }
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

    // Feed RSSI into the proximity state machine.
    // Resolve deviceId to userId if known, so RSSI updates target the
    // correct peer entry after a GATT exchange has completed.
    final resolvedPeerId = _deviceToUserIdMap[event.deviceId] ?? event.deviceId;
    _peerIdsSeenThisCycle.add(resolvedPeerId);
    _stateMachine.onPeerDiscovered(resolvedPeerId, event.rssi);

    // Emit raw proximity event
    _proximityController.add(BleProximityEvent(
      peerId: _deviceToUserIdMap[event.deviceId] ?? '',
      deviceId: event.deviceId,
      rssi: event.rssi,
      timestamp: event.timestamp,
      isExchanged: false,
    ));

    // Log first discovery per device per scan cycle (avoids flooding)
    if (!_discoveryLoggedThisCycle.contains(event.deviceId)) {
      _discoveryLoggedThisCycle.add(event.deviceId);
      _log('Peer discovered: ${_truncateId(event.deviceId)} RSSI: ${event.rssi}');
    }

    // Attempt GATT exchange for new peers
    if (!_exchangedDeviceIds.contains(event.deviceId)) {
      _attemptGattExchange(event.deviceId, event.rssi);
    }
  }

  /// Handle Central GATT exchange results -- update state machine identity.
  void _onExchange(BleExchangeResult result) {
    _exchangedDeviceIds.add(result.deviceId);
    _deviceToUserIdMap[result.deviceId] = result.peerUserId;

    // Remap the peer in the state machine from deviceId to real userId
    // so future events (especially "lost") emit the resolved identity.
    _stateMachine.updatePeerId(result.deviceId, result.peerUserId);

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

    // Cooldown: don't retry a device more than once every 30 seconds
    final lastAttempt = _lastExchangeAttempt[deviceId];
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt).inSeconds < 30) {
      return; // Cooldown -- wait before retrying
    }
    _lastExchangeAttempt[deviceId] = DateTime.now();

    // Mark as in-progress (prevent concurrent attempts for same device)
    _exchangedDeviceIds.add(deviceId);

    try {
      final device = BluetoothDevice.fromId(deviceId);
      final result = await _centralService.exchangeUserIds(
        device,
        _currentUserId,
        rssi: rssi,
      );

      if (result == null) {
        // Exchange returned null (service/characteristic not found, empty peer ID).
        // Remove from exchanged set so it can be retried on next discovery.
        _exchangedDeviceIds.remove(deviceId);
        _log('GATT exchange returned null for ${_truncateId(deviceId)} -- will retry');
      }
      // On success, _onExchange fires via exchangeStream (device stays in set)
    } catch (e) {
      // Exchange failed -- remove from exchanged set so it can be retried
      // on next discovery. This handles transient connection failures.
      _exchangedDeviceIds.remove(deviceId);
      _log('GATT exchange failed for ${_truncateId(deviceId)}: $e');
    }
  }

  /// Handle Bluetooth adapter state changes.
  void _onAdapterStateChanged(BluetoothAdapterState state) {
    _adapterState = state;
    _log('Bluetooth adapter state: $state');

    if (state == BluetoothAdapterState.on && _isRunning) {
      // Bluetooth turned back on while we should be running,
      // restart scanning and advertising.
      _startScanCycle();
      _peripheralService.startAdvertising(_currentUserId);
      // Restart staleness timer
      _peerStalenessTimer?.cancel();
      _peerStalenessTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkPeerStaleness(),
      );
    } else if (state != BluetoothAdapterState.on && _isRunning) {
      // Bluetooth turned off, scanning and advertising will
      // automatically stop. We keep _isRunning = true so we
      // restart when Bluetooth is turned back on.
      _scanCycleTimer?.cancel();
      _scanCycleTimer = null;
      _peerStalenessTimer?.cancel();
      _peerStalenessTimer = null;
      _stateMachine.resetAllPeers();
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

    _peerStalenessTimer?.cancel();
    _peerStalenessTimer = null;

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
