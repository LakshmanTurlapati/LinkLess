import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE constants for the Linkless proximity detection system.
///
/// Uses custom 128-bit UUIDs to uniquely identify Linkless devices
/// during BLE scanning and GATT service discovery.
class BleConstants {
  BleConstants._();

  /// Custom service UUID for Linkless BLE proximity detection.
  /// Used by both Central (scanning filter) and Peripheral (advertising).
  static final Guid serviceUuid =
      Guid('603c6e94-03b8-429c-b4a9-38d55567523c');

  /// Characteristic UUID for user ID exchange via GATT.
  /// Central reads peer's user ID and writes its own user ID to this
  /// characteristic on the Peripheral's GATT server.
  static final Guid userIdCharacteristicUuid =
      Guid('f2688f1c-0fbd-47aa-a048-df36c8325b67');

  /// String form of service UUID for ble_peripheral advertising.
  static const String serviceUuidString =
      '603c6e94-03b8-429c-b4a9-38d55567523c';

  /// String form of characteristic UUID for ble_peripheral GATT server.
  static const String userIdCharacteristicUuidString =
      'f2688f1c-0fbd-47aa-a048-df36c8325b67';

  /// RSSI threshold to consider a device as "entering" proximity range.
  /// Higher (less negative) = closer. -45 dBm targets ~2 feet / 0.6 meters.
  /// Testing value -- will fine-tune after physical test.
  static const int enterRssiThreshold = -45;

  /// RSSI threshold to consider a device as "exiting" proximity range.
  /// Lower (more negative) = farther away. -55 dBm provides 10 dBm
  /// hysteresis gap to prevent rapid enter/exit oscillation.
  static const int exitRssiThreshold = -55;

  /// Debounce timeout before a device is considered truly exited.
  /// Prevents false exits from momentary signal drops.
  static const Duration debounceTimeout = Duration(seconds: 10);

  /// Interval between scan cycles when using periodic scanning.
  static const Duration scanInterval = Duration(seconds: 5);

  /// Duration of each scan cycle before stopping and restarting.
  static const Duration scanTimeout = Duration(seconds: 30);

  /// Maximum time to wait for a GATT connection to complete.
  static const Duration connectionTimeout = Duration(seconds: 5);

  /// Maximum time to wait for service discovery after connecting.
  static const int serviceDiscoveryTimeoutSeconds = 5;
}
