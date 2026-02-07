import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:linkless/ble/ble_central_service.dart';
import 'package:linkless/ble/ble_peripheral_service.dart';

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

/// High-level BLE manager that orchestrates both Central and Peripheral roles.
///
/// Manages the full BLE lifecycle:
/// - Checks Bluetooth adapter state
/// - Requests runtime permissions
/// - Starts both Central scanning and Peripheral advertising simultaneously
/// - Merges discovery and exchange events into a unified proximity stream
/// - Handles adapter state changes (Bluetooth on/off)
class BleManager {
  final BleCentralService _centralService = BleCentralService();
  final BlePeripheralService _peripheralService = BlePeripheralService();

  final StreamController<BleProximityEvent> _proximityController =
      StreamController<BleProximityEvent>.broadcast();

  StreamSubscription<BleDiscoveryEvent>? _discoverySubscription;
  StreamSubscription<BleExchangeResult>? _exchangeSubscription;
  StreamSubscription<String>? _peripheralExchangeSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  bool _isRunning = false;
  String _currentUserId = '';

  /// Central service instance (exposed for advanced usage).
  BleCentralService get centralService => _centralService;

  /// Peripheral service instance (exposed for advanced usage).
  BlePeripheralService get peripheralService => _peripheralService;

  /// Unified stream of proximity events from both Central and Peripheral roles.
  ///
  /// Events from Central scanning produce events with [isExchanged] = false
  /// and empty [peerId]. After a successful GATT exchange, an event with
  /// [isExchanged] = true and the peer's user ID is emitted.
  Stream<BleProximityEvent> get proximityStream =>
      _proximityController.stream;

  /// Whether the BLE manager is currently running (scanning + advertising).
  bool get isRunning => _isRunning;

  /// Initialize the BLE manager.
  ///
  /// Sets up iOS state restoration and subscribes to adapter state changes.
  /// Must be called before [start].
  Future<void> initialize() async {
    await _centralService.initialize();

    // Listen for adapter state changes
    _adapterStateSubscription =
        FlutterBluePlus.adapterState.listen(_onAdapterStateChanged);
  }

  /// Request all BLE-related permissions.
  ///
  /// On Android: requests Bluetooth scan, connect, advertise, and location
  /// (for Android < 12). On iOS: Bluetooth permissions are requested implicitly
  /// when the BLE stack is initialized.
  ///
  /// Returns a [BlePermissionResult] indicating whether all permissions
  /// were granted.
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

    return BlePermissionResult(
      allGranted: denied.isEmpty,
      deniedPermissions: denied,
    );
  }

  /// Check if Bluetooth is currently on.
  Future<bool> isBluetoothOn() async {
    final state = FlutterBluePlus.adapterStateNow;
    return state == BluetoothAdapterState.on;
  }

  /// Start both Central scanning and Peripheral advertising.
  ///
  /// [userId] is the current user's ID for the GATT exchange.
  /// Both roles start simultaneously so this device can both discover
  /// and be discovered by other Linkless users.
  ///
  /// Throws if Bluetooth is not available or permissions are not granted.
  Future<void> start(String userId) async {
    if (_isRunning) return;

    _currentUserId = userId;
    _isRunning = true;

    // Subscribe to Central discovery events
    _discoverySubscription =
        _centralService.discoveryStream.listen(_onDiscovery);

    // Subscribe to Central exchange results
    _exchangeSubscription =
        _centralService.exchangeStream.listen(_onExchange);

    // Subscribe to Peripheral peer user ID writes
    _peripheralExchangeSubscription =
        _peripheralService.peerUserIdStream.listen(_onPeripheralExchange);

    // Start both roles concurrently
    await Future.wait([
      _startCentralScanning(),
      _peripheralService.startAdvertising(userId),
    ]);
  }

  /// Stop both Central scanning and Peripheral advertising.
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;

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
  }

  /// Start Central scanning with automatic restart on completion.
  Future<void> _startCentralScanning() async {
    try {
      await _centralService.startScanning();
    } catch (e) {
      // Scan may fail if adapter is off or permissions denied.
      // The adapter state listener will restart scanning when
      // Bluetooth is turned back on.
    }
  }

  /// Handle Central discovery events.
  void _onDiscovery(BleDiscoveryEvent event) {
    _proximityController.add(BleProximityEvent(
      peerId: '',
      deviceId: event.deviceId,
      rssi: event.rssi,
      timestamp: event.timestamp,
      isExchanged: false,
    ));
  }

  /// Handle Central GATT exchange results.
  void _onExchange(BleExchangeResult result) {
    _proximityController.add(BleProximityEvent(
      peerId: result.peerUserId,
      deviceId: result.deviceId,
      rssi: result.rssi,
      timestamp: result.timestamp,
      isExchanged: true,
    ));
  }

  /// Handle Peripheral peer user ID writes.
  void _onPeripheralExchange(String peerUserId) {
    _proximityController.add(BleProximityEvent(
      peerId: peerUserId,
      deviceId: '',
      rssi: 0,
      timestamp: DateTime.now(),
      isExchanged: true,
    ));
  }

  /// Handle Bluetooth adapter state changes.
  void _onAdapterStateChanged(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.on && _isRunning) {
      // Bluetooth turned back on while we should be running,
      // restart scanning and advertising.
      _startCentralScanning();
      _peripheralService.startAdvertising(_currentUserId);
    } else if (state != BluetoothAdapterState.on && _isRunning) {
      // Bluetooth turned off, scanning and advertising will
      // automatically stop. We keep _isRunning = true so we
      // restart when Bluetooth is turned back on.
    }
  }

  /// Clean up all resources.
  Future<void> dispose() async {
    await stop();
    await _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
    await _centralService.dispose();
    await _peripheralService.dispose();
    await _proximityController.close();
  }
}
