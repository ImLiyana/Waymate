
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'location_service.dart';

enum AlertType { sos, medical, lowBattery }

class SosService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();

  /// Finds the closest OTHER group member to the given position.
  /// Returns their uid and phone number, or null if no one else is
  /// sharing location in this group.
  Future<Map<String, dynamic>?> _findNearestMember({
    required String groupId,
    required String excludeUid,
    required double lat,
    required double lng,
  }) async {
    final snapshot = await _firestore
        .collection('locations')
        .where('groupId', isEqualTo: groupId)
        .get();

    String? nearestUid;
    double nearestDistance = double.infinity;

    for (final doc in snapshot.docs) {
      if (doc.id == excludeUid) continue;
      final data = doc.data();
      final otherLat = data['lat'] as double?;
      final otherLng = data['lng'] as double?;
      if (otherLat == null || otherLng == null) continue;

      final distance = _locationService.distanceBetween(lat, lng, otherLat, otherLng);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestUid = doc.id;
      }
    }

    if (nearestUid == null) return null;

    final userDoc = await _firestore.collection('users').doc(nearestUid).get();
    if (!userDoc.exists) return null;

    return {
      'uid': nearestUid,
      'name': userDoc.data()?['name'] ?? 'A group member',
      'phone': userDoc.data()?['phone'],
      'distanceMeters': nearestDistance,
    };
  }

  Future<String?> _getGuidePhone(String groupId) async {
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return null;
    final guideId = groupDoc.data()?['guideId'];
    if (guideId == null) return null;
    final guideDoc = await _firestore.collection('users').doc(guideId).get();
    return guideDoc.data()?['phone'];
  }

  Future<void> _openSmsComposer(List<String> numbers, String message) async {
    if (numbers.isEmpty) return;
    final uri = Uri(scheme: 'sms', path: numbers.join(','), queryParameters: {'body': message});
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  /// Full SOS: alerts guide, emergency contact, AND the nearest group
  /// member — since whoever's physically closest may reach the person
  /// faster than a guide who could be much further away.
  Future<String> triggerSos({
    required String uid,
    required String touristName,
    required String? groupId,
    required Position position,
    String? emergencyContactPhone,
  }) async {
    final alertRef = await _firestore.collection('sos_alerts').add({
      'uid': uid,
      'groupId': groupId,
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'active',
      'type': 'sos',
    });

    final mapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    final message = 'WAYMATE SOS ALERT: $touristName needs help. Location: $mapsLink';

    final numbers = <String>[];
    if (groupId != null) {
      final guidePhone = await _getGuidePhone(groupId);
      if (guidePhone != null && guidePhone.isNotEmpty) numbers.add(guidePhone);

      final nearest = await _findNearestMember(
        groupId: groupId, excludeUid: uid, lat: position.latitude, lng: position.longitude,
      );
      if (nearest != null && nearest['phone'] != null) {
        numbers.add(nearest['phone']);
        // Also write a targeted alert so the nearest member's app
        // shows this even if they aren't the guide.
        await _firestore.collection('sos_alerts').doc(alertRef.id).update({
          'nearestMemberUid': nearest['uid'],
        });
      }
    }
    if (emergencyContactPhone != null && emergencyContactPhone.isNotEmpty) {
      numbers.add(emergencyContactPhone);
    }

    await _openSmsComposer(numbers, message);
    return alertRef.id;
  }

  /// Medical Aid — lighter urgency, different message tone, alerts
  /// guide + nearest member (not the emergency contact, to avoid
  /// alarming family over something that may be minor).
  Future<String> triggerMedicalAid({
    required String uid,
    required String touristName,
    required String? groupId,
    required Position position,
  }) async {
    final alertRef = await _firestore.collection('sos_alerts').add({
      'uid': uid,
      'groupId': groupId,
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'active',
      'type': 'medical',
    });

    final mapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    final message = 'WAYMATE: $touristName may need medical assistance. Location: $mapsLink';

    final numbers = <String>[];
    if (groupId != null) {
      final guidePhone = await _getGuidePhone(groupId);
      if (guidePhone != null && guidePhone.isNotEmpty) numbers.add(guidePhone);

      final nearest = await _findNearestMember(
        groupId: groupId, excludeUid: uid, lat: position.latitude, lng: position.longitude,
      );
      if (nearest != null && nearest['phone'] != null) numbers.add(nearest['phone']);
    }

    await _openSmsComposer(numbers, message);
    return alertRef.id;
  }

  /// Low battery — sends the last known location as a heads-up,
  /// distinct type so the guide's UI can show it differently.
  Future<void> sendLowBatteryAlert({
    required String uid,
    required String touristName,
    required String? groupId,
    required Position position,
  }) async {
    await _firestore.collection('sos_alerts').add({
      'uid': uid,
      'groupId': groupId,
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'active',
      'type': 'lowBattery',
    });

    if (groupId != null) {
      final guidePhone = await _getGuidePhone(groupId);
      if (guidePhone != null && guidePhone.isNotEmpty) {
        final mapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
        await _openSmsComposer(
          [guidePhone],
          'WAYMATE: $touristName\'s phone battery is low. Last known location: $mapsLink',
        );
      }
    }
  }

  Future<void> resolveAlert(String alertId) async {
    await _firestore.collection('sos_alerts').doc(alertId).update({'status': 'resolved'});
  }
}