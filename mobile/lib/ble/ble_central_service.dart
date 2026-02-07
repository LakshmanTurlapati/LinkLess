import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:linkless/ble/ble_constants.dart';

/// Event emitted when a Linkless peer is discovered during BLE scanning.
class BleDiscoveryEvent {
  /// The device identifier (platform-specific: MAC on Android, UUID on iOS).
  final String deviceId;

  /// The RSSI signal strength at time of discovery.
  final int rssi;

  /// The timestamp of the discovery event.
  final DateTime timestamp;

  /// The advertised device name, if any.
  final String deviceName;

  const BleDiscoveryEvent({
    required this.deviceId,
    required this.rssi,
    required this.timestamp,
    this.deviceName = '',
  });

  @override
  String toString() =>
      'BleDiscoveryEvent(deviceId: $deviceId, rssi: $rssi, name: $deviceName)';
}

/// Result of a GATT user ID exchange with a peer device.
class BleExchangeResult {
  /// The user ID read from the peer's GATT characteristic.
  final String peerUserId;

  /// The device identifier of the peer.
  final String deviceId;

  /// The RSSI at time of exchange.
  final int rssi;

  /// The timestamp of the exchange.
  final DateTime timestamp;

  const BleExchangeResult({
    required this.peerUserId,
    required this.deviceId,
    required this.rssi,
    required this.timestamp,
  });

  @override
  String toString() =>
      'BleExchangeResult(peerUserId: $peerUserId, deviceId: $deviceId, rssi: $rssi)';
}

/// BLE Central role service for scanning and GATT user ID exchange.
///
/// Scans for nearby devices advertising the Linkless service UUID,
/// then connects to each discovered peripheral to exchange user IDs
/// via the GATT characteristic. This is the "connection-based exchange"
/// pattern used by COVID contact tracing apps (e.g., TraceTogether) to
/// enable reliable cross-platform iOS background detection.
class BleCentralService {
  final StreamController<BleDiscoveryEvent> _discoveryController =
      StreamController<BleDiscoveryEvent>.broadcast();

  final StreamController<BleExchangeResult> _exchangeController =
      StreamController<BleExchangeResult>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;

  bool _isScanning = false;

  /// Stream of discovery events when Linkless peers are found during scanning.
  Stream<BleDiscoveryEvent> get discoveryStream => _discoveryController.stream;

  /// Stream of exchange results after successful GATT user ID exchanges.
  Stream<BleExchangeResult> get exchangeStream => _exchangeController.stream;

  /// Whether the Central is currently scanning.
  bool get isScanning => _isScanning;

  /// Initialize the Central service.
  ///
  /// Configures iOS state restoration so the system can re-launch the app
  /// after it has been terminated while a BLE scan was in progress.
  Future<void> initialize() async {
    await FlutterBluePlus.setOptions(restoreState: true);
  }

  /// Start scanning for devices advertising the Linkless service UUID.
  ///
  /// Uses [FlutterBluePlus.startScan] with a service UUID filter to only
  /// discover Linkless peers. Scan results are emitted on [discoveryStream].
  /// The scan runs for [BleConstants.scanTimeout] before automatically
  /// stopping.
  Future<void> startScanning() async {
    if (_isScanning) return;

    _isScanning = true;

    // Listen to scan results and emit discovery events
    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          final event = BleDiscoveryEvent(
            deviceId: result.device.remoteId.str,
            rssi: result.rssi,
            timestamp: DateTime.now(),
            deviceName: result.advertisementData.advName,
          );
          _discoveryController.add(event);
        }
      },
      onError: (Object error) {
        _discoveryController.addError(error);
      },
    );

    // Register subscription to be canceled when scan completes
    FlutterBluePlus.cancelWhenScanComplete(_scanSubscription!);

    try {
      await FlutterBluePlus.startScan(
        withServices: [BleConstants.serviceUuid],
        timeout: BleConstants.scanTimeout,
        continuousUpdates: true,
        continuousDivisor: 3,
      );
    } catch (e) {
      _isScanning = false;
      rethrow;
    }

    _isScanning = false;
  }

  /// Stop an active scan.
  Future<void> stopScanning() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _isScanning = false;
  }

  /// Exchange user IDs with a discovered peripheral device via GATT.
  ///
  /// This implements the connection-based exchange pattern:
  /// 1. Connect to the [device]
  /// 2. Discover services
  /// 3. Find the Linkless service and user ID characteristic
  /// 4. Read the peer's user ID from the characteristic
  /// 5. Write [myUserId] to the characteristic
  /// 6. Disconnect
  ///
  /// Returns a [BleExchangeResult] on success, or throws on failure.
  /// Connection is subject to [BleConstants.connectionTimeout].
  Future<BleExchangeResult?> exchangeUserIds(
    BluetoothDevice device,
    String myUserId, {
    int rssi = 0,
  }) async {
    try {
      // Connect with timeout
      await device.connect(
        license: License.free,
        timeout: BleConstants.connectionTimeout,
        mtu: null,
        autoConnect: false,
      );

      // Discover services
      final services = await device.discoverServices(
        timeout: BleConstants.serviceDiscoveryTimeoutSeconds,
      );

      // Find the Linkless service
      BluetoothService? linklessService;
      for (final service in services) {
        if (service.serviceUuid == BleConstants.serviceUuid) {
          linklessService = service;
          break;
        }
      }

      if (linklessService == null) {
        await device.disconnect();
        return null;
      }

      // Find the user ID characteristic
      BluetoothCharacteristic? userIdCharacteristic;
      for (final chr in linklessService.characteristics) {
        if (chr.characteristicUuid == BleConstants.userIdCharacteristicUuid) {
          userIdCharacteristic = chr;
          break;
        }
      }

      if (userIdCharacteristic == null) {
        await device.disconnect();
        return null;
      }

      // Read the peer's user ID
      final peerIdBytes = await userIdCharacteristic.read();
      final peerUserId = utf8.decode(peerIdBytes);

      if (peerUserId.isEmpty) {
        await device.disconnect();
        return null;
      }

      // Write our user ID to the characteristic
      final myIdBytes = utf8.encode(myUserId);
      await userIdCharacteristic.write(myIdBytes);

      // Disconnect
      await device.disconnect();

      final result = BleExchangeResult(
        peerUserId: peerUserId,
        deviceId: device.remoteId.str,
        rssi: rssi,
        timestamp: DateTime.now(),
      );

      _exchangeController.add(result);
      return result;
    } catch (e) {
      // Ensure we disconnect on any error
      try {
        if (device.isConnected) {
          await device.disconnect();
        }
      } catch (_) {
        // Ignore disconnect errors during cleanup
      }
      rethrow;
    }
  }

  /// Clean up resources.
  Future<void> dispose() async {
    await stopScanning();
    await _scanSubscription?.cancel();
    await _discoveryController.close();
    await _exchangeController.close();
  }
}
