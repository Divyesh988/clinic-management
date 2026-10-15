import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'doctor_service.dart';
import 'ehr_models.dart';

/// Central Electronic Health Records (EHR) Service.
/// Manages patient master profiles, longitudinal encounter records (visits),
/// atomic registrations, legacy migrations, and clinical audit histories.
class EhrService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _visitsCollection =>
      _firestore.collection('visits');

  static CollectionReference<Map<String, dynamic>> get _patientsCollection =>
      _firestore.collection('patients');

  // ==========================================================================
  // STREAMS & QUERIES
  // ==========================================================================

  /// Real-time stream of all clinical visits/encounters for a specific patient,
  /// sorted newest first.
  static Stream<List<VisitRecord>> streamPatientVisits(String patientId) {
    if (patientId.trim().isEmpty) {
      return Stream.value([]);
    }

    return _visitsCollection
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map((snapshot) {
      final list = <VisitRecord>[];
      for (final doc in snapshot.docs) {
        try {
          list.add(VisitRecord.fromMap(doc.data(), doc.id));
        } catch (e) {
          debugPrint('Error parsing visit record ${doc.id}: $e');
        }
      }

      // Sort newest first by visitDate, falling back to visitNumber
      list.sort((a, b) {
        final cmp = b.visitDate.compareTo(a.visitDate);
        if (cmp != 0) return cmp;
        return b.visitNumber.compareTo(a.visitNumber);
      });

      return list;
    });
  }

  /// Fetches all visits for a patient.
  static Future<List<VisitRecord>> getPatientVisits(String patientId) async {
    if (patientId.trim().isEmpty) return [];

    try {
      final snapshot = await _visitsCollection
          .where('patientId', isEqualTo: patientId)
          .get();

      final list = <VisitRecord>[];
      for (final doc in snapshot.docs) {
        try {
          list.add(VisitRecord.fromMap(doc.data(), doc.id));
        } catch (e) {
          debugPrint('Error parsing visit ${doc.id}: $e');
        }
      }

      list.sort((a, b) {
        final cmp = b.visitDate.compareTo(a.visitDate);
        if (cmp != 0) return cmp;
        return b.visitNumber.compareTo(a.visitNumber);
      });

      return list;
    } catch (e) {
      debugPrint('Error fetching patient visits: $e');
      return [];
    }
  }

  /// Gets the most recent finalized visit for a patient.
  static Future<VisitRecord?> getLatestVisitForPatient(String patientId) async {
    final visits = await getPatientVisits(patientId);
    return visits.isNotEmpty ? visits.first : null;
  }

  /// Searches for existing patients by ID, Phone number, or Name
  /// to prevent accidental duplicate patient profile creations.
  static Future<List<Map<String, dynamic>>> searchExistingPatients(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];

    final doctorId = DoctorService.currentDoctorId;
    try {
      final snapshot = await _patientsCollection
          .where('doctorId', isEqualTo: doctorId)
          .get();

      final matches = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['docId'] = doc.id;

        final id = (data['id']?.toString() ?? doc.id).toLowerCase();
        final name = (data['name']?.toString() ?? '').toLowerCase();
        final phone = (data['phone']?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
        final cleanPhoneQuery = clean.replaceAll(RegExp(r'\D'), '');

        if (id.contains(clean) ||
            name.contains(clean) ||
            (cleanPhoneQuery.isNotEmpty && phone.contains(cleanPhoneQuery))) {
          matches.add(data);
        }
      }

      return matches;
    } catch (e) {
      debugPrint('Error searching existing patients: $e');
      return [];
    }
  }

  // ==========================================================================
  // ATOMIC WORKFLOWS: FIRST TIME PATIENT REGISTRATION + VISIT #1
  // ==========================================================================

  /// Atomically creates the patient master profile AND their Visit #1 record.
  /// Guarantees that neither record is orphaned if one step fails.
  static Future<Map<String, dynamic>> savePatientWithFirstVisit({
    required Map<String, dynamic> patientData,
    required Map<String, dynamic> visitDetails,
  }) async {
    final batch = _firestore.batch();

    // 1. Resolve Patient ID
    String patientId = patientData['id']?.toString() ?? '';
    if (patientId.isEmpty) {
      patientId = "PT-${10000 + DateTime.now().millisecondsSinceEpoch % 90000}";
      patientData['id'] = patientId;
    }

    final patientRef = _patientsCollection.doc(patientId);

    // 2. Generate Visit #1 ID
    final visitId = "VS-${DateTime.now().millisecondsSinceEpoch}";
    final visitRef = _visitsCollection.doc(visitId);

    final now = DateTime.now();
    final visitDate = (visitDetails['visitDate'] is DateTime)
        ? (visitDetails['visitDate'] as DateTime)
        : now;

    final prescriptions = (visitDetails['prescriptions'] is List)
        ? List<Map<String, dynamic>>.from(visitDetails['prescriptions'] as List)
        : <Map<String, dynamic>>[];

    final medSummary = prescriptions.isNotEmpty
        ? prescriptions.map((m) => '${m['name']} (${m['dosage']})').join(', ')
        : 'None Prescribed';

    final consultFee = (visitDetails['consultationFee'] as num?)?.toDouble() ?? 500.0;
    final medFee = (visitDetails['medicineFee'] as num?)?.toDouble() ?? 200.0;
    final total = consultFee + medFee;
    final billStatus = visitDetails['billStatus']?.toString() ?? 'Paid';
    final pending = billStatus == 'Paid' ? 0.0 : total;

    // 3. Construct Visit #1 Record
    final visitRecord = VisitRecord(
      id: visitId,
      patientId: patientId,
      patientName: patientData['name']?.toString() ?? 'Patient',
      patientPhone: patientData['phone']?.toString() ?? '',
      clinicId: visitDetails['clinicId']?.toString() ?? patientData['clinicId']?.toString() ?? '',
      clinicName: visitDetails['clinicName']?.toString() ?? patientData['clinic']?.toString() ?? 'Clinic',
      clinicAddress: visitDetails['clinicAddress']?.toString() ?? patientData['clinicAddress']?.toString() ?? '',
      doctorId: DoctorService.currentDoctorId,
      visitNumber: 1,
      visitType: 'Initial Consultation',
      visitStatus: 'Completed',
      visitDate: visitDate,
      chiefComplaint: visitDetails['chiefComplaint']?.toString() ?? patientData['disease']?.toString() ?? 'General Consultation',
      symptoms: (visitDetails['symptoms'] is List)
          ? List<String>.from(visitDetails['symptoms'] as List)
          : [visitDetails['chiefComplaint']?.toString() ?? 'General Checkup'],
      vitals: (visitDetails['vitals'] is Map)
          ? Map<String, dynamic>.from(visitDetails['vitals'] as Map)
          : {},
      examinationNotes: visitDetails['examinationNotes']?.toString() ?? '',
      disease: visitDetails['disease']?.toString() ?? patientData['disease']?.toString() ?? 'General Consultation',
      diagnosis: visitDetails['diagnosis']?.toString() ?? patientData['diagnosis']?.toString() ?? 'Under Review',
      diseaseCategory: visitDetails['diseaseCategory']?.toString() ?? patientData['diseaseCategory']?.toString() ?? 'General & Infectious',
      prescriptions: prescriptions,
      clinicalNotes: visitDetails['clinicalNotes']?.toString() ?? '',
      treatmentPlan: visitDetails['treatmentPlan']?.toString() ?? '',
      followUpDate: visitDetails['followUpDate'] as DateTime?,
      followUpInstructions: visitDetails['followUpInstructions']?.toString() ?? '',
      consultationFee: consultFee,
      medicineFee: medFee,
      totalAmount: total,
      billStatus: billStatus,
      pendingAmount: pending,
      paymentMethod: visitDetails['paymentMethod']?.toString() ?? patientData['paymentMethod']?.toString() ?? 'UPI',
      isLegacyMigration: false,
      createdAt: now,
      updatedAt: now,
    );

    // 4. Update Patient Master Profile with Visit #1 Derived summary
    patientData['totalVisits'] = 1;
    patientData['lastVisit'] = 'Today, Just now';
    patientData['lastVisitDate'] = Timestamp.fromDate(visitDate);
    patientData['recentRx'] = medSummary;
    patientData['medicines'] = prescriptions;
    patientData['totalBilled'] = total.toInt();
    patientData['pendingAmount'] = pending.toInt();
    patientData['billStatus'] = billStatus;
    patientData['lastBillDate'] = 'Today';
    patientData['createdAt'] = FieldValue.serverTimestamp();
    patientData['updatedAt'] = FieldValue.serverTimestamp();

    // 5. Commit Batch
    batch.set(patientRef, patientData);
    batch.set(visitRef, visitRecord.toMap());

    await batch.commit();

    return {
      'patient': patientData,
      'visit': visitRecord,
    };
  }

  // ==========================================================================
  // NEW VISIT / FOLLOW-UP CONSULTATION WORKFLOW
  // ==========================================================================

  /// Saves a subsequent visit (Visit #2, #3...) for an existing patient.
  /// Atomically writes the encounter to `visits` and updates `patients/{patientId}`
  /// without overwriting historical clinical records!
  static Future<VisitRecord> saveNewVisit({
    required String patientId,
    required String patientName,
    required String patientPhone,
    required String clinicId,
    required String clinicName,
    required String clinicAddress,
    required String visitType,
    required DateTime visitDate,
    required String chiefComplaint,
    List<String> symptoms = const [],
    Map<String, dynamic> vitals = const {},
    String examinationNotes = '',
    required String disease,
    required String diagnosis,
    String diseaseCategory = 'General & Infectious',
    List<Map<String, dynamic>> prescriptions = const [],
    String clinicalNotes = '',
    String treatmentPlan = '',
    DateTime? followUpDate,
    String followUpInstructions = '',
    required double consultationFee,
    required double medicineFee,
    required String billStatus,
    required String paymentMethod,
  }) async {
    final batch = _firestore.batch();

    // 1. Fetch current patient profile to verify and increment visit count
    final patientRef = _patientsCollection.doc(patientId);
    final patientSnap = await patientRef.get();
    final patientData = patientSnap.data() ?? {};

    // 2. Determine accurate visit number
    final existingVisits = await getPatientVisits(patientId);
    final nextVisitNumber = existingVisits.length + 1;

    // 3. Generate stable Visit ID
    final visitId = "VS-${DateTime.now().millisecondsSinceEpoch}";
    final visitRef = _visitsCollection.doc(visitId);

    final total = consultationFee + medicineFee;
    final pending = billStatus == 'Paid' ? 0.0 : total;
    final now = DateTime.now();

    final visitRecord = VisitRecord(
      id: visitId,
      patientId: patientId,
      patientName: patientName,
      patientPhone: patientPhone,
      clinicId: clinicId,
      clinicName: clinicName,
      clinicAddress: clinicAddress,
      doctorId: DoctorService.currentDoctorId,
      visitNumber: nextVisitNumber,
      visitType: visitType,
      visitStatus: 'Completed',
      visitDate: visitDate,
      chiefComplaint: chiefComplaint,
      symptoms: symptoms.isNotEmpty ? symptoms : [chiefComplaint],
      vitals: vitals,
      examinationNotes: examinationNotes,
      disease: disease,
      diagnosis: diagnosis,
      diseaseCategory: diseaseCategory,
      prescriptions: prescriptions,
      clinicalNotes: clinicalNotes,
      treatmentPlan: treatmentPlan,
      followUpDate: followUpDate,
      followUpInstructions: followUpInstructions,
      consultationFee: consultationFee,
      medicineFee: medicineFee,
      totalAmount: total,
      billStatus: billStatus,
      pendingAmount: pending,
      paymentMethod: paymentMethod,
      isLegacyMigration: false,
      createdAt: now,
      updatedAt: now,
    );

    // 4. Update the Patient Master profile with latest visit reference & running totals
    final existingTotalBilled = (patientData['totalBilled'] as num?)?.toDouble() ?? 0.0;
    final existingPending = (patientData['pendingAmount'] as num?)?.toDouble() ?? 0.0;

    final medSummary = prescriptions.isNotEmpty
        ? prescriptions.map((m) => '${m['name']} (${m['dosage']})').join(', ')
        : 'None Prescribed';

    final patientUpdates = <String, dynamic>{
      'totalVisits': nextVisitNumber,
      'lastVisit': 'Today, Just now',
      'lastVisitDate': Timestamp.fromDate(visitDate),
      'clinicId': clinicId,
      'clinic': clinicName,
      'clinicAddress': clinicAddress,
      'disease': disease,
      'diagnosis': diagnosis,
      'diseaseCategory': diseaseCategory,
      'recentRx': medSummary,
      'medicines': prescriptions,
      'totalBilled': (existingTotalBilled + total).toInt(),
      'pendingAmount': (existingPending + pending).toInt(),
      'billStatus': pending > 0 ? 'Pending' : 'Paid',
      'lastBillDate': 'Today',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    batch.set(visitRef, visitRecord.toMap());
    batch.update(patientRef, patientUpdates);

    await batch.commit();

    return visitRecord;
  }

  // ==========================================================================
  // ENCOUNTER CORRECTIONS & AUDIT TRAIL
  // ==========================================================================

  /// Updates an existing finalized visit with an auditable change log.
  /// Preserves the previous version in the audit trail.
  static Future<void> updateVisitWithAudit({
    required String visitId,
    required Map<String, dynamic> changedFields,
    required String reason,
  }) async {
    final visitRef = _visitsCollection.doc(visitId);
    final snap = await visitRef.get();
    if (!snap.exists || snap.data() == null) {
      throw Exception('Visit document $visitId not found');
    }

    final currentData = snap.data()!;
    final List<dynamic> auditTrail = List.from(currentData['auditTrail'] ?? []);

    auditTrail.add({
      'timestamp': Timestamp.now(),
      'modifiedBy': DoctorService.currentDoctorId,
      'reason': reason,
      'previousValues': {
        for (final k in changedFields.keys)
          if (currentData.containsKey(k)) k: currentData[k],
      },
    });

    final updates = Map<String, dynamic>.from(changedFields);
    updates['auditTrail'] = auditTrail;
    updates['updatedAt'] = FieldValue.serverTimestamp();

    await visitRef.update(updates);
  }

  // ==========================================================================
  // IDEMPOTENT LEGACY DATA MIGRATION
  // ==========================================================================

  /// Transparently migrates single-record legacy patient documents
  /// into independent Visit #1 documents in the `visits` collection.
  ///
  /// Uses a deterministic docId: `VS_LEGACY_{patientId}`.
  /// If a visit already exists for a patient, that patient is safely skipped.
  /// Can be rerun indefinitely without duplicating records!
  static Future<Map<String, int>> migrateLegacyPatients() async {
    final doctorId = DoctorService.currentDoctorId;
    int migratedCount = 0;
    int skippedCount = 0;

    try {
      final patientsSnap = await _patientsCollection
          .where('doctorId', isEqualTo: doctorId)
          .get();

      for (final pDoc in patientsSnap.docs) {
        final pData = pDoc.data();
        final patientId = pData['id']?.toString() ?? pDoc.id;

        // Check if any visit already exists for this patient
        final existingVisits = await _visitsCollection
            .where('patientId', isEqualTo: patientId)
            .limit(1)
            .get();

        if (existingVisits.docs.isNotEmpty) {
          skippedCount++;
          continue;
        }

        // Create deterministic Legacy Visit #1
        final legacyVisitId = "VS_LEGACY_$patientId";

        DateTime recordDate = DateTime.now();
        final rawCreatedAt = pData['createdAt'];
        if (rawCreatedAt is Timestamp) {
          recordDate = rawCreatedAt.toDate();
        } else if (rawCreatedAt is String) {
          final parsed = DateTime.tryParse(rawCreatedAt);
          if (parsed != null) recordDate = parsed;
        }

        final rawMeds = pData['medicines'];
        final List<Map<String, dynamic>> rxList = [];
        if (rawMeds is List) {
          for (final m in rawMeds) {
            if (m is Map) rxList.add(Map<String, dynamic>.from(m));
          }
        }

        final consult = (pData['consultationFee'] as num?)?.toDouble() ?? 500.0;
        final meds = (pData['medicineFee'] as num?)?.toDouble() ?? 200.0;
        final total = (pData['totalAmount'] as num?)?.toDouble() ?? (consult + meds);
        final billSt = pData['billStatus']?.toString() ?? 'Paid';
        final pending = (pData['pendingAmount'] as num?)?.toDouble() ?? (billSt == 'Paid' ? 0.0 : total);

        final legacyVisit = VisitRecord(
          id: legacyVisitId,
          patientId: patientId,
          patientName: pData['name']?.toString() ?? 'Patient',
          patientPhone: pData['phone']?.toString() ?? '',
          clinicId: pData['clinicId']?.toString() ?? '',
          clinicName: pData['clinic']?.toString() ?? 'Sunrise Clinic',
          clinicAddress: pData['clinicAddress']?.toString() ?? '',
          doctorId: doctorId,
          visitNumber: 1,
          visitType: 'Initial Consultation (Migrated)',
          visitStatus: 'Completed',
          visitDate: recordDate,
          chiefComplaint: pData['disease']?.toString() ?? 'Initial Clinical Record',
          symptoms: [pData['disease']?.toString() ?? 'Initial Checkup'],
          vitals: const {},
          examinationNotes: 'Migrated from legacy patient registration record.',
          disease: pData['disease']?.toString() ?? 'General Consultation',
          diagnosis: pData['diagnosis']?.toString() ?? 'Initial Clinical Assessment',
          diseaseCategory: pData['diseaseCategory']?.toString() ?? 'General & Infectious',
          prescriptions: rxList,
          clinicalNotes: 'Legacy patient profile converted to longitudinal EHR encounter.',
          treatmentPlan: '',
          followUpDate: null,
          followUpInstructions: '',
          consultationFee: consult,
          medicineFee: meds,
          totalAmount: total,
          billStatus: billSt,
          pendingAmount: pending,
          paymentMethod: pData['paymentMethod']?.toString() ?? 'UPI',
          isLegacyMigration: true,
          createdAt: recordDate,
          updatedAt: DateTime.now(),
        );

        await _visitsCollection.doc(legacyVisitId).set(legacyVisit.toMap());
        migratedCount++;
      }

      debugPrint('EHR Migration complete: $migratedCount migrated, $skippedCount skipped.');
      return {
        'migrated': migratedCount,
        'skipped': skippedCount,
      };
    } catch (e) {
      debugPrint('Error running EHR migration: $e');
      return {
        'migrated': migratedCount,
        'skipped': skippedCount,
      };
    }
  }
}
