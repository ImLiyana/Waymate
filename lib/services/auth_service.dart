import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'background_location_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register a new user with email/password, then save their profile
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role,
    String? emergencyContactPhone,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;

    final newUser = AppUser(
      uid: uid,
      name: name,
      phone: phone,
      role: role,
      emergencyContactPhone: emergencyContactPhone,
    );

    await _firestore.collection('users').doc(uid).set(newUser.toMap());
    return newUser;
  }

  // Log in an existing user
  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Fetch a user's profile from Firestore
  Future<AppUser?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(uid, doc.data()!);
  }

  /// Live version of [getUserProfile].
  Stream<AppUser?> userProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromMap(uid, doc.data()!);
    });
  }

  /// Logout: stops the background service, keeps the last known
  /// location on the map (only flags it offline), then signs out.
  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;

    // Stop the service first so it can't overwrite the offline flag.
    stopBackgroundLocationService();
    await Future.delayed(const Duration(milliseconds: 400));

    if (uid != null) {
      try {
        await _firestore.collection('locations').doc(uid).update({
          'online': false,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // No location doc yet, or a network hiccup. Not fatal.
      }
    }

    await _auth.signOut();
  }
}