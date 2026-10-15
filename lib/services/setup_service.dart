import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'clinic_service.dart';
import 'doctor_service.dart';

class SetupStatus {
  final int clinicCount;
  final int medicineCount;
  final bool manualMedicineSetupConfirmed;
  final bool persistedSetupCompleted;

  const SetupStatus({
    required this.clinicCount,
    required this.medicineCount,
    required this.manualMedicineSetupConfirmed,
    required this.persistedSetupCompleted,
  });

  bool get clinicSetupCompleted => clinicCount > 0;
  bool get medicineSetupCompleted => medicineCount > 0 || manualMedicineSetupConfirmed;
  bool get isComplete => clinicSetupCompleted && medicineSetupCompleted;
}

class SetupService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String get _effectiveDocId {
    final docId = DoctorService.currentDoctorId;
    return (docId.isNotEmpty && docId != 'doc_main') ? docId : 'main';
  }

  /// Checks authoritative Firestore data and returns the current setup status.
  /// If [reconcileFirestore] is true, updates the doctor profile document with verified flags.
  static Future<SetupStatus> checkSetupStatus({bool reconcileFirestore = true}) async {
    try {
      // Run legacy clinic migration if needed
      await ClinicService.migrateLegacyClinicsIfNeeded();

      final targetDocId = _effectiveDocId;

      // 1. Check clinics count strictly for the current doctor
      final clinics = await ClinicService.getDoctorClinics();
      final clinicCount = clinics.length;

      // 2. Check predefined medicines count
      final medicinesSnapshot = await _firestore.collection('predefined_medicines').get();
      final medicineCount = medicinesSnapshot.docs.length;

      // 3. Check target doctor profile document
      final profileDoc = await _firestore.collection('doctor_profile').doc(targetDocId).get();
      final profileData = profileDoc.data() ?? {};

      // 4. Also check doctors/{uid} if authenticated
      Map<String, dynamic> doctorAccountData = {};
      if (targetDocId != 'main') {
        try {
          final docAccount = await _firestore.collection('doctors').doc(targetDocId).get();
          if (docAccount.exists && docAccount.data() != null) {
            doctorAccountData = docAccount.data()!;
          }
        } catch (_) {}
      }

      final manualMedicineConfirmed = profileData['manualMedicineSetupConfirmed'] == true ||
          doctorAccountData['onboardingCompleted'] == true;
      final persistedCompleted = profileData['setupCompleted'] == true ||
          doctorAccountData['onboardingCompleted'] == true ||
          doctorAccountData['setupCompleted'] == true;

      final status = SetupStatus(
        clinicCount: clinicCount,
        medicineCount: medicineCount,
        manualMedicineSetupConfirmed: manualMedicineConfirmed,
        persistedSetupCompleted: persistedCompleted,
      );

      // Reconcile authoritative state back to Firestore if requested
      if (reconcileFirestore) {
        final Map<String, dynamic> updateData = {
          'clinicSetupCompleted': status.clinicSetupCompleted,
          'medicineSetupCompleted': status.medicineSetupCompleted,
          'setupCompleted': status.isComplete,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (status.isComplete && !persistedCompleted) {
          updateData['setupCompletedAt'] = FieldValue.serverTimestamp();
        }

        await _firestore.collection('doctor_profile').doc(targetDocId).set(
          updateData,
          SetOptions(merge: true),
        );

        if (targetDocId != 'main') {
          await _firestore.collection('doctors').doc(targetDocId).set({
            'onboardingCompleted': status.isComplete,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      return status;
    } catch (e) {
      debugPrint('Error evaluating SetupStatus from Firestore: $e');
      rethrow;
    }
  }

  /// Doctor explicitly opts to add medicines manually rather than bulk importing right now.
  static Future<void> confirmManualMedicines() async {
    final targetDocId = _effectiveDocId;
    await _firestore.collection('doctor_profile').doc(targetDocId).set({
      'manualMedicineSetupConfirmed': true,
      'medicineSetupCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (targetDocId != 'main') {
      await _firestore.collection('doctors').doc(targetDocId).set({
        'onboardingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Finalizes setup in Firestore
  static Future<void> completeSetup() async {
    final targetDocId = _effectiveDocId;
    await _firestore.collection('doctor_profile').doc(targetDocId).set({
      'clinicSetupCompleted': true,
      'medicineSetupCompleted': true,
      'setupCompleted': true,
      'setupCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (targetDocId != 'main') {
      await _firestore.collection('doctors').doc(targetDocId).set({
        'onboardingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
