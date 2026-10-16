import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service managing the authenticated doctor's identity, profile mapping, and session state.
class DoctorService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Active doctor ID. Defaults to 'doc_main' (authoritative main doctor profile).
  static String _currentDoctorId = 'doc_main';

  // ValueNotifier to allow reactive updates across screens when doctor session changes
  static final ValueNotifier<String> activeDoctorNotifier = ValueNotifier<String>(_currentDoctorId);

  static String get currentDoctorId => _currentDoctorId;

  /// Changes the active doctor identifier (e.g. on sign-in / switch account).
  /// Notifies all listeners to refresh their queries and streams.
  static void switchDoctor(String doctorId) {
    if (_currentDoctorId != doctorId) {
      _currentDoctorId = doctorId;
      activeDoctorNotifier.value = doctorId;
      debugPrint('Switched active doctor session to: $doctorId');
    }
  }

  /// Resolves the canonical doctor profile from Firestore (checking doctors/{uid} and doctor_profile/{uid}).
  /// Falls back to doctor_profile/main only for legacy unauthenticated/doc_main sessions.
  static Future<Map<String, dynamic>> ensureDoctorProfile([String? explicitDoctorId]) async {
    final doctorId = explicitDoctorId ?? _currentDoctorId;
    if (doctorId.isEmpty) {
      return {'doctorId': ''};
    }

    try {
      // 1. If this is a real authenticated doctor UID (not legacy doc_main)
      if (doctorId != 'doc_main') {
        final doctorDoc = await _firestore.collection('doctors').doc(doctorId).get();
        final profileDoc = await _firestore.collection('doctor_profile').doc(doctorId).get();

        if (doctorDoc.exists || profileDoc.exists) {
          final merged = <String, dynamic>{
            'doctorId': doctorId,
            'uid': doctorId,
          };
          if (profileDoc.exists && profileDoc.data() != null) {
            merged.addAll(profileDoc.data()!);
          }
          if (doctorDoc.exists && doctorDoc.data() != null) {
            final docData = doctorDoc.data()!;
            merged['name'] ??= docData['displayName'];
            merged['email'] ??= docData['email'];
            merged['phone'] ??= docData['phone'];
            merged['regNumber'] ??= docData['regNumber'];
            merged['speciality'] ??= docData['specialty'];
            merged['degree'] ??= docData['degree'];
            merged['accountStatus'] = docData['accountStatus'];
            merged['onboardingCompleted'] = docData['onboardingCompleted'];
          }
          return merged;
        }
      }

      // 2. Legacy fallback for doc_main
      final docRef = _firestore.collection('doctor_profile').doc('main');
      final snapshot = await docRef.get();

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        if (data['doctorId'] == null) {
          await docRef.set({
            'doctorId': _currentDoctorId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          data['doctorId'] = _currentDoctorId;
        }
        return data;
      } else {
        final initialProfile = {
          'doctorId': _currentDoctorId,
          'name': 'Doctor',
          'degree': 'MBBS',
          'speciality': 'Consultant Physician',
          'regNumber': '',
          'experience': '',
          'phone': '',
          'email': '',
          'clinicName': 'Main Clinic',
          'clinicAddress': '',
          'consultationFee': 500.0,
          'workingHours': 'Mon - Sat: 09:00 AM - 01:00 PM, 05:00 PM - 08:30 PM',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await docRef.set(initialProfile);
        return initialProfile;
      }
    } catch (e) {
      debugPrint('Error ensuring doctor profile: $e');
      return {'doctorId': _currentDoctorId};
    }
  }

  /// Streams the active doctor profile dynamically.
  static Stream<Map<String, dynamic>> streamDoctorProfile() {
    final doctorId = _currentDoctorId;
    if (doctorId.isNotEmpty && doctorId != 'doc_main') {
      return _firestore.collection('doctor_profile').doc(doctorId).snapshots().asyncMap((docSnap) async {
        if (docSnap.exists && docSnap.data() != null) {
          final data = Map<String, dynamic>.from(docSnap.data()!);
          data['doctorId'] = doctorId;
          return data;
        }
        // Fallback to doctors/{uid}
        final docAccount = await _firestore.collection('doctors').doc(doctorId).get();
        if (docAccount.exists && docAccount.data() != null) {
          final d = docAccount.data()!;
          return {
            'doctorId': doctorId,
            'name': d['displayName'] ?? 'Doctor',
            'email': d['email'] ?? '',
            'phone': d['phone'] ?? '',
            'regNumber': d['regNumber'] ?? '',
            'speciality': d['specialty'] ?? 'Consultant Physician',
            'degree': d['degree'] ?? 'MBBS',
          };
        }
        return {'doctorId': doctorId, 'name': 'Doctor'};
      });
    }

    return _firestore.collection('doctor_profile').doc('main').snapshots().map((snap) {
      return snap.data() ?? {'doctorId': 'doc_main', 'name': 'Doctor'};
    });
  }
}
