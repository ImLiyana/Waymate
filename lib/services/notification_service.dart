import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings: settings);
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