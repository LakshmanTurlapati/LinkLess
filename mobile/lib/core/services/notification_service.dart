import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications for system-level
/// recording notifications ("LinkLess is cooking").
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'linkless_recording';
  static const _notificationId = 42;

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
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
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    final title = initials != null ? 'Linking with $initials' : 'Linking...';
    await _plugin.show(
      id: _notificationId,
      title: title,
      notificationDetails: const NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> dismissRecordingNotification() async {
    await _plugin.cancel(id: _notificationId);
  }
}
