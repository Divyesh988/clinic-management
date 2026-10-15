import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'doctor_service.dart';

/// Centralized repository and service for doctor-scoped Clinic operations.
/// Strictly enforces that every query, read, write, update, and deletion is scoped to the current doctor.
class ClinicService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _clinicsCollection =>
      _firestore.collection('clinics');

  /// Streams only the clinics registered by the currently authenticated doctor.
  static Stream<List<Map<String, dynamic>>> streamDoctorClinics() {
    final doctorId = DoctorService.currentDoctorId;
    return _clinicsCollection
        .where('doctorId', isEqualTo: doctorId)
        .snapshots()
        .map((snapshot) {
      final List<Map<String, dynamic>> clinics = [];
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['docId'] = doc.id;
        clinics.add(data);
      }

      clinics.sort((a, b) {
        final aPrimary = a['isPrimary'] == true ? 1 : 0;
        final bPrimary = b['isPrimary'] == true ? 1 : 0;
        if (aPrimary != bPrimary) return bPrimary.compareTo(aPrimary);
        return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
      });

      return clinics;
    });
  }

  /// Fetches only the clinics registered by the currently authenticated doctor.
  static Future<List<Map<String, dynamic>>> getDoctorClinics() async {
    final doctorId = DoctorService.currentDoctorId;
    final snapshot = await _clinicsCollection
        .where('doctorId', isEqualTo: doctorId)
        .get();

    final List<Map<String, dynamic>> clinics = [];
    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['docId'] = doc.id;
      clinics.add(data);
    }

    clinics.sort((a, b) {
      final aPrimary = a['isPrimary'] == true ? 1 : 0;
      final bPrimary = b['isPrimary'] == true ? 1 : 0;
      if (aPrimary != bPrimary) return bPrimary.compareTo(aPrimary);
      return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
    });

    return clinics;
  }

  /// Authoritatively fetches and validates a clinic by ID.
  /// Returns the clinic data if and ONLY if it exists and belongs to the current doctor.
  static Future<Map<String, dynamic>?> getClinicById(String clinicId) async {
    if (clinicId.trim().isEmpty) return null;

    try {
      final doc = await _clinicsCollection.doc(clinicId).get();
      if (!doc.exists || doc.data() == null) return null;

      final data = Map<String, dynamic>.from(doc.data()!);
      data['docId'] = doc.id;

      // Verify ownership strictly
      if (data['doctorId'] != DoctorService.currentDoctorId) {
        debugPrint('Security warning: Attempted to access clinic $clinicId owned by another doctor (${data['doctorId']})');
        return null;
      }

      return data;
    } catch (e) {
      debugPrint('Error getting clinic by id: $e');
      return null;
    }
  }

  /// Saves (creates or updates) a clinic document, strictly stamping the current doctor's ID.
  static Future<Map<String, dynamic>> saveClinic({
    String? docId,
    required String name,
    required String address,
    String? phone,
    String? email,
    double? consultationFee,
    String? workingHours,
    bool isPrimary = false,
  }) async {
    final doctorId = DoctorService.currentDoctorId;

    final clinicData = <String, dynamic>{
      'name': name.trim(),
      'address': address.trim(),
      'phone': (phone ?? '').trim(),
      'email': (email ?? '').trim(),
      'consultationFee': consultationFee ?? 500.0,
      'workingHours': (workingHours ?? '').trim(),
      'isPrimary': isPrimary,
      'doctorId': doctorId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    String currentDocId = docId ?? '';
    if (docId == null || docId.isEmpty) {
      clinicData['createdAt'] = FieldValue.serverTimestamp();
      final ref = await _clinicsCollection.add(clinicData);
      currentDocId = ref.id;
    } else {
      // Validate that existing doc belongs to current doctor before updating
      final existing = await _clinicsCollection.doc(docId).get();
      if (existing.exists && existing.data()?['doctorId'] != doctorId) {
        throw Exception('Unauthorized: Cannot update clinic belonging to another doctor.');
      }
      await _clinicsCollection.doc(docId).update(clinicData);
    }

    // If primary, atomically un-mark other clinics for THIS doctor only
    if (isPrimary) {
      await _handlePrimarySync(currentDocId, clinicData);
    } else {
      // If this is the doctor's only clinic, make it primary automatically
      final myClinics = await getDoctorClinics();
      if (myClinics.length == 1) {
        clinicData['isPrimary'] = true;
        await _clinicsCollection.doc(currentDocId).update({'isPrimary': true});
        await _handlePrimarySync(currentDocId, clinicData);
      }
    }

    // Ensure doctor_profile records clinicSetupCompleted
    await _firestore.collection('doctor_profile').doc('main').set({
      'clinicSetupCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    clinicData['docId'] = currentDocId;
    return clinicData;
  }

  /// Synchronizes primary clinic state across doctor's clinics and doctor_profile/main
  static Future<void> _handlePrimarySync(String primaryDocId, Map<String, dynamic> clinicData) async {
    final doctorId = DoctorService.currentDoctorId;
    final doctorClinics = await _clinicsCollection.where('doctorId', isEqualTo: doctorId).get();

    final batch = _firestore.batch();
    for (final doc in doctorClinics.docs) {
      if (doc.id != primaryDocId && doc.data()['isPrimary'] == true) {
        batch.update(doc.reference, {'isPrimary': false});
      }
    }
    await batch.commit();

    await _firestore.collection('doctor_profile').doc('main').set({
      'clinicName': clinicData['name'],
      'clinicAddress': clinicData['address'],
      'primaryClinicId': primaryDocId,
      'consultationFee': clinicData['consultationFee'],
      'clinicSetupCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sets a clinic as the primary clinic for the current doctor
  static Future<void> setPrimaryClinic(String clinicId) async {
    final clinic = await getClinicById(clinicId);
    if (clinic == null) {
      throw Exception('Clinic not found or does not belong to the current doctor.');
    }

    await _clinicsCollection.doc(clinicId).update({
      'isPrimary': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _handlePrimarySync(clinicId, clinic);
  }

  /// Deletes a clinic belonging to the current doctor.
  static Future<void> deleteClinic(String clinicId) async {
    final clinic = await getClinicById(clinicId);
    if (clinic == null) {
      throw Exception('Clinic not found or does not belong to the current doctor.');
    }

    await _clinicsCollection.doc(clinicId).delete();

    // If it was primary, designate another clinic of this doctor as primary if any remain
    if (clinic['isPrimary'] == true) {
      final remaining = await getDoctorClinics();
      if (remaining.isNotEmpty) {
        await setPrimaryClinic(remaining.first['docId']);
      } else {
        await _firestore.collection('doctor_profile').doc('main').set({
          'primaryClinicId': null,
          'clinicSetupCompleted': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  /// Safe, explicit legacy migration:
  /// Inspects legacy clinics that lack doctorId.
  /// If doctor_profile/main explicitly designates `primaryClinicId`, links that clinic to the doctor.
  /// Unassigned clinics are left untouched and excluded from doctor queries.
  static Future<void> migrateLegacyClinicsIfNeeded() async {
    try {
      final profileDoc = await _firestore.collection('doctor_profile').doc('main').get();
      if (!profileDoc.exists || profileDoc.data() == null) return;

      final profileData = profileDoc.data()!;
      final primaryClinicId = profileData['primaryClinicId']?.toString();
      final doctorId = DoctorService.currentDoctorId;

      if (primaryClinicId != null && primaryClinicId.isNotEmpty) {
        final clinicDoc = await _clinicsCollection.doc(primaryClinicId).get();
        if (clinicDoc.exists && clinicDoc.data()?['doctorId'] == null) {
          debugPrint('Migrating legacy clinic $primaryClinicId to doctor $doctorId based on verified profile reference.');
          await _clinicsCollection.doc(primaryClinicId).update({
            'doctorId': doctorId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('Legacy clinic migration check error: $e');
    }
  }
}
