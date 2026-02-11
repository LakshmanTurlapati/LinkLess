import 'dart:async';
import 'dart:convert';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/widgets.dart';

import 'package:linkless/ble/ble_constants.dart';

/// BLE Peripheral role service for advertising and GATT server.
///
/// Advertises the Linkless service UUID and hosts a GATT service with a
/// read/write characteristic for user ID exchange. Central-role devices
/// can read this device's user ID and write their own user ID to the
/// characteristic.
class BlePeripheralService {
  final StreamController<String> _peerUserIdController =
      StreamController<String>.broadcast();

  bool _isAdvertising = false;
  bool _isInitialized = false;
  String _currentUserId = '';

  /// Stream of peer user IDs received when a Central writes its user ID
  /// to our GATT characteristic.
  Stream<String> get peerUserIdStream => _peerUserIdController.stream;

  /// Whether the Peripheral is currently advertising.
  bool get isAdvertising => _isAdvertising;

  /// The current user ID being advertised via GATT.
  String get currentUserId => _currentUserId;

  /// Initialize the BLE peripheral and set up read/write callbacks.
  ///
  /// Must be called before [startAdvertising].
  Future<void> initialize() async {
    if (_isInitialized) return;

    await BlePeripheral.initialize();

    BlePeripheral.setReadRequestCallback(
        (String deviceId, String characteristicId, int offset, List<int>? value) {
      if (characteristicId.toLowerCase() ==
          BleConstants.userIdCharacteristicUuidString.toLowerCase()) {
        debugPrint(
          '[BlePeripheralService] Read request from $deviceId — '
          'returning userId: $_currentUserId',
        );
        return ReadRequestResult(value: utf8.encode(_currentUserId));
      }
      return null;
    });

    BlePeripheral.setWriteRequestCallback(
        (String deviceId, String characteristicId, int offset, List<int>? value) {
      if (characteristicId.toLowerCase() ==
              BleConstants.userIdCharacteristicUuidString.toLowerCase() &&
          value != null) {
        final peerUserId = utf8.decode(value);
        debugPrint(
          '[BlePeripheralService] Write request from $deviceId — '
          'peerUserId: $peerUserId',
        );
        onPeerUserIdReceived(peerUserId);
      }
      return null;
    });

    _isInitialized = true;
    debugPrint('[BlePeripheralService] Initialized');
  }

  /// Start advertising the Linkless service UUID and host the GATT service.
  ///
  /// [userId] is the current user's ID that will be exposed via the GATT
  /// characteristic for Centrals to read during the exchange.
  Future<void> startAdvertising(String userId) async {
    if (_isAdvertising) return;

    _currentUserId = userId;

    // Set up the GATT service with a read/write characteristic
    final characteristic = BleCharacteristic(
      uuid: BleConstants.userIdCharacteristicUuidString,
      properties: [
        CharacteristicProperties.read.index,
        CharacteristicProperties.write.index,
      ],
      permissions: [
        AttributePermissions.readable.index,
        AttributePermissions.writeable.index,
      ],
      value: null,
    );

    final service = BleService(
      uuid: BleConstants.serviceUuidString,
      primary: true,
      characteristics: [characteristic],
    );

    await BlePeripheral.addService(service);

    await BlePeripheral.startAdvertising(
      services: [BleConstants.serviceUuidString],
      localName: null, // don't broadcast device name
    );

    _isAdvertising = true;
    debugPrint('[BlePeripheralService] Advertising started with GATT service');
  }

  /// Called when a Central device writes its user ID to our GATT
  /// characteristic.
  void onPeerUserIdReceived(String peerUserId) {
    if (peerUserId.isNotEmpty) {
      _peerUserIdController.add(peerUserId);
    }
  }

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    await BlePeripheral.stopAdvertising();
    _isAdvertising = false;
    debugPrint('[BlePeripheralService] Advertising stopped');
  }

  /// Clean up resources.
  Future<void> dispose() async {
    await stopAdvertising();
    await _peerUserIdController.close();
  }
}
