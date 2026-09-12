import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInReady = false;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> _ensureGoogleSignInReady() async {
    if (!_googleSignInReady) {
      await _googleSignIn.initialize();
      _googleSignInReady = true;
    }
  }

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

  Future<void> logout() async {
    await _auth.signOut();
  }

  // Sign in with a Google account
  Future<AppUser?> signInWithGoogle() async {
    await _ensureGoogleSignInReady();

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.authenticate();
    } catch (_) {
      return null; // user cancelled or sign-in failed
    }

    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final uid = userCredential.user!.uid;

    final existing = await getUserProfile(uid);
    if (existing != null) return existing;

    final newUser = AppUser(
      uid: uid,
      name: userCredential.user!.displayName ?? '',
      phone: userCredential.user!.phoneNumber ?? '',
      role: 'tourist',
    );
    await _firestore.collection('users').doc(uid).set(newUser.toMap());
    return newUser;
  }
}