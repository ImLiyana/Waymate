import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Live stream of messages for a group, newest last.
  Stream<QuerySnapshot> messagesStream(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> sendMessage({
    required String groupId,
    required String senderUid,
    required String senderName,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    await _firestore.collection('groups').doc(groupId).collection('messages').add({
      'senderUid': senderUid,
      'senderName': senderName,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}