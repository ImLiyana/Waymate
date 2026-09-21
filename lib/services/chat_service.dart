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

  /// Live stream of the currently-pinned message (if any). Only one
  /// message can be pinned at a time per group — pinning a new one
  /// automatically unpins the previous, so this is always at most 1 doc.
  Stream<QueryDocumentSnapshot?> pinnedMessageStream(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .where('pinned', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : snap.docs.first);
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
      'deleted': false,
      'pinned': false,
    });
  }

  /// "Unsend" — soft-deletes a message so it shows as "This message was
  /// deleted" for everyone, rather than vanishing without a trace. Only
  /// the original sender should be able to call this (enforced in the
  /// UI layer by only showing the option on the sender's own bubbles).
  Future<void> deleteMessage({required String groupId, required String messageId}) async {
    await _firestore.collection('groups').doc(groupId).collection('messages').doc(messageId).update({
      'deleted': true,
      'text': '',
    });
  }

  /// Pins a message, unpinning whatever was previously pinned first so
  /// there's only ever one pinned message per group at a time.
  Future<void> pinMessage({required String groupId, required String messageId}) async {
    final messagesRef = _firestore.collection('groups').doc(groupId).collection('messages');
    final currentlyPinned = await messagesRef.where('pinned', isEqualTo: true).get();
    final batch = _firestore.batch();
    for (final doc in currentlyPinned.docs) {
      batch.update(doc.reference, {'pinned': false});
    }
    batch.update(messagesRef.doc(messageId), {'pinned': true});
    await batch.commit();
  }

  Future<void> unpinMessage({required String groupId, required String messageId}) async {
    await _firestore.collection('groups').doc(groupId).collection('messages').doc(messageId).update({'pinned': false});
  }

  /// Marks the group's chat as "read" up to now for this user. Called
  /// when the user opens (and leaves) the chat screen.
  Future<void> markGroupRead({required String groupId, required String uid}) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('reads')
        .doc(uid)
        .set({'lastRead': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  /// Live count of messages sent by OTHERS after this user's last-read
  /// timestamp — used for the unread badge on the drawer's Chat tile.
  Stream<int> unreadCountStream({required String groupId, required String uid}) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('reads')
        .doc(uid)
        .snapshots()
        .asyncExpand((readDoc) {
      final lastRead = readDoc.data()?['lastRead'] as Timestamp?;
      Query query = _firestore.collection('groups').doc(groupId).collection('messages');
      if (lastRead != null) {
        query = query.where('timestamp', isGreaterThan: lastRead);
      }
      return query.snapshots().map(
            (snap) => snap.docs.where((d) => (d.data() as Map<String, dynamic>)['senderUid'] != uid).length,
          );
    });
  }
}