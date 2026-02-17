import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  Future<void> startScanning({AndroidScanMode? scanMode}) async {
    if (_isScanning) return;

    _isScanning = true;

    // Listen to scan results and emit discovery events
    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        // Android scan diagnostics: log when many results arrive but none match
        if (Platform.isAndroid && results.isNotEmpty) {
          final withService = results.where((r) =>
            r.advertisementData.serviceUuids.any((u) => u == BleConstants.serviceUuid)
          ).length;
          if (withService == 0 && results.length > 3) {
            debugPrint(
              '[BleCentralService] Android scan: ${results.length} results, '
              '0 matched Linkless UUID',
            );
          }
        }

        for (final result in results) {
          // On Android (unfiltered scan), manually check service UUIDs
          // because iOS ble_peripheral ads may not include the UUID in
          // a format that Android's hardware filter can match.
          if (Platform.isAndroid) {
            final hasService = result.advertisementData.serviceUuids
                .any((uuid) => uuid == BleConstants.serviceUuid);
            if (!hasService) continue;
          }

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
      // On Android, scan without service filter because iOS ble_peripheral
      // advertisements may not include the UUID in a format Android's
      // hardware filter matches. We filter manually in the results listener.
      // On iOS, keep the filter as it works correctly.
      await FlutterBluePlus.startScan(
        withServices: Platform.isIOS ? [BleConstants.serviceUuid] : [],
        timeout: BleConstants.scanTimeout,
        continuousUpdates: true,
        continuousDivisor: 3,
        androidScanMode: scanMode ?? AndroidScanMode.lowLatency,
      );

      // startScan may resolve before the scan actually finishes on Android.
      // Wait for the scan to truly complete so the scan cycle doesn't
      // restart prematurely and hit Android's "scanning too frequently"
      // throttle.
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning
            .where((scanning) => !scanning)
            .first
            .timeout(
              BleConstants.scanTimeout + const Duration(seconds: 5),
              onTimeout: () => false,
            );
      }
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
      debugPrint('[BleCentralService] Exchange: connecting to ${device.remoteId.str}...');
      await device.connect(
        license: License.free,
        timeout: BleConstants.connectionTimeout,
        mtu: null,
        autoConnect: false,
      );
      debugPrint('[BleCentralService] Exchange: connected, discovering services...');

      // Request larger MTU for UUID exchange (36 bytes + 3 ATT overhead = 39 minimum)
      if (Platform.isAndroid) {
        await device.requestMtu(64);
      }

      // Discover services
      final services = await device.discoverServices(
        subscribeToServicesChanged: false,
        timeout: BleConstants.serviceDiscoveryTimeoutSeconds,
      );
      debugPrint('[BleCentralService] Exchange: found ${services.length} services');

      // Find the Linkless service
      BluetoothService? linklessService;
      for (final service in services) {
        if (service.serviceUuid == BleConstants.serviceUuid) {
          linklessService = service;
          break;
        }
      }

      if (linklessService == null) {
        debugPrint('[BleCentralService] Exchange: Linkless service NOT found on ${device.remoteId.str}');
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
        debugPrint('[BleCentralService] Exchange: userId characteristic NOT found');
        await device.disconnect();
        return null;
      }

      // Read the peer's user ID
      final peerIdBytes = await userIdCharacteristic.read();
      final peerUserId = utf8.decode(peerIdBytes);

      if (peerUserId.isEmpty) {
        debugPrint('[BleCentralService] Exchange: peer userId is EMPTY');
        await device.disconnect();
        return null;
      }

      // Write our user ID to the characteristic
      final myIdBytes = utf8.encode(myUserId);
      await userIdCharacteristic.write(myIdBytes);

      // Disconnect
      await device.disconnect();

      debugPrint('[BleCentralService] Exchange SUCCESS: peer=${peerUserId.substring(0, 8)}...');

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
