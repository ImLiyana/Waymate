import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Battery _battery = Battery();
  final Geocoding _geocoding = Geocoding();

  static const double geofenceRadiusMeters = 500;
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

  Future<String> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return 'Address unavailable';
      final p = placemarks.first;
      final parts = [p.street, p.subLocality, p.locality].where((s) => s != null && s.isNotEmpty);
      return parts.isNotEmpty ? parts.join(', ') : 'Address unavailable';
    } catch (_) {
      return 'Address unavailable';
    }
  }

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

  double distanceBetween(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  Stream<QuerySnapshot> groupLocationsStream(String groupId) {
    return _firestore.collection('locations').where('groupId', isEqualTo: groupId).snapshots();
  }

  Map<String, dynamic>? findGuideLocation(List<QueryDocumentSnapshot> docs) {
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['role'] == 'guide') return data;
    }
    return null;
  }

  bool isStrayingTooFar({
    required double touristLat,
    required double touristLng,
    required double guideLat,
    required double guideLng,
  }) {
    final distance = distanceBetween(touristLat, touristLng, guideLat, guideLng);
    return distance > geofenceRadiusMeters;
  }

  Future<bool> checkLowBatteryOnce() async {
    try {
      final level = await _battery.batteryLevel;
      if (level <= lowBatteryThreshold && !_lowBatteryAlertSent) {
        _lowBatteryAlertSent = true;
        return true;
      }
      if (level > lowBatteryThreshold) {
        _lowBatteryAlertSent = false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Finds real nearby hospitals using OpenStreetMap's free Overpass
  /// API — actual place data, not an AI guess. Returns name + distance,
  /// sorted nearest first.
  Future<List<Map<String, dynamic>>> findNearbyHospitals(double lat, double lng) async {
    final query = '''
      [out:json][timeout:15];
      (
        node["amenity"="hospital"](around:5000,$lat,$lng);
        way["amenity"="hospital"](around:5000,$lat,$lng);
      );
      out center 8;
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final elements = data['elements'] as List;

      final hospitals = <Map<String, dynamic>>[];
      for (final el in elements) {
        final tags = el['tags'] as Map<String, dynamic>?;
        final name = tags?['name'] as String? ?? 'Unnamed hospital';

        double? hLat = el['lat'] as double?;
        double? hLng = el['lon'] as double?;
        if (hLat == null && el['center'] != null) {
          hLat = el['center']['lat'] as double?;
          hLng = el['center']['lon'] as double?;
        }
        if (hLat == null || hLng == null) continue;

        final distanceMeters = distanceBetween(lat, lng, hLat, hLng);
        hospitals.add({'name': name, 'distanceMeters': distanceMeters});
      }

      hospitals.sort((a, b) => (a['distanceMeters'] as double).compareTo(b['distanceMeters'] as double));
      return hospitals.take(5).toList();
    } catch (_) {
      return [];
    }
  }
}