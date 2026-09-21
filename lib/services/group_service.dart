import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generates a random 6-character code like "A7F3K9"
  String _generateGroupCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusing chars like O/0, I/1
    final rand = Random();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  // Creates a new group for a guide, returns the generated groupId
  Future<String> createGroupForGuide({
    required String guideId,
    required String groupName,
  }) async {
    final groupId = _generateGroupCode();

    await _firestore.collection('groups').doc(groupId).set({
      'guideId': guideId,
      'groupName': groupName,
      'memberIds': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Also update the guide's own user doc to reference their group
    await _firestore.collection('users').doc(guideId).update({
      'groupId': groupId,
    });

    return groupId;
  }

  // Lets a tourist join an existing group using the code
  Future<bool> joinGroup({required String uid, required String groupCode}) async {
    final groupRef = _firestore.collection('groups').doc(groupCode);
    final groupDoc = await groupRef.get();

    if (!groupDoc.exists) return false; // invalid code

    await groupRef.update({
      'memberIds': FieldValue.arrayUnion([uid]),
    });

    await _firestore.collection('users').doc(uid).update({
      'groupId': groupCode,
    });

    return true;
  }

  // Looks up the guide's uid for a given group — used so a tourist's
  // map can show where their guide currently is.
  Future<String?> getGuideId(String groupId) async {
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return null;
    return groupDoc.data()?['guideId'];
  }

  /// Removes a tourist from the group entirely — clears their groupId
  /// and location doc so they stop appearing on the guide's map.
  Future<void> removeMember({required String groupId, required String memberUid}) async {
    await _firestore.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([memberUid]),
    });
    await _firestore.collection('users').doc(memberUid).update({'groupId': null});
    await _firestore.collection('locations').doc(memberUid).delete();
  }

  /// Transfers guide leadership to another current group member.
  /// The old guide becomes a regular tourist in the same group; the
  /// chosen member becomes the new guide.
  Future<void> transferGuideRole({
    required String groupId,
    required String currentGuideUid,
    required String newGuideUid,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({'guideId': newGuideUid});
    await _firestore.collection('users').doc(newGuideUid).update({'role': 'guide'});
    await _firestore.collection('users').doc(currentGuideUid).update({'role': 'tourist'});

    // Update both their location docs' role field too, so the map/list
    // reflects the change immediately without waiting for their next
    // GPS ping.
    await _firestore.collection('locations').doc(newGuideUid).set({'role': 'guide'}, SetOptions(merge: true));
    await _firestore.collection('locations').doc(currentGuideUid).set({'role': 'tourist'}, SetOptions(merge: true));
  }

  // ===========================================================
  // Destination / meeting-point feature
  // ===========================================================

  /// Sets (or replaces) the group's current destination/meeting point.
  /// Only one destination is active per group at a time — calling this
  /// again simply overwrites whatever was set before, which is exactly
  /// how "unset and set a new one" works: the guide just calls this
  /// again with new details.
  Future<void> setDestination({
    required String groupId,
    required String name,
    required double lat,
    required double lng,
    String? reachByTime,
    String? instructions,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'destination': {
        'name': name,
        'lat': lat,
        'lng': lng,
        'reachByTime': reachByTime,
        'instructions': instructions,
        'setAt': FieldValue.serverTimestamp(),
      },
    });
  }

  /// Clears the current destination entirely (guide "unsets" it with
  /// no replacement).
  Future<void> clearDestination({required String groupId}) async {
    await _firestore.collection('groups').doc(groupId).update({'destination': FieldValue.delete()});
  }

  /// Live stream of the group's current destination, or null if none
  /// is set. Every tourist's home screen listens to this so the
  /// destination banner and map pin update the moment the guide sets,
  /// changes, or clears it.
  Stream<Map<String, dynamic>?> destinationStream(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots().map((doc) {
      final data = doc.data();
      return data?['destination'] as Map<String, dynamic>?;
    });
  }

  // ===========================================================
  // Announcement feature
  // ===========================================================

  /// Broadcasts a short announcement (e.g. "Lunch break at 1pm") that
  /// shows as a banner on every tourist's home screen. Posting a new
  /// one replaces the previous one, same pattern as destinations.
  Future<void> postAnnouncement({required String groupId, required String text}) async {
    await _firestore.collection('groups').doc(groupId).update({
      'announcement': {
        'text': text,
        'postedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  Future<void> clearAnnouncement({required String groupId}) async {
    await _firestore.collection('groups').doc(groupId).update({'announcement': FieldValue.delete()});
  }

  Stream<Map<String, dynamic>?> announcementStream(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots().map((doc) {
      final data = doc.data();
      return data?['announcement'] as Map<String, dynamic>?;
    });
  }

  // ===========================================================
  // End Trip — wipe the group and free everyone to join/start anew
  // ===========================================================

  /// Ends the guide's current trip: removes every tourist from the
  /// group (clearing their groupId and deleting their live location,
  /// exactly like removeMember does one at a time — but for everyone
  /// at once), deletes the group's chat history, and deletes the group
  /// document itself. The guide's own groupId is cleared too, so they
  /// land on a "start a new trip" screen rather than an empty
  /// dashboard pointing at a group that no longer exists.
  ///
  /// Capped at a Firestore batch's 500-operation limit — fine for a
  /// normal trip-sized group, but very large groups with long chat
  /// history could theoretically exceed it (messages are capped at
  /// 400 here to leave room for the member/guide/group operations).
  Future<void> endTrip({required String groupId, required String guideUid}) async {
    final groupRef = _firestore.collection('groups').doc(groupId);
    final groupDoc = await groupRef.get();
    if (!groupDoc.exists) return;

    final memberIds = List<String>.from(groupDoc.data()?['memberIds'] ?? []);
    final batch = _firestore.batch();

    for (final uid in memberIds) {
      batch.update(_firestore.collection('users').doc(uid), {'groupId': null});
      batch.delete(_firestore.collection('locations').doc(uid));
    }

    // The guide themselves also leaves this group.
    batch.update(_firestore.collection('users').doc(guideUid), {'groupId': null});
    batch.delete(_firestore.collection('locations').doc(guideUid));

    final messages = await groupRef.collection('messages').limit(400).get();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(groupRef);

    await batch.commit();
  }
}