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

  /// Requests location permission in the two steps Android requires:
  /// foreground ("while using the app") first, then — only once that's
  /// granted — background ("Allow all the time") as a SEPARATE prompt.
  /// Android 11+ refuses to show both in one combined dialog; asking
  /// for background before foreground is granted just fails silently.
  ///
  /// Returns true as long as foreground access was granted, even if
  /// the user declines the background upgrade — the app still works
  /// while open either way, background tracking just won't survive
  /// minimizing the app without it.
  Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    // Foreground is granted at this point. Now ask for the background
    // upgrade as its own, later call. On some Android versions/OEMs
    // this shows the "Allow all the time" option directly; on others
    // it has no effect and the user must grant it manually from
    // Settings — either way, this attempt doesn't block foreground use.
    if (permission == LocationPermission.whileInUse) {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
    }

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
    }, SetOptions(merge: true));
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
  Future<List<Map<String, dynamic>>> findNearbyHospitals(
    double lat, double lng) async {
      print('🚨 OVERPASS FUNCTION CALLED: $lat, $lng');
  final query = '''
[out:json][timeout:30];
(
  node["amenity"="hospital"](around:20000,$lat,$lng);
  way["amenity"="hospital"](around:20000,$lat,$lng);
  relation["amenity"="hospital"](around:20000,$lat,$lng);
);
out center;
''';

  try {
    print('OVERPASS SEARCH: $lat, $lng');

    final response = await http
        .post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          body: {'data': query},
        )
        .timeout(const Duration(seconds: 35));

    print('OVERPASS STATUS: ${response.statusCode}');
    print('OVERPASS RESPONSE LENGTH: ${response.body.length}');

    if (response.statusCode != 200) {
      print('OVERPASS ERROR: ${response.body}');
      return [];
    }

    final data = jsonDecode(response.body);
    final elements = data['elements'] as List? ?? [];

    print('OVERPASS ELEMENTS: ${elements.length}');

    final hospitals = <Map<String, dynamic>>[];

    for (final el in elements) {
      final tags = el['tags'] as Map<String, dynamic>?;

      final name = tags?['name']?.toString() ?? 'Unnamed hospital';

      double? hLat;
      double? hLng;

      // Node
      if (el['lat'] is num && el['lon'] is num) {
        hLat = (el['lat'] as num).toDouble();
        hLng = (el['lon'] as num).toDouble();
      }

      // Way / relation
      if ((hLat == null || hLng == null) && el['center'] != null) {
        final center = el['center'];

        if (center['lat'] is num && center['lon'] is num) {
          hLat = (center['lat'] as num).toDouble();
          hLng = (center['lon'] as num).toDouble();
        }
      }

      if (hLat == null || hLng == null) continue;

      final distanceMeters = distanceBetween(
        lat,
        lng,
        hLat,
        hLng,
      );

      hospitals.add({
        'name': name,
        'distanceMeters': distanceMeters,
        'lat': hLat,
        'lng': hLng,
      });
    }

    hospitals.sort(
      (a, b) => (a['distanceMeters'] as double)
          .compareTo(b['distanceMeters'] as double),
    );

    print('HOSPITALS FOUND: ${hospitals.length}');

    return hospitals.take(5).toList();
  } catch (e) {
    print('OVERPASS EXCEPTION: $e');
    return [];
  }
}}