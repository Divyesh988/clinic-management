import 'package:cloud_firestore/cloud_firestore.dart';

/// EHR Visit / Encounter model representing a distinct clinical consultation.
class VisitRecord {
  final String id;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final String clinicId;
  final String clinicName;
  final String clinicAddress;
  final String doctorId;
  final int visitNumber;
  final String visitType; // 'Initial Consultation', 'Follow-up', 'Routine Checkup', 'Emergency'
  final String visitStatus; // 'Completed', 'Draft', 'Cancelled'
  final DateTime visitDate;
  final String chiefComplaint;
  final List<String> symptoms;
  final Map<String, dynamic> vitals; // bp, pulse, temperature, weight, spo2, etc.
  final String examinationNotes;
  final String disease;
  final String diagnosis;
  final String diseaseCategory;
  final List<Map<String, dynamic>> prescriptions; // [{name, type, dosage, duration, instructions}]
  final String clinicalNotes;
  final String treatmentPlan;
  final DateTime? followUpDate;
  final String followUpInstructions;
  final double consultationFee;
  final double medicineFee;
  final double totalAmount;
  final String billStatus; // 'Paid', 'Pending'
  final double pendingAmount;
  final String paymentMethod; // 'UPI', 'Cash', 'Card', etc.
  final bool isLegacyMigration;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> auditTrail;

  const VisitRecord({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientPhone = '',
    required this.clinicId,
    required this.clinicName,
    this.clinicAddress = '',
    required this.doctorId,
    required this.visitNumber,
    this.visitType = 'Initial Consultation',
    this.visitStatus = 'Completed',
    required this.visitDate,
    this.chiefComplaint = '',
    this.symptoms = const [],
    this.vitals = const {},
    this.examinationNotes = '',
    this.disease = '',
    this.diagnosis = '',
    this.diseaseCategory = 'General & Infectious',
    this.prescriptions = const [],
    this.clinicalNotes = '',
    this.treatmentPlan = '',
    this.followUpDate,
    this.followUpInstructions = '',
    this.consultationFee = 0.0,
    this.medicineFee = 0.0,
    this.totalAmount = 0.0,
    this.billStatus = 'Paid',
    this.pendingAmount = 0.0,
    this.paymentMethod = 'UPI',
    this.isLegacyMigration = false,
    this.createdAt,
    this.updatedAt,
    this.auditTrail = const [],
  });

  /// Convert Firestore document snapshot/map to VisitRecord
  factory VisitRecord.fromMap(Map<String, dynamic> data, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawPrescriptions = data['prescriptions'] ?? data['medicines'];
    final List<Map<String, dynamic>> parsedRx = [];
    if (rawPrescriptions is List) {
      for (final item in rawPrescriptions) {
        if (item is Map) {
          parsedRx.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final rawSymptoms = data['symptoms'];
    final List<String> parsedSymptoms = [];
    if (rawSymptoms is List) {
      for (final s in rawSymptoms) {
        if (s != null) parsedSymptoms.add(s.toString());
      }
    }

    final rawAudit = data['auditTrail'];
    final List<Map<String, dynamic>> parsedAudit = [];
    if (rawAudit is List) {
      for (final a in rawAudit) {
        if (a is Map) parsedAudit.add(Map<String, dynamic>.from(a));
      }
    }

    final rawVitals = data['vitals'];
    final Map<String, dynamic> parsedVitals = rawVitals is Map
        ? Map<String, dynamic>.from(rawVitals)
        : {};

    final total = (data['totalAmount'] as num?)?.toDouble() ??
        ((data['totalBilled'] as num?)?.toDouble() ?? 0.0);
    final consult = (data['consultationFee'] as num?)?.toDouble() ?? 0.0;
    final meds = (data['medicineFee'] as num?)?.toDouble() ?? 0.0;
    final billSt = data['billStatus']?.toString() ?? 'Paid';
    final pending = (data['pendingAmount'] as num?)?.toDouble() ??
        (billSt == 'Paid' ? 0.0 : total);

    return VisitRecord(
      id: docId.isNotEmpty ? docId : (data['id']?.toString() ?? 'VS-0000'),
      patientId: data['patientId']?.toString() ?? '',
      patientName: data['patientName']?.toString() ?? (data['name']?.toString() ?? 'Patient'),
      patientPhone: data['patientPhone']?.toString() ?? (data['phone']?.toString() ?? ''),
      clinicId: data['clinicId']?.toString() ?? '',
      clinicName: data['clinicName']?.toString() ?? (data['clinic']?.toString() ?? 'Clinic'),
      clinicAddress: data['clinicAddress']?.toString() ?? '',
      doctorId: data['doctorId']?.toString() ?? '',
      visitNumber: (data['visitNumber'] as num?)?.toInt() ?? 1,
      visitType: data['visitType']?.toString() ?? 'Initial Consultation',
      visitStatus: data['visitStatus']?.toString() ?? 'Completed',
      visitDate: parseDate(data['visitDate'] ?? data['createdAt']),
      chiefComplaint: data['chiefComplaint']?.toString() ?? (data['disease']?.toString() ?? ''),
      symptoms: parsedSymptoms,
      vitals: parsedVitals,
      examinationNotes: data['examinationNotes']?.toString() ?? '',
      disease: data['disease']?.toString() ?? '',
      diagnosis: data['diagnosis']?.toString() ?? '',
      diseaseCategory: data['diseaseCategory']?.toString() ?? 'General & Infectious',
      prescriptions: parsedRx,
      clinicalNotes: data['clinicalNotes']?.toString() ?? '',
      treatmentPlan: data['treatmentPlan']?.toString() ?? '',
      followUpDate: parseNullableDate(data['followUpDate']),
      followUpInstructions: data['followUpInstructions']?.toString() ?? '',
      consultationFee: consult,
      medicineFee: meds,
      totalAmount: total,
      billStatus: billSt,
      pendingAmount: pending,
      paymentMethod: data['paymentMethod']?.toString() ?? 'UPI',
      isLegacyMigration: data['isLegacyMigration'] == true,
      createdAt: parseNullableDate(data['createdAt']),
      updatedAt: parseNullableDate(data['updatedAt']),
      auditTrail: parsedAudit,
    );
  }

  /// Convert to Firestore Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'clinicId': clinicId,
      'clinicName': clinicName,
      'clinicAddress': clinicAddress,
      'doctorId': doctorId,
      'visitNumber': visitNumber,
      'visitType': visitType,
      'visitStatus': visitStatus,
      'visitDate': Timestamp.fromDate(visitDate),
      'chiefComplaint': chiefComplaint,
      'symptoms': symptoms,
      'vitals': vitals,
      'examinationNotes': examinationNotes,
      'disease': disease,
      'diagnosis': diagnosis,
      'diseaseCategory': diseaseCategory,
      'prescriptions': prescriptions,
      'clinicalNotes': clinicalNotes,
      'treatmentPlan': treatmentPlan,
      'followUpDate': followUpDate != null ? Timestamp.fromDate(followUpDate!) : null,
      'followUpInstructions': followUpInstructions,
      'consultationFee': consultationFee,
      'medicineFee': medicineFee,
      'totalAmount': totalAmount,
      'billStatus': billStatus,
      'pendingAmount': pendingAmount,
      'paymentMethod': paymentMethod,
      'isLegacyMigration': isLegacyMigration,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'auditTrail': auditTrail,
    };
  }
}
