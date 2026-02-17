import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/ble/proximity_state_machine.dart';
import 'package:linkless/core/services/notification_service.dart';

class ProximityNotificationHandler {
  StreamSubscription<ProximityEvent>? _subscription;

  Future<void> initialize() async {
    _subscription = BleManager.instance.proximityStateStream.listen((event) {
      if (event.type == ProximityEventType.detected) {
        _showProximityNotification(event.peerId);
      }
    });
    debugPrint('[ProximityNotificationHandler] Initialized');
  }

  Future<void> _showProximityNotification(String peerId) async {
    await NotificationService.instance.showProximityDetectedNotification();
    debugPrint('[ProximityNotificationHandler] Notification shown for $peerId');
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
