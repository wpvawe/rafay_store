import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

enum AuthStatus { unknown, unauthenticated, pendingApproval, authenticated }

/// Manages authentication state and the current [UserModel].
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthService? authService,
    FirestoreService? firestoreService,
  })  : _authService = authService ?? AuthService(),
        _db = firestoreService ?? FirestoreService() {
    _init();
  }

  final AuthService _authService;
  final FirestoreService _db;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _currentUser;
  String? _error;
  bool _isBusy = false;
  StreamSubscription? _userDocSubscription;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get error => _error;
  bool get isBusy => _isBusy;

  bool get canEdit => _currentUser?.canWrite ?? false;

  void _init() {
    _authService.authStateChanges.listen(_onAuthStateChanged);

    // Give Firebase Auth + Firestore enough time to restore the session.
    // Previously this was 5 s which fired BEFORE the 3rd Firestore retry
    // (total retry window = 0.8 + 1.6 + 3.0 + 5.0 + 8.0 = 18.4 s).
    // We now wait 30 s so every retry completes before we give up.
    Future.delayed(const Duration(seconds: 30), () {
      if (_status == AuthStatus.unknown) {
        // If Firebase Auth still has a current user the Firestore read is
        // just being slow — don't sign the user out yet; extend 20 more s.
        if (_authService.currentUser != null) {
          debugPrint('AuthProvider: Timeout but Firebase user exists — extending 20 s');
          Future.delayed(const Duration(seconds: 20), () {
            if (_status == AuthStatus.unknown) {
              debugPrint('AuthProvider: Extended timeout — forcing unauthenticated');
              _status = AuthStatus.unauthenticated;
              notifyListeners();
            }
          });
          return;
        }
        debugPrint('AuthProvider: Timeout — forcing unauthenticated');
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });
  }

  void _onAuthStateChanged(User? firebaseUser) async {
    await _userDocSubscription?.cancel();
    _userDocSubscription = null;

    if (firebaseUser == null) {
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _startWatchingUser(firebaseUser.uid, retryCount: 0);
  }

  /// Watches the Firestore user document and retries up to [maxRetries] times
  /// on permission-denied errors (which can occur on first open before
  /// Firestore security rules have fully evaluated the auth token).
  void _startWatchingUser(String uid, {required int retryCount}) {
    const maxRetries = 5;
    const retryDelays = [
      Duration(milliseconds: 800),
      Duration(milliseconds: 1600),
      Duration(milliseconds: 3000),
      Duration(milliseconds: 5000),
      Duration(milliseconds: 8000),
    ];

    _userDocSubscription = _db.watchUser(uid).listen(
      (userModel) {
        if (userModel == null) {
          _status = AuthStatus.pendingApproval;
          _currentUser = null;
        } else if (!userModel.isApproved) {
          _status = AuthStatus.pendingApproval;
          _currentUser = userModel;
        } else {
          _status = AuthStatus.authenticated;
          _currentUser = userModel;
        }
        notifyListeners();
      },
      onError: (error) {
        final msg = error.toString();
        final isPermissionDenied =
            msg.contains('permission-denied') ||
            msg.contains('PERMISSION_DENIED') ||
            msg.contains('Missing or insufficient permissions');

        if (isPermissionDenied && retryCount < maxRetries) {
          // Cancel current subscription and retry after a short delay.
          // This handles the race condition on first app open where the
          // Firebase auth token has not yet propagated to Firestore rules.
          debugPrint(
            'AuthProvider: Permission denied — retrying '
            '(attempt ${retryCount + 1}/$maxRetries)',
          );
          _userDocSubscription?.cancel();
          _userDocSubscription = null;

          final delay = retryDelays[retryCount];
          Future.delayed(delay, () {
            _startWatchingUser(uid, retryCount: retryCount + 1);
          });
        } else {
          debugPrint('AuthProvider: Firestore watchUser error: $error');
          _status = AuthStatus.unauthenticated;
          _currentUser = null;
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _setBusy(true);
    _clearError();
    try {
      await _authService.signIn(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    _setBusy(true);
    _clearError();
    try {
      await _authService.signUp(name: name, email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signInWithGoogle() async {
    _setBusy(true);
    _clearError();
    try {
      await _authService.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cancelled')) {
        _error = null;
      } else {
        _error = 'Google sign-in failed. Please try again.';
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> resetPassword(String email) async {
    _setBusy(true);
    _clearError();
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to send reset email.';
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  void clearError() => _clearError();

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
