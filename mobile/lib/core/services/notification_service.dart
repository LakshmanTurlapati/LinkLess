import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications for system-level
/// recording notifications ("LinkLess is cooking").
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'linkless_recording';
  static const _notificationId = 42;

  static const _scanActiveNotificationId = 100;
  static const _scanActiveChannelId = 'linkless_scanning';
  static const _proximityDetectedNotificationId = 101;
  static const _proximityDetectedChannelId = 'linkless_proximity';

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
  }

  Future<void> showRecordingNotification({String? initials}) async {
    const android = AndroidNotificationDetails(
      _channelId,
      'LinkLess Recording',
      channelDescription: 'Shown when LinkLess is recording a conversation',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );

    final isUpdate = initials != null;
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: !isUpdate,
      presentBadge: false,
    );

    final title = isUpdate ? 'Linking with $initials' : 'Linking...';
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: 'Recording in progress…',
      notificationDetails: NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> dismissRecordingNotification() async {
    await _plugin.cancel(id: _notificationId);
  }

  Future<void> showScanActiveNotification() async {
    const android = AndroidNotificationDetails(
      _scanActiveChannelId,
      'LinkLess Scanning',
      channelDescription: 'Shown when LinkLess is scanning in the background',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
      presentBadge: false,
    );
    await _plugin.show(
      id: _scanActiveNotificationId,
      title: 'LinkLess Active',
      body: 'Detecting nearby users in the background',
      notificationDetails: const NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> dismissScanActiveNotification() async {
    await _plugin.cancel(id: _scanActiveNotificationId);
  }

  Future<void> showProximityDetectedNotification({String? peerInitials}) async {
    const android = AndroidNotificationDetails(
      _proximityDetectedChannelId,
      'LinkLess Proximity',
      channelDescription: 'Shown when a nearby user is detected',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    final title =
        peerInitials != null ? '$peerInitials is nearby!' : 'Someone nearby!';
    await _plugin.show(
      id: _proximityDetectedNotificationId,
      title: title,
      body: 'Open LinkLess to connect',
      notificationDetails: const NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> dismissProximityDetectedNotification() async {
    await _plugin.cancel(id: _proximityDetectedNotificationId);
  }
}
