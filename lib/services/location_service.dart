
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:battery_plus/battery_plus.dart';

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Battery _battery = Battery();

  /// Meters beyond which a tourist is considered "straying too far"
  /// from their guide.
  static const double geofenceRadiusMeters = 500;

  /// Battery percentage below which a low-battery alert fires.
  static const int lowBatteryThreshold = 15;

  bool _lowBatteryAlertSent = false;

  Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<Position> getCurrentPosition() async {
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Stream<Position> get positionStream {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    );
  }

  /// Reliable on-device address lookup — uses the phone's own
  /// geocoding service (same one Google Maps uses), not a flaky
  /// public web API. Android/iOS only, not web.
  Future<String> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return 'Address unavailable';
      final p = placemarks.first;
      final parts = [p.street, p.subLocality, p.locality].where((s) => s != null && s.isNotEmpty);
      return parts.isNotEmpty ? parts.join(', ') : 'Address unavailable';
    } catch (_) {
      return 'Address unavailable';
    }
  }

  /// Pushes location + current battery level to Firestore.
  Future<void> pushLocation({
    required String uid,
    required String? groupId,
    required String role,
    required Position position,
  }) async {
    int batteryLevel = -1;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    await _firestore.collection('locations').doc(uid).set({
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'groupId': groupId,
      'role': role,
      'batteryLevel': batteryLevel,
    });
  }

  /// Straight-line distance in meters between two points.
  double distanceBetween(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Live stream of every location document in a group.
  Stream<QuerySnapshot> groupLocationsStream(String groupId) {
    return _firestore.collection('locations').where('groupId', isEqualTo: groupId).snapshots();
  }

  /// Finds the guide's current position within a group's location docs,
  /// used both for the geofence check and for tourist-side map markers.
  Map<String, dynamic>? findGuideLocation(List<QueryDocumentSnapshot> docs) {
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['role'] == 'guide') return data;
    }
    return null;
  }

  /// Checks if a tourist has strayed beyond the geofence radius from
  /// their guide. Returns true if a warning should be shown/sent.
  bool isStrayingTooFar({
    required double touristLat,
    required double touristLng,
    required double guideLat,
    required double guideLng,
  }) {
    final distance = distanceBetween(touristLat, touristLng, guideLat, guideLng);
    return distance > geofenceRadiusMeters;
  }

  /// Checks current battery level; returns true (once) the moment it
  /// crosses below the low-battery threshold, so callers can trigger
  /// a one-time alert rather than repeating it every check.
  Future<bool> checkLowBatteryOnce() async {
    try {
      final level = await _battery.batteryLevel;
      if (level <= lowBatteryThreshold && !_lowBatteryAlertSent) {
        _lowBatteryAlertSent = true;
        return true;
      }
      if (level > lowBatteryThreshold) {
        _lowBatteryAlertSent = false; // reset if charged back up
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}