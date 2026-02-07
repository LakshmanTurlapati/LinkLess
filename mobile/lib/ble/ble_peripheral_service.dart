import 'dart:async';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import 'package:linkless/ble/ble_constants.dart';

/// BLE Peripheral role service for advertising and GATT server.
///
/// Advertises the Linkless service UUID so that Central-role devices
/// can discover this device. In a full implementation, the GATT server
/// would host a characteristic that Centrals read (to get this device's
/// user ID) and write to (to deliver their own user ID).
///
/// NOTE: flutter_ble_peripheral (v2.1.0) supports BLE advertising but
/// does NOT support hosting custom GATT services/characteristics with
/// read/write handlers. For full GATT server support, a different package
/// such as ble_peripheral would be needed. The advertising functionality
/// works correctly and is sufficient for device discovery. The GATT server
/// methods are stubbed below with clear documentation of the intended
/// behavior.
class BlePeripheralService {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  final StreamController<String> _peerUserIdController =
      StreamController<String>.broadcast();

  bool _isAdvertising = false;
  String _currentUserId = '';

  /// Stream of peer user IDs received when a Central writes its user ID
  /// to our GATT characteristic.
  ///
  /// NOTE: This stream will not emit values until GATT server support is
  /// implemented. Currently, user ID exchange only works in the Central
  /// direction (Central reads/writes on the Peripheral's GATT server).
  /// The Peripheral side requires a package that supports hosting GATT
  /// services with read/write callbacks.
  Stream<String> get peerUserIdStream => _peerUserIdController.stream;

  /// Whether the Peripheral is currently advertising.
  bool get isAdvertising => _isAdvertising;

  /// The current user ID being advertised via GATT.
  String get currentUserId => _currentUserId;

  /// Start advertising the Linkless service UUID.
  ///
  /// [userId] is the current user's ID that will be exposed via the GATT
  /// characteristic for Centrals to read during the exchange.
  ///
  /// On Android, advertising uses low-latency mode with connectable=true
  /// so that Central devices can initiate GATT connections. On iOS,
  /// the service UUID is included in the overflow area for background
  /// advertising.
  Future<void> startAdvertising(String userId) async {
    if (_isAdvertising) return;

    _currentUserId = userId;

    final advertiseData = AdvertiseData(
      serviceUuid: BleConstants.serviceUuidString,
      includeDeviceName: false,
    );

    final advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeLowLatency,
      connectable: true,
      timeout: 0, // Advertise indefinitely
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerLow,
    );

    await _peripheral.start(
      advertiseData: advertiseData,
      advertiseSettings: advertiseSettings,
    );

    _isAdvertising = true;

    // TODO(GATT Server): flutter_ble_peripheral does not support hosting
    // custom GATT services with read/write characteristics. To enable
    // the full user ID exchange pattern, implement GATT server using
    // the ble_peripheral package (v2.4.0+). The GATT server should:
    //
    // 1. Create a GATT service with BleConstants.serviceUuid
    // 2. Add a characteristic with BleConstants.userIdCharacteristicUuid
    //    - Properties: read, write
    //    - Permissions: readable, writeable
    // 3. On read request: return utf8.encode(_currentUserId)
    // 4. On write request: decode the written bytes as UTF-8 and emit
    //    the peer's user ID on peerUserIdStream
    //
    // This is critical for iOS background detection where the Central
    // role may not be active. The GATT connection exchange pattern
    // (from TraceTogether/BlueTrace) ensures both devices can exchange
    // IDs regardless of which one is in the Central vs Peripheral role.
  }

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    await _peripheral.stop();
    _isAdvertising = false;
  }

  /// Called when a Central device writes its user ID to our GATT
  /// characteristic.
  ///
  /// NOTE: This is a stub that will be called by the GATT server
  /// write handler once GATT server support is implemented. For now,
  /// it can be called manually for testing purposes.
  void onPeerUserIdReceived(String peerUserId) {
    if (peerUserId.isNotEmpty) {
      _peerUserIdController.add(peerUserId);
    }
  }

  /// Get the Peripheral's current state stream.
  Stream<PeripheralState>? get onStateChanged =>
      _peripheral.onPeripheralStateChanged;

  /// Check if advertising is supported on this device.
  Future<bool> get isSupported => _peripheral.isSupported;

  /// Clean up resources.
  Future<void> dispose() async {
    await stopAdvertising();
    await _peerUserIdController.close();
  }
}
