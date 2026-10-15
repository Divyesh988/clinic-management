import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_models.dart';
import 'doctor_service.dart';

/// Centralized SaaS Authentication & Doctor Identity Service.
/// Integrates Firebase Authentication with Cloud Firestore doctor authorization records.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DoctorAccount? _cachedAccount;

  /// Active Firebase Auth instance
  static FirebaseAuth get auth => _auth;

  /// Current Firebase authenticated User
  static User? get currentUser => _auth.currentUser;

  /// Current validated Doctor Account Profile
  static DoctorAccount? get currentAccount => _cachedAccount;

  /// Stream of Firebase Authentication state changes
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Whether a user is currently signed in to Firebase Auth
  static bool get isAuthenticated => _auth.currentUser != null;

  // ==========================================================================
  // SIGN IN WORKFLOW
  // ==========================================================================

  /// Authenticates doctor using Email and Password via Firebase Authentication.
  /// Verifies account record in Firestore and checks authorization status.
  static Future<DoctorAccount> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw const AuthException('Email and password must not be empty.');
    }

    try {
      // 1. Authenticate with Firebase Authentication
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPassword,
      );

      final user = credential.user;
      if (user == null) {
        throw const AuthException('Authentication failed. No user record returned.');
      }

      // 2. Fetch or provision the Doctor Account record in `doctors/{uid}`
      final account = await _ensureDoctorAccount(user);

      // 3. Verify Account Authorization & SaaS Platform Status
      if (!account.isActive) {
        await _auth.signOut();
        _cachedAccount = null;
        if (account.accountStatus == DoctorAccountStatus.suspended) {
          throw const AuthException(
            'Your doctor account has been suspended. Please contact clinic administration.',
          );
        } else {
          throw const AuthException(
            'Your doctor account is inactive. Please contact administration for authorization.',
          );
        }
      }

      // Check linked SaaS Customer record in `customers/{uid}` for real-time lifecycle status
      try {
        final customerDoc = await _firestore.collection('customers').doc(user.uid).get();
        if (customerDoc.exists && customerDoc.data() != null) {
          final cStatus = customerDoc.data()!['accountStatus']?.toString().toUpperCase();
          if (cStatus == 'SUSPENDED') {
            await _auth.signOut();
            _cachedAccount = null;
            throw const AuthException(
              'Your clinic SaaS subscription account is currently suspended. Please contact administration.',
            );
          }
        }
      } catch (e) {
        if (e is AuthException) rethrow;
      }

      // 4. Initialize Doctor session scope across the app
      _cachedAccount = account;
      DoctorService.switchDoctor(user.uid);

      return account;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error [${e.code}]: ${e.message}');
      throw AuthException(_mapFirebaseAuthError(e));
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('Unexpected Login Error: $e');
      throw AuthException('An unexpected error occurred during sign in: $e');
    }
  }

  // ==========================================================================
  // FORGOT PASSWORD / PASSWORD RESET
  // ==========================================================================

  /// Sends a secure Firebase password reset email to the doctor's verified email.
  static Future<void> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw const AuthException('Please enter a valid email address.');
    }

    try {
      await _auth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      debugPrint('Password Reset Error [${e.code}]: ${e.message}');
      throw AuthException(_mapFirebaseAuthError(e));
    } catch (e) {
      debugPrint('Password reset failed: $e');
      throw const AuthException('Failed to send password reset email. Please try again later.');
    }
  }

  /// Completes mandatory first-login password change for an authenticated doctor.
  /// Updates credentials in Firebase Auth and updates `mustChangePassword: false` in Firestore.
  static Future<void> completeFirstLoginPasswordChange(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No active doctor session. Please sign in again.');
    }

    final trimmed = newPassword.trim();
    if (trimmed.length < 8) {
      throw const AuthException('New password must be at least 8 characters long.');
    }

    try {
      // 1. Update password in Firebase Authentication
      await user.updatePassword(trimmed);

      // 2. Clear mustChangePassword flag in Firestore doctors/{uid}
      await _firestore.collection('doctors').doc(user.uid).set({
        'mustChangePassword': false,
        'initialPasswordChanged': true,
        'passwordChangedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. Update cached account model if available
      if (_cachedAccount != null) {
        _cachedAccount = DoctorAccount(
          uid: _cachedAccount!.uid,
          email: _cachedAccount!.email,
          displayName: _cachedAccount!.displayName,
          specialty: _cachedAccount!.specialty,
          degree: _cachedAccount!.degree,
          phone: _cachedAccount!.phone,
          regNumber: _cachedAccount!.regNumber,
          accountStatus: _cachedAccount!.accountStatus,
          onboardingCompleted: _cachedAccount!.onboardingCompleted,
          mustChangePassword: false,
          distributorUid: _cachedAccount!.distributorUid,
          activePlanId: _cachedAccount!.activePlanId,
          subscriptionStatus: _cachedAccount!.subscriptionStatus,
          createdAt: _cachedAccount!.createdAt,
          updatedAt: DateTime.now(),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('First-login password update error [${e.code}]: ${e.message}');
      if (e.code == 'requires-recent-login') {
        throw const AuthException(
          'For security, your session has expired. Please sign in again before updating your password.',
        );
      }
      throw AuthException(_mapFirebaseAuthError(e));
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('Error completing first-login password change: $e');
      throw AuthException('Failed to update password: $e');
    }
  }

  // ==========================================================================
  // SESSION RESTORATION & LOGOUT
  // ==========================================================================

  /// Verifies active session on app startup and restores doctor profile.
  static Future<DoctorAccount?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      _cachedAccount = null;
      return null;
    }

    try {
      final account = await _ensureDoctorAccount(user);
      if (!account.isActive) {
        await signOut();
        return null;
      }

      // Check if suspended from SaaS admin portal
      try {
        final custDoc = await _firestore.collection('customers').doc(user.uid).get();
        if (custDoc.exists && custDoc.data()?['accountStatus']?.toString().toUpperCase() == 'SUSPENDED') {
          await signOut();
          return null;
        }
      } catch (_) {}

      _cachedAccount = account;
      DoctorService.switchDoctor(user.uid);
      return account;
    } catch (e) {
      debugPrint('Error restoring session for user ${user.uid}: $e');
      return null;
    }
  }

  /// Securely signs out the doctor, clears session caches, and resets doctor scope.
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Firebase signOut error: $e');
    } finally {
      _cachedAccount = null;
      DoctorService.switchDoctor('');
    }
  }

  // ==========================================================================
  // DOCTOR ACCOUNT RECORD MANAGEMENT (Firestore: doctors/{uid})
  // ==========================================================================

  /// Ensures a Firestore doctor record exists for the authenticated UID.
  /// If missing (e.g. initial sign in of a provisioned Auth user), seeds
  /// profile data from existing doctor profile or auth credentials safely.
  static Future<DoctorAccount> _ensureDoctorAccount(User user) async {
    final docRef = _firestore.collection('doctors').doc(user.uid);
    final snapshot = await docRef.get();

    if (snapshot.exists && snapshot.data() != null) {
      final account = DoctorAccount.fromMap(snapshot.data()!, user.uid);
      // Ensure doctor_profile/{uid} mirror exists as well for legacy view compatibility
      try {
        final profileDoc = await _firestore.collection('doctor_profile').doc(user.uid).get();
        if (!profileDoc.exists) {
          await _firestore.collection('doctor_profile').doc(user.uid).set({
            'doctorId': user.uid,
            'name': account.displayName,
            'email': account.email,
            'speciality': account.specialty,
            'degree': account.degree,
            'phone': account.phone,
            'regNumber': account.regNumber,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
      return account;
    }

    // Check if legacy doctor_profile/main contains reference data to carry over
    Map<String, dynamic> seedData = {};
    try {
      final legacyDoc = await _firestore.collection('doctor_profile').doc('main').get();
      if (legacyDoc.exists && legacyDoc.data() != null) {
        seedData = legacyDoc.data()!;
      }
    } catch (_) {}

    final defaultName = user.displayName ??
        (seedData['name']?.toString() ??
            'Dr. ${user.email?.split('@').first.capitalize() ?? 'Doctor'}');

    final newAccount = DoctorAccount(
      uid: user.uid,
      email: user.email ?? '',
      displayName: defaultName,
      specialty: seedData['speciality']?.toString() ?? 'Consultant Physician',
      degree: seedData['degree']?.toString() ?? 'MBBS, MD',
      phone: seedData['phone']?.toString() ?? '',
      regNumber: seedData['regNumber']?.toString() ?? '',
      accountStatus: DoctorAccountStatus.active,
      onboardingCompleted: seedData['setupCompleted'] == true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(newAccount.toMap(), SetOptions(merge: true));

    // Also mirror to doctor_profile/{uid} for full compatibility
    try {
      await _firestore.collection('doctor_profile').doc(user.uid).set({
        ...newAccount.toMap(),
        'doctorId': user.uid,
        'name': newAccount.displayName,
        'email': newAccount.email,
        'speciality': newAccount.specialty,
        'degree': newAccount.degree,
      }, SetOptions(merge: true));
    } catch (_) {}

    return newAccount;
  }

  // ==========================================================================
  // ERROR MAPPING
  // ==========================================================================

  static String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Invalid email or password. Please verify your credentials.';
      case 'invalid-email':
        return 'The email address is not in a valid format.';
      case 'user-disabled':
        return 'This doctor account has been deactivated. Please contact support.';
      case 'too-many-requests':
        return 'Access temporarily blocked due to multiple failed login attempts. Please try again later or reset your password.';
      case 'network-request-failed':
        return 'Unable to reach the server. Please check your internet connection.';
      case 'operation-not-allowed':
        return 'Email & Password authentication is not enabled in Firebase Console.';
      default:
        return e.message ?? 'Authentication failed (${e.code}). Please try again.';
    }
  }
}

/// Typed authentication exception
class AuthException implements Exception {
  final String message;
  final String? code;
  const AuthException(this.message, {this.code});

  @override
  String toString() => message;
}

extension _StringExt on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
