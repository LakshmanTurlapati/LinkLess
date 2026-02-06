import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// BLE Service UUID for LinkLess proximity detection.
/// All LinkLess devices advertise this service so they can discover each other.
const String kLinkLessServiceUuid = '0000FACE-0000-1000-8000-00805F9B34FB';

/// Characteristic UUID for exchanging user identity.
const String kUserIdentityCharUuid = '0000FACE-0001-1000-8000-00805F9B34FB';

/// RSSI threshold for "in proximity" — roughly within 2-3 meters.
const int kProximityRssiThreshold = -65;

/// Minimum time (seconds) a peer must stay in proximity before triggering.
const int kProximityMinDurationSeconds = 5;

/// Represents a nearby LinkLess user detected via BLE.
class NearbyPeer {
  final String deviceId;
  final String? userId;
  final String? displayName;
  final int rssi;
  final double estimatedDistance;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool isInProximity;

  const NearbyPeer({
    required this.deviceId,
    this.userId,
    this.displayName,
    required this.rssi,
    required this.estimatedDistance,
    required this.firstSeen,
    required this.lastSeen,
    this.isInProximity = false,
  });

  NearbyPeer copyWith({
    String? userId,
    String? displayName,
    int? rssi,
    double? estimatedDistance,
    DateTime? lastSeen,
    bool? isInProximity,
  }) {
    return NearbyPeer(
      deviceId: deviceId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      rssi: rssi ?? this.rssi,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      firstSeen: firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      isInProximity: isInProximity ?? this.isInProximity,
    );
  }

  Duration get proximityDuration => lastSeen.difference(firstSeen);
}

/// State for the BLE proximity service.
class BleProximityState {
  final bool isScanning;
  final bool isAdvertising;
  final Map<String, NearbyPeer> nearbyPeers;
  final String? error;

  const BleProximityState({
    this.isScanning = false,
    this.isAdvertising = false,
    this.nearbyPeers = const {},
    this.error,
  });

  BleProximityState copyWith({
    bool? isScanning,
    bool? isAdvertising,
    Map<String, NearbyPeer>? nearbyPeers,
    String? error,
  }) {
    return BleProximityState(
      isScanning: isScanning ?? this.isScanning,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      nearbyPeers: nearbyPeers ?? this.nearbyPeers,
      error: error,
    );
  }

  List<NearbyPeer> get proximityPeers =>
      nearbyPeers.values.where((p) => p.isInProximity).toList();
}

/// Core BLE proximity detection service.
///
/// Scans for other LinkLess devices using BLE, estimates distance via RSSI,
/// and emits events when two users are close enough to trigger transcription.
class BleProximityService extends StateNotifier<BleProximityState> {
  final String _currentUserId;
  final String _currentDisplayName;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _cleanupTimer;
  Timer? _proximityCheckTimer;

  /// Stream controller for proximity trigger events.
  final _proximityTriggerController =
      StreamController<NearbyPeer>.broadcast();

  /// Stream controller for proximity lost events.
  final _proximityLostController = StreamController<NearbyPeer>.broadcast();

  /// Fires when a peer enters close proximity for long enough.
  Stream<NearbyPeer> get onProximityTriggered =>
      _proximityTriggerController.stream;

  /// Fires when a previously-proximate peer moves away.
  Stream<NearbyPeer> get onProximityLost => _proximityLostController.stream;

  BleProximityService({
    required String currentUserId,
    required String currentDisplayName,
  })  : _currentUserId = currentUserId,
        _currentDisplayName = currentDisplayName,
        super(const BleProximityState());

  /// Start scanning for nearby LinkLess devices and advertising our presence.
  Future<void> startProximityDetection() async {
    try {
      // Check if Bluetooth is available and on
      if (await FlutterBluePlus.isSupported == false) {
        state = state.copyWith(error: 'Bluetooth is not supported on this device');
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        state = state.copyWith(error: 'Please turn on Bluetooth');
        return;
      }

      await _startScanning();
      _startCleanupTimer();
      _startProximityCheckTimer();
    } catch (e) {
      state = state.copyWith(error: 'Failed to start proximity detection: $e');
    }
  }

  /// Stop all BLE scanning and advertising.
  Future<void> stopProximityDetection() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _cleanupTimer?.cancel();
    _proximityCheckTimer?.cancel();
    state = state.copyWith(
      isScanning: false,
      isAdvertising: false,
      nearbyPeers: {},
    );
  }

  Future<void> _startScanning() async {
    // Scan for devices advertising the LinkLess service UUID
    await FlutterBluePlus.startScan(
      withServices: [Guid(kLinkLessServiceUuid)],
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );

    state = state.copyWith(isScanning: true);

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        final updatedPeers = Map<String, NearbyPeer>.from(state.nearbyPeers);

        for (final result in results) {
          final deviceId = result.device.remoteId.str;
          final rssi = result.rssi;
          final distance = _estimateDistance(rssi);
          final isClose = rssi >= kProximityRssiThreshold;

          // Try to extract user identity from advertisement data
          String? userId;
          String? displayName;
          final serviceData = result.advertisementData.serviceData;
          if (serviceData.isNotEmpty) {
            try {
              final data = serviceData.values.first;
              final decoded = utf8.decode(data);
              final parts = decoded.split('|');
              if (parts.length >= 2) {
                userId = parts[0];
                displayName = parts[1];
              }
            } catch (_) {}
          }

          if (updatedPeers.containsKey(deviceId)) {
            updatedPeers[deviceId] = updatedPeers[deviceId]!.copyWith(
              userId: userId,
              displayName: displayName,
              rssi: rssi,
              estimatedDistance: distance,
              lastSeen: DateTime.now(),
              isInProximity: isClose,
            );
          } else {
            updatedPeers[deviceId] = NearbyPeer(
              deviceId: deviceId,
              userId: userId,
              displayName: displayName,
              rssi: rssi,
              estimatedDistance: distance,
              firstSeen: DateTime.now(),
              lastSeen: DateTime.now(),
              isInProximity: isClose,
            );
          }
        }

        state = state.copyWith(nearbyPeers: updatedPeers);
      },
      onError: (error) {
        state = state.copyWith(error: 'Scan error: $error');
      },
    );
  }

  /// Periodically check if any peer has been in proximity long enough
  /// to trigger a conversation recording.
  void _startProximityCheckTimer() {
    _proximityCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        for (final peer in state.nearbyPeers.values) {
          if (peer.isInProximity &&
              peer.proximityDuration.inSeconds >= kProximityMinDurationSeconds) {
            _proximityTriggerController.add(peer);
          }
        }
      },
    );
  }

  /// Clean up stale peers that haven't been seen recently.
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        final now = DateTime.now();
        final updatedPeers = Map<String, NearbyPeer>.from(state.nearbyPeers);
        final removedPeers = <NearbyPeer>[];

        updatedPeers.removeWhere((key, peer) {
          final stale = now.difference(peer.lastSeen).inSeconds > 30;
          if (stale && peer.isInProximity) {
            removedPeers.add(peer);
          }
          return stale;
        });

        for (final peer in removedPeers) {
          _proximityLostController.add(peer);
        }

        state = state.copyWith(nearbyPeers: updatedPeers);
      },
    );
  }

  /// Estimate distance in meters from RSSI value using the log-distance path
  /// loss model. This is an approximation — actual distance depends on
  /// environment, obstacles, device antenna characteristics, etc.
  double _estimateDistance(int rssi) {
    // Measured power at 1 meter (typical for BLE)
    const int txPower = -59;
    // Path loss exponent (2.0 = free space, 2.7-3.5 = indoor)
    const double n = 2.5;

    if (rssi == 0) return -1.0;

    final ratio = (txPower - rssi) / (10 * n);
    return double.parse(
      (pow10(ratio)).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    stopProximityDetection();
    _proximityTriggerController.close();
    _proximityLostController.close();
    super.dispose();
  }
}

double pow10(double exponent) {
  return _pow(10.0, exponent);
}

double _pow(double base, double exponent) {
  // Simple power function using dart:math would be imported in real code
  double result = 1.0;
  int intPart = exponent.floor();
  double fracPart = exponent - intPart;

  for (int i = 0; i < intPart; i++) {
    result *= base;
  }

  // Approximate fractional part using natural log
  if (fracPart > 0) {
    // Using Taylor series approximation for small fractional exponents
    double ln10 = 2.302585;
    double x = fracPart * ln10;
    double term = 1.0;
    double sum = 1.0;
    for (int i = 1; i <= 10; i++) {
      term *= x / i;
      sum += term;
    }
    result *= sum;
  }

  return result;
}

/// Provider for the BLE proximity service.
final bleProximityServiceProvider =
    StateNotifierProvider<BleProximityService, BleProximityState>((ref) {
  // These will be injected with actual user data after authentication
  return BleProximityService(
    currentUserId: '',
    currentDisplayName: '',
  );
});
