import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../doctor/account_suspended_screen.dart';
import 'auth_models.dart';
import 'doctor_service.dart';

/// Centralized SaaS Authentication & Doctor Identity Service.
/// Integrates Firebase Authentication with Cloud Firestore doctor authorization records,
/// real-time account suspension monitoring, and immediate clinical session restriction.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Global navigator key to allow immediate route redirection upon real-time suspension
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static DoctorAccount? _cachedAccount;

  // Real-time account status monitoring state
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _doctorDocSubscription;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _customerDocSubscription;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileDocSubscription;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customerQuerySubscription;
  static StreamSubscription<User?>? _authSubscription;
  static String? _monitoringUid;
  static bool _isSuspended = false;
  static String? _suspensionReason;

  /// Reactive notifiers for live UI updates across the entire application
  static final ValueNotifier<bool> isSuspendedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<DoctorAccount?> accountNotifier = ValueNotifier<DoctorAccount?>(null);

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

  /// Whether the current session has been flagged as suspended by Master Admin
  static bool get isCurrentSessionSuspended => _isSuspended;

  /// Stored reason for account suspension, if provided
  static String? get suspensionReason => _suspensionReason;

  // ==========================================================================
  // REAL-TIME ACCOUNT STATUS MONITORING & DIAGNOSTIC SYSTEM
  // ==========================================================================

  /// Initializes the global auth state change listener at application boot.
  /// Automatically attaches account status monitoring whenever a doctor signs in.
  static void initializeAuthListener() {
    if (_authSubscription != null) return;
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        debugPrint('[AuthService][AUTH_EVENT] authStateChanges: User authenticated (UID: ${user.uid}, Email: ${user.email})');
        startAccountStatusMonitoring(user.uid, user.email);
      } else {
        debugPrint('[AuthService][AUTH_EVENT] authStateChanges: User signed out / null');
        stopAccountStatusMonitoring();
      }
    });
    debugPrint('[AuthService] Initialized global authStateChanges listener.');
  }

  /// Initiates live Firestore listeners for `doctors/{uid}`, `customers/{uid}`,
  /// `doctor_profile/{uid}`, and query by `doctorUid`.
  /// Automatically called upon sign-in or session restoration.
  static void startAccountStatusMonitoring(String uid, [String? email]) {
    if (uid.isEmpty || uid == 'doc_main') {
      debugPrint('[AuthService][MONITOR_SKIP] Skipping live monitoring for empty/doc_main UID: "$uid"');
      return;
    }

    if (_monitoringUid == uid && _doctorDocSubscription != null) {
      debugPrint('[AuthService][MONITOR_EXISTS] Already actively monitoring doctor UID: $uid');
      return;
    }

    stopAccountStatusMonitoring();
    _monitoringUid = uid;

    final resolvedEmail = email ?? _auth.currentUser?.email;

    debugPrint('[AuthService][MONITOR_START] ========================================');
    debugPrint('[AuthService][MONITOR_START] Authenticated Firebase UID: $uid');
    debugPrint('[AuthService][MONITOR_START] Authenticated Email: $resolvedEmail');
    debugPrint('[AuthService][MONITOR_START] Activating live snapshot listeners on:');
    debugPrint('[AuthService][MONITOR_START]   1. Document: doctors/$uid');
    debugPrint('[AuthService][MONITOR_START]   2. Document: customers/$uid');
    debugPrint('[AuthService][MONITOR_START]   3. Document: doctor_profile/$uid');
    debugPrint('[AuthService][MONITOR_START]   4. Query: customers where doctorUid == $uid');
    debugPrint('[AuthService][MONITOR_START] ========================================');

    // 1. Subscribe to `doctors/{uid}`
    _doctorDocSubscription = _firestore
        .collection('doctors')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (_monitoringUid != uid) return;
        _onDoctorDocumentSnapshot(snapshot, uid);
      },
      onError: (error) {
        debugPrint('[AuthService][ERROR] doctors/$uid listener error: $error');
        if (error is FirebaseException &&
            (error.code == 'permission-denied' || error.code == 'unauthenticated')) {
          _triggerAccountSuspension(
            reason: 'Access revoked by platform security policy. Account may be suspended.',
            sourcePath: 'doctors/$uid (permission-denied)',
          );
        }
      },
    );

    // 2. Subscribe to `customers/{uid}` (SaaS directory record)
    _customerDocSubscription = _firestore
        .collection('customers')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (_monitoringUid != uid) return;
        _onCustomerDocumentSnapshot(snapshot, uid);
      },
      onError: (error) {
        debugPrint('[AuthService][ERROR] customers/$uid listener error: $error');
        if (error is FirebaseException &&
            (error.code == 'permission-denied' || error.code == 'unauthenticated')) {
          _triggerAccountSuspension(
            reason: 'Subscription access revoked by platform security policy.',
            sourcePath: 'customers/$uid (permission-denied)',
          );
        }
      },
    );

    // 3. Subscribe to `doctor_profile/{uid}`
    _profileDocSubscription = _firestore
        .collection('doctor_profile')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (_monitoringUid != uid) return;
        _onProfileDocumentSnapshot(snapshot, uid);
      },
      onError: (error) {
        debugPrint('[AuthService][ERROR] doctor_profile/$uid listener error: $error');
      },
    );

    // 4. Query `customers` where `doctorUid == uid` (handles records where documentId != doctorUid)
    _customerQuerySubscription = _firestore
        .collection('customers')
        .where('doctorUid', isEqualTo: uid)
        .snapshots()
        .listen(
      (querySnapshot) {
        if (_monitoringUid != uid) return;
        _onCustomerQuerySnapshot(querySnapshot, uid);
      },
      onError: (error) {
        debugPrint('[AuthService][ERROR] customers (where doctorUid==$uid) listener error: $error');
      },
    );
  }

  static void _onDoctorDocumentSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot, String uid) {
    final path = snapshot.reference.path;
    final exists = snapshot.exists;

    if (!exists || snapshot.data() == null) {
      debugPrint('[AuthService][SNAPSHOT] Path: $path | Exists: false');
      _triggerAccountSuspension(
        reason: 'Doctor account record not found on server.',
        sourcePath: path,
      );
      return;
    }

    final data = snapshot.data()!;
    final rawStatus = data['accountStatus']?.toString();
    final status = DoctorAccountStatus.fromString(rawStatus);
    final reason = data['suspensionReason']?.toString() ??
        'Account suspended by platform administrator.';

    final isSuspendedVerdict = (status == DoctorAccountStatus.suspended);
    final isActiveVerdict = (status == DoctorAccountStatus.active);

    debugPrint('[AuthService][SNAPSHOT] Path: $path | Exists: true | Raw: "$rawStatus" | Normalized: $status | isActive: $isActiveVerdict | isSuspended: $isSuspendedVerdict');

    if (isSuspendedVerdict) {
      _triggerAccountSuspension(reason: reason, sourcePath: path);
    } else if (status == DoctorAccountStatus.inactive) {
      _triggerAccountSuspension(
        reason: 'Doctor account is inactive. Please contact administration.',
        sourcePath: path,
      );
    } else if (isActiveVerdict) {
      if (_isSuspended) {
        debugPrint('[AuthService][REACTIVATION] doctors/$uid became active. Verifying customer status from server...');
        _recheckAndRestoreIfBothActive(uid);
      } else {
        _cachedAccount = DoctorAccount.fromMap(data, uid);
        accountNotifier.value = _cachedAccount;
      }
    }
  }

  static void _onCustomerDocumentSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot, String uid) {
    final path = snapshot.reference.path;
    final exists = snapshot.exists;

    if (!exists || snapshot.data() == null) {
      debugPrint('[AuthService][SNAPSHOT] Path: $path | Exists: false');
      return;
    }

    final data = snapshot.data()!;
    final rawStatus = data['accountStatus']?.toString();
    final cStatus = rawStatus?.toUpperCase().trim();
    final reason = data['suspensionReason']?.toString() ??
        'Clinic SaaS subscription is currently suspended.';

    debugPrint('[AuthService][SNAPSHOT] Path: $path | Exists: true | Raw: "$rawStatus" | Normalized: "$cStatus"');

    if (cStatus == 'SUSPENDED') {
      _triggerAccountSuspension(reason: reason, sourcePath: path);
    } else if (cStatus == 'CLOSED') {
      _triggerAccountSuspension(
        reason: 'Clinic SaaS subscription has been closed.',
        sourcePath: path,
      );
    } else if (cStatus == 'ACTIVE' && _isSuspended) {
      debugPrint('[AuthService][REACTIVATION] customers/$uid became ACTIVE. Verifying doctors status from server...');
      _recheckAndRestoreIfBothActive(uid);
    }
  }

  static void _onProfileDocumentSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot, String uid) {
    if (!snapshot.exists || snapshot.data() == null) return;
    final path = snapshot.reference.path;
    final data = snapshot.data()!;
    final rawStatus = data['accountStatus']?.toString();
    final pStatus = rawStatus?.toLowerCase().trim();
    final reason = data['suspensionReason']?.toString() ??
        'Doctor clinical access suspended by administrator.';

    debugPrint('[AuthService][SNAPSHOT] Path: $path | Exists: true | Raw: "$rawStatus" | Normalized: "$pStatus"');

    if (pStatus == 'suspended') {
      _triggerAccountSuspension(reason: reason, sourcePath: path);
    }
  }

  static void _onCustomerQuerySnapshot(
      QuerySnapshot<Map<String, dynamic>> querySnapshot, String uid) {
    debugPrint('[AuthService][QUERY_SNAPSHOT] customers (doctorUid==$uid) matched ${querySnapshot.docs.length} record(s)');
    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final rawStatus = data['accountStatus']?.toString();
      final cStatus = rawStatus?.toUpperCase().trim();
      final reason = data['suspensionReason']?.toString() ??
          'Clinic SaaS subscription is currently suspended.';
      debugPrint('[AuthService][QUERY_SNAPSHOT] customers/${doc.id} | Raw: "$rawStatus" | Normalized: "$cStatus"');

      if (cStatus == 'SUSPENDED') {
        _triggerAccountSuspension(reason: reason, sourcePath: 'customers/${doc.id}');
        return;
      } else if (cStatus == 'CLOSED') {
        _triggerAccountSuspension(
          reason: 'Clinic SaaS subscription has been closed.',
          sourcePath: 'customers/${doc.id}',
        );
        return;
      }
    }
  }

  /// Cancels live listeners and resets monitoring state safely.
  static void stopAccountStatusMonitoring() {
    _doctorDocSubscription?.cancel();
    _customerDocSubscription?.cancel();
    _profileDocSubscription?.cancel();
    _customerQuerySubscription?.cancel();
    _doctorDocSubscription = null;
    _customerDocSubscription = null;
    _profileDocSubscription = null;
    _customerQuerySubscription = null;
    _monitoringUid = null;
    debugPrint('[AuthService] Stopped live account status monitoring.');
  }

  /// Immediately enforces suspended session across the entire Flutter app.
  /// Prevents continued queries, clears doctor scope, and redirects to AccountSuspendedScreen.
  static void _triggerAccountSuspension({String? reason, String? sourcePath}) {
    final cleanReason = reason ?? 'Account suspended by platform administrator.';
    final previousNotifierVal = isSuspendedNotifier.value;

    _isSuspended = true;
    _suspensionReason = cleanReason;
    isSuspendedNotifier.value = true;
    _cachedAccount = null;
    accountNotifier.value = null;

    // Reset doctor scope so active queries and streams stop fetching sensitive clinic data
    DoctorService.switchDoctor('');

    debugPrint('[AuthService][SUSPENSION_DETECTED] ========================================');
    debugPrint('[AuthService][SUSPENSION_DETECTED] Source trigger: ${sourcePath ?? 'authoritative check'}');
    debugPrint('[AuthService][SUSPENSION_DETECTED] Reason: $cleanReason');
    debugPrint('[AuthService][SUSPENSION_DETECTED] Previous isSuspendedNotifier: $previousNotifierVal -> New: true');
    debugPrint('[AuthService][SUSPENSION_DETECTED] Reset DoctorService active doctor session.');
    debugPrint('[AuthService][SUSPENSION_DETECTED] ========================================');

    // Push AccountSuspendedScreen and clear navigation stack safely in post-frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentState != null) {
        debugPrint('[AuthService][NAVIGATE] Executing pushAndRemoveUntil(AccountSuspendedScreen)');
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AccountSuspendedScreen(reason: cleanReason),
          ),
          (route) => false,
        );
      } else {
        debugPrint('[AuthService][NAVIGATE] navigatorKey.currentState is null (handled reactively by MaterialApp.builder Stack)');
      }
    });
  }

  /// Checks if both `doctors/{uid}` and `customers/{uid}` have returned to active status on the SERVER.
  static Future<void> _recheckAndRestoreIfBothActive(String uid) async {
    try {
      debugPrint('[AuthService][RECHECK] Querying server for authoritative status across doctors/$uid, customers, and doctor_profile...');

      // 1. Check doctors/{uid} strictly from SERVER
      final docSnap = await _firestore.collection('doctors').doc(uid).get(
        const GetOptions(source: Source.server),
      );
      if (!docSnap.exists || docSnap.data() == null) {
        debugPrint('[AuthService][RECHECK] doctors/$uid missing on server; remaining suspended.');
        return;
      }
      final dStatus = DoctorAccountStatus.fromString(docSnap.data()!['accountStatus']?.toString());
      if (dStatus != DoctorAccountStatus.active) {
        debugPrint('[AuthService][RECHECK] doctors/$uid status is $dStatus (not active); remaining suspended.');
        return;
      }

      // 2. Check customers/{uid} from SERVER
      try {
        final custSnap = await _firestore.collection('customers').doc(uid).get(
          const GetOptions(source: Source.server),
        );
        if (custSnap.exists && custSnap.data() != null) {
          final cStatus = custSnap.data()!['accountStatus']?.toString().toUpperCase().trim();
          if (cStatus == 'SUSPENDED' || cStatus == 'CLOSED') {
            debugPrint('[AuthService][RECHECK] customers/$uid is $cStatus; remaining suspended.');
            return;
          }
        }
      } catch (e) {
        debugPrint('[AuthService][RECHECK] Error checking customers/$uid: $e');
      }

      // 3. Check doctor_profile/{uid} from SERVER
      try {
        final profSnap = await _firestore.collection('doctor_profile').doc(uid).get(
          const GetOptions(source: Source.server),
        );
        if (profSnap.exists && profSnap.data() != null) {
          final pStatus = profSnap.data()!['accountStatus']?.toString().toLowerCase().trim();
          if (pStatus == 'suspended') {
            debugPrint('[AuthService][RECHECK] doctor_profile/$uid is suspended; remaining suspended.');
            return;
          }
        }
      } catch (e) {
        debugPrint('[AuthService][RECHECK] Error checking doctor_profile/$uid: $e');
      }

      // Both are active! Restore session
      debugPrint('[AuthService][RESTORE] All server records active. Restoring active doctor session for $uid');
      _isSuspended = false;
      _suspensionReason = null;
      isSuspendedNotifier.value = false;
      _cachedAccount = DoctorAccount.fromMap(docSnap.data()!, uid);
      accountNotifier.value = _cachedAccount;
      DoctorService.switchDoctor(uid);
    } catch (e) {
      debugPrint('[AuthService][RECHECK] Server revalidation error: $e. Remaining suspended.');
    }
  }

  // ==========================================================================
  // SIGN IN WORKFLOW
  // ==========================================================================

  /// Authenticates doctor using Email and Password via Firebase Authentication.
  /// Verifies account record in Firestore, checks authorization status, and begins monitoring.
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

      // 4. Initialize Doctor session scope and launch live monitoring
      _isSuspended = false;
      _suspensionReason = null;
      isSuspendedNotifier.value = false;
      _cachedAccount = account;
      accountNotifier.value = account;
      DoctorService.switchDoctor(user.uid);

      startAccountStatusMonitoring(user.uid);

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
      _isSuspended = false;
      isSuspendedNotifier.value = false;
      stopAccountStatusMonitoring();
      return null;
    }

    try {
      final account = await revalidateActiveSession(forceServer: false);
      if (account == null || !account.isActive) {
        // revalidateActiveSession already triggers suspension flow if suspended
        return null;
      }
      return account;
    } catch (e) {
      debugPrint('[AuthService] Error restoring session for user ${user.uid}: $e');
      return null;
    }
  }

  /// Authoritatively revalidates active session against Firestore.
  /// Called upon app resume from background, on network reconnect, and manually from AccountSuspendedScreen.
  static Future<DoctorAccount?> revalidateActiveSession({bool forceServer = true}) async {
    final user = _auth.currentUser;
    if (user == null) {
      _cachedAccount = null;
      _isSuspended = false;
      isSuspendedNotifier.value = false;
      stopAccountStatusMonitoring();
      return null;
    }

    final source = forceServer ? Source.server : Source.serverAndCache;

    try {
      // 1. Fetch doctors/{uid}
      final docRef = _firestore.collection('doctors').doc(user.uid);
      DocumentSnapshot<Map<String, dynamic>> docSnap;
      try {
        docSnap = await docRef.get(GetOptions(source: source));
      } catch (e) {
        docSnap = await docRef.get();
      }

      if (!docSnap.exists || docSnap.data() == null) {
        _triggerAccountSuspension(reason: 'Doctor account record not found on server.');
        return null;
      }

      final docData = docSnap.data()!;
      final status = DoctorAccountStatus.fromString(docData['accountStatus']?.toString());
      if (status == DoctorAccountStatus.suspended) {
        final reason = docData['suspensionReason']?.toString() ?? 'Account suspended by platform administrator.';
        _triggerAccountSuspension(reason: reason);
        return null;
      }
      if (status == DoctorAccountStatus.inactive) {
        _triggerAccountSuspension(reason: 'Doctor account is inactive. Please contact administration.');
        return null;
      }

      // 2. Fetch customers/{uid} if present
      try {
        final custRef = _firestore.collection('customers').doc(user.uid);
        final custSnap = await custRef.get(GetOptions(source: source));
        if (custSnap.exists && custSnap.data() != null) {
          final cStatus = custSnap.data()!['accountStatus']?.toString().toUpperCase();
          if (cStatus == 'SUSPENDED') {
            final reason = custSnap.data()!['suspensionReason']?.toString() ?? 'Clinic SaaS subscription is suspended.';
            _triggerAccountSuspension(reason: reason);
            return null;
          } else if (cStatus == 'CLOSED') {
            _triggerAccountSuspension(reason: 'Clinic SaaS subscription has been closed.');
            return null;
          }
        }
      } catch (_) {}

      // Both verified active!
      final account = DoctorAccount.fromMap(docData, user.uid);
      _isSuspended = false;
      _suspensionReason = null;
      isSuspendedNotifier.value = false;
      _cachedAccount = account;
      accountNotifier.value = account;
      DoctorService.switchDoctor(user.uid);

      // Ensure real-time monitoring is running
      startAccountStatusMonitoring(user.uid);

      return account;
    } on FirebaseException catch (e) {
      debugPrint('[AuthService] Revalidate session Firebase error: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        _triggerAccountSuspension(reason: 'Access revoked by platform security policy.');
      }
      return null;
    } catch (e) {
      debugPrint('[AuthService] Revalidate session general error: $e');
      return null;
    }
  }

  /// Securely signs out the doctor, cancels active listeners, clears session caches, and resets doctor scope.
  static Future<void> signOut() async {
    try {
      stopAccountStatusMonitoring();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Firebase signOut error: $e');
    } finally {
      _cachedAccount = null;
      _isSuspended = false;
      _suspensionReason = null;
      isSuspendedNotifier.value = false;
      accountNotifier.value = null;
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
        return 'Email & Password authentication is currently unavailable. Please contact system support.';
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
