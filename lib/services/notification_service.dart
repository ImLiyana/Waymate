import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Sets up the notifications plugin only — no permission dialogs.
  /// Safe to call before runApp(), since it does no UI-blocking work.
  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings: settings);
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS runtime permission.
  /// Deliberately kept SEPARATE from init() and must be called AFTER
  /// runApp() — calling it before the first frame renders shows the
  /// system permission dialog over a blank black screen, since Flutter
  /// hasn't drawn anything yet at that point.
  static Future<void> requestPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  static Future<void> showSosAlert({required String touristName}) async {
    const androidDetails = AndroidNotificationDetails(
      'sos_channel',
      'SOS Alerts',
      channelDescription: 'Emergency alerts from tourists in your group',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'SOS Alert!',
      body: '$touristName needs help — tap to view location',
      notificationDetails: details,
    );
  }
}