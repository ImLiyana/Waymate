import 'dart:async';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase_options.dart';

const _channelId = 'waymate_tracking_channel';
const _notificationId = 888;

/// Sets up (but does not start) the Android foreground service that
/// keeps pushing this device's location to Firestore even while
/// WayMate is minimized or the screen is off. Without this, Android's
/// Doze mode and battery optimization throttle/kill plain background
/// location listeners within minutes — a persistent foreground
/// notification is what tells the OS "keep this alive."
///
/// Call this once, early in main(), before runApp().
Future<void> setupBackgroundLocationService() async {
  final service = FlutterBackgroundService();

  const channel = AndroidNotificationChannel(
    _channelId,
    'WayMate Location Sharing',
    description: 'Shows while WayMate is sharing your live location with your group.',
    importance: Importance.low,
  );

  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _channelId,
      initialNotificationTitle: 'WayMate',
      initialNotificationContent: 'Sharing your live location with your group',
      foregroundServiceNotificationId: _notificationId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

/// Starts the foreground service. Call once the user is logged in and
/// their profile (role/groupId) is known — e.g. right after the
/// profile stream in home_screen.dart delivers its first non-null
/// value, guarded so it's only started once per session.
void startBackgroundLocationService() {
  FlutterBackgroundService().startService();
}

/// Stops the foreground service. Call on logout — otherwise a signed-
/// out device would keep silently sharing a location tied to no one.
void stopBackgroundLocationService() {
  FlutterBackgroundService().invoke('stopService');
}

@pragma('vm:entry-point')
void _onBackgroundStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // This runs in its OWN isolate, separate from the app's main
  // isolate — Firebase must be initialized here too, exactly as
  // main.dart does, or every Firestore call below fails silently
  // against no configured app.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  final battery = Battery();
  bool lowBatteryAlertSent = false;

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    service.stopSelf();
    return;
  }

  String role = 'tourist';
  String? groupId;

  // Keep role/groupId in sync live — if the guide transfers their
  // role, or a tourist is removed/joins a new group while the app is
  // backgrounded, the next location push should reflect that instead
  // of writing stale values for the rest of the session.
  //
  // IMPORTANT: groupId starts out unknown (null). The Firestore read
  // above is async, but the GPS position stream below fires
  // independently and can emit its first fix before that first
  // snapshot arrives — especially since GPS is often already warmed
  // up from the foreground screen. If a location write happened
  // before we knew the real groupId, it would overwrite the
  // locations/{uid} doc with groupId: null, silently dropping that
  // user out of the guide's `where('groupId', isEqualTo: ...)` query
  // — the marker just vanishes with no error anywhere. So: wait for
  // the first real profile snapshot (bounded by a timeout so a rules/
  // network problem can't hang the service forever) before starting
  // to push locations at all.
  final profileReady = Completer<void>();
  final userSub = firestore.collection('users').doc(uid).snapshots().listen((doc) {
    final data = doc.data();
    if (data != null) {
      role = data['role'] as String? ?? 'tourist';
      groupId = data['groupId'] as String?;
    }
    if (!profileReady.isCompleted) profileReady.complete();
  });

  await profileReady.future.timeout(const Duration(seconds: 10), onTimeout: () {});

  final positionSub = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
  ).listen((position) async {
    int batteryLevel = -1;
    try {
      batteryLevel = await battery.batteryLevel;
    } catch (_) {}

    try {
      await firestore.collection('locations').doc(uid).set({
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'groupId': groupId,
        'role': role,
        'batteryLevel': batteryLevel,
      }, SetOptions(merge: true));
    } catch (_) {
      // No UI to surface an error to from here — just let the next
      // position update retry the write.
    }

    // Same low-battery alert as the foreground path (sos_service.dart),
    // minus the SMS composer step — launching a UI intent from a
    // headless background service isn't reliable, so that part stays
    // foreground-only. The Firestore alert doc itself still gets
    // written here, which is what actually drives the guide's
    // real-time alert banner.
    if (role == 'tourist' && batteryLevel >= 0 && batteryLevel <= 15 && !lowBatteryAlertSent) {
      lowBatteryAlertSent = true;
      try {
        await firestore.collection('sos_alerts').add({
          'uid': uid,
          'groupId': groupId,
          'lat': position.latitude,
          'lng': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'active',
          'type': 'lowBattery',
        });
      } catch (_) {}
    } else if (batteryLevel > 15) {
      lowBatteryAlertSent = false;
    }

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'WayMate',
        content: 'Sharing your live location with your group',
      );
    }
  });

  service.on('stopService').listen((event) async {
    await positionSub.cancel();
    await userSub.cancel();
    service.stopSelf();
  });
}