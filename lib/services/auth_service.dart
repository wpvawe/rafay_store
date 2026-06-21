import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/constants.dart';
import '../models/user_model.dart';
import 'firestore_service.dart';

/// Handles Firebase Authentication operations.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirestoreService? firestoreService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestoreService ?? FirestoreService();

  final FirebaseAuth _auth;
  final FirestoreService _db;

  // Web client ID from google-services.json (client_type: 3).
  // Required by google_sign_in v6.x to obtain an idToken that
  // Firebase can verify. Without this, idToken is null on Android
  // and signInWithCredential throws "sign-in failed".
  static const _googleWebClientId =
      '761475352831-mugl9t9hvsnhbf58vjvum277sgqndcrd.apps.googleusercontent.com';

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Sign in with email and password.
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user!.uid;
    final userModel = await _db.getUser(uid);
    if (userModel == null) throw Exception('User record not found.');
    return userModel;
  }

  /// Register a new user. Saves the user in Firestore with pending status.
  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;

    // Update display name in Firebase Auth
    await user.updateDisplayName(name.trim());

    final newUser = UserModel(
      uid: user.uid,
      name: name.trim(),
      email: email.trim().toLowerCase(),
      role: AppConstants.roleViewer,
      status: AppConstants.statusPending,
      createdAt: DateTime.now(),
    );

    await _db.createUser(newUser);
    return newUser;
  }

  /// Sign in with Google. Creates a Firestore record if new user (pending status).
  Future<UserModel> signInWithGoogle() async {
    // serverClientId is required in google_sign_in v6.x to receive an idToken.
    // Without it the idToken is null on Android and Firebase rejects the credential.
    final googleSignIn = GoogleSignIn(serverClientId: _googleWebClientId);

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled.');

    final googleAuth = await googleUser.authentication;

    // Guard: if both tokens are null Firebase will throw an obscure error.
    if (googleAuth.idToken == null && googleAuth.accessToken == null) {
      throw Exception(
        'Google authentication tokens unavailable.\n'
        'Make sure your app SHA-1 fingerprint is registered in '
        'Firebase Console → Project Settings → Android app.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user!;

    // Check if Firestore record exists
    UserModel? existing = await _db.getUser(firebaseUser.uid);
    if (existing != null) return existing;

    // New user — create with pending status (requires admin approval)
    final newUser = UserModel(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName ?? googleUser.displayName ?? 'User',
      email: firebaseUser.email ?? googleUser.email,
      role: AppConstants.roleViewer,
      status: AppConstants.statusPending,
      createdAt: DateTime.now(),
    );
    await _db.createUser(newUser);
    return newUser;
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await GoogleSignIn(serverClientId: _googleWebClientId).signOut();
    await _auth.signOut();
  }
}
