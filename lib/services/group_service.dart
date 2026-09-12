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
}