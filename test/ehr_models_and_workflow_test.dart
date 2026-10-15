import 'package:flutter_test/flutter_test.dart';
import 'package:clinic_mangement/services/ehr_models.dart';

void main() {
  group('EHR VisitRecord Model & Serialization Tests', () {
    test('VisitRecord correctly instantiates and calculates billing totals', () {
      final visit = VisitRecord(
        id: 'VS-001',
        patientId: 'PT-10023',
        patientName: 'Ramesh Patel',
        clinicId: 'CLN-001',
        clinicName: 'Sunrise Clinic',
        doctorId: 'doc_main',
        visitNumber: 1,
        visitType: 'Initial Consultation',
        visitDate: DateTime(2026, 10, 10, 10, 30),
        chiefComplaint: 'Fever and throat pain for 3 days',
        symptoms: ['Fever', 'Throat Pain', 'Dry Cough'],
        vitals: {
          'bp': '120/80',
          'pulse': '76',
          'temperature': '100.4',
        },
        disease: 'Acute Pharyngitis',
        diagnosis: 'Bacterial Pharyngitis with mild tonsillar erythema',
        diseaseCategory: 'ENT & Ophthalmology',
        prescriptions: [
          {
            'name': 'Amoxicillin 500mg',
            'type': 'Capsule',
            'dosage': '1-0-1',
            'duration': '5 Days',
            'instructions': 'After meals',
          },
          {
            'name': 'Paracetamol 650mg',
            'type': 'Tablet',
            'dosage': '1-0-1',
            'duration': '3 Days',
            'instructions': 'SOS for fever',
          },
        ],
        consultationFee: 500.0,
        medicineFee: 250.0,
        totalAmount: 750.0,
        billStatus: 'Paid',
        pendingAmount: 0.0,
        paymentMethod: 'UPI',
      );

      expect(visit.id, 'VS-001');
      expect(visit.patientId, 'PT-10023');
      expect(visit.visitNumber, 1);
      expect(visit.totalAmount, 750.0);
      expect(visit.pendingAmount, 0.0);
      expect(visit.prescriptions.length, 2);
      expect(visit.vitals['bp'], '120/80');
      expect(visit.symptoms.length, 3);
    });

    test('VisitRecord.toMap() and VisitRecord.fromMap() roundtrip preserves data fidelity', () {
      final now = DateTime(2026, 10, 12, 14, 0);
      final original = VisitRecord(
        id: 'VS-171299999',
        patientId: 'PT-99881',
        patientName: 'Priya Sharma',
        patientPhone: '+91 98765 43210',
        clinicId: 'CLN-002',
        clinicName: 'City Health Clinic',
        clinicAddress: 'Surat, Gujarat',
        doctorId: 'doc_main',
        visitNumber: 2,
        visitType: 'Follow-up',
        visitStatus: 'Completed',
        visitDate: now,
        chiefComplaint: 'Follow-up for Hypertension',
        symptoms: ['Mild headache'],
        vitals: {'bp': '130/85', 'pulse': '72', 'weight': '64'},
        examinationNotes: 'BP improved since last visit.',
        disease: 'Hypertension',
        diagnosis: 'Essential Hypertension - Controlled',
        diseaseCategory: 'Cardiovascular',
        prescriptions: [
          {
            'name': 'Telmisartan 40mg',
            'type': 'Tablet',
            'dosage': '1-0-0',
            'duration': '30 Days',
          }
        ],
        clinicalNotes: 'Continue low sodium diet.',
        treatmentPlan: 'Re-evaluate in 30 days.',
        followUpDate: now.add(const Duration(days: 30)),
        followUpInstructions: 'Monitor morning BP weekly.',
        consultationFee: 400.0,
        medicineFee: 180.0,
        totalAmount: 580.0,
        billStatus: 'Pending',
        pendingAmount: 580.0,
        paymentMethod: 'Cash',
      );

      final map = original.toMap();
      expect(map['patientId'], 'PT-99881');
      expect(map['visitNumber'], 2);
      expect(map['consultationFee'], 400.0);

      final deserialized = VisitRecord.fromMap(map, 'VS-171299999');
      expect(deserialized.id, 'VS-171299999');
      expect(deserialized.patientName, 'Priya Sharma');
      expect(deserialized.visitNumber, 2);
      expect(deserialized.vitals['bp'], '130/85');
      expect(deserialized.prescriptions.first['name'], 'Telmisartan 40mg');
      expect(deserialized.totalAmount, 580.0);
      expect(deserialized.billStatus, 'Pending');
    });

    test('Multiple visits for same patient preserve distinct clinical histories without overwriting', () {
      final patientId = 'PT-55443';

      final visit1 = VisitRecord(
        id: 'VS-01',
        patientId: patientId,
        patientName: 'Anil Shah',
        clinicId: 'CLN-1',
        clinicName: 'Sunrise Clinic',
        doctorId: 'doc_main',
        visitNumber: 1,
        visitType: 'Initial Consultation',
        visitDate: DateTime(2026, 9, 1),
        chiefComplaint: 'High fasting blood sugar, fatigue',
        disease: 'Type 2 Diabetes Mellitus',
        diagnosis: 'Newly detected Type 2 Diabetes Mellitus',
        prescriptions: [
          {'name': 'Metformin 500mg', 'dosage': '1-0-1', 'duration': '15 Days'}
        ],
        consultationFee: 500.0,
        medicineFee: 150.0,
        totalAmount: 650.0,
      );

      final visit2 = VisitRecord(
        id: 'VS-02',
        patientId: patientId,
        patientName: 'Anil Shah',
        clinicId: 'CLN-1',
        clinicName: 'Sunrise Clinic',
        doctorId: 'doc_main',
        visitNumber: 2,
        visitType: 'Follow-up',
        visitDate: DateTime(2026, 9, 16),
        chiefComplaint: 'Blood sugar check, feeling energetic',
        disease: 'Type 2 Diabetes Mellitus',
        diagnosis: 'Type 2 Diabetes Mellitus - Glycemic control improving',
        prescriptions: [
          {'name': 'Metformin 500mg', 'dosage': '1-0-1', 'duration': '30 Days'},
          {'name': 'Glimepiride 1mg', 'dosage': '1-0-0', 'duration': '30 Days'},
        ],
        consultationFee: 300.0,
        medicineFee: 280.0,
        totalAmount: 580.0,
      );

      final visits = [visit1, visit2];
      visits.sort((a, b) => b.visitDate.compareTo(a.visitDate));

      // 1. Visit #2 is newest
      expect(visits.first.id, 'VS-02');
      expect(visits.first.visitNumber, 2);
      expect(visits.first.prescriptions.length, 2);

      // 2. Visit #1 retains historical prescription and does not reflect Visit #2's changes
      expect(visits.last.id, 'VS-01');
      expect(visits.last.visitNumber, 1);
      expect(visits.last.prescriptions.length, 1);
      expect(visits.last.diagnosis, 'Newly detected Type 2 Diabetes Mellitus');
    });

    test('Audit trail preserves modification history on finalized visits', () {
      final visit = VisitRecord(
        id: 'VS-AUDIT-01',
        patientId: 'PT-1234',
        patientName: 'Kavita Dave',
        clinicId: 'CLN-01',
        clinicName: 'Sunrise Clinic',
        doctorId: 'doc_main',
        visitNumber: 1,
        visitDate: DateTime(2026, 10, 1),
        diagnosis: 'Acute Gastritis',
        auditTrail: [
          {
            'timestamp': DateTime(2026, 10, 2),
            'modifiedBy': 'doc_main',
            'reason': 'Corrected typographical error in clinical notes',
            'previousValues': {'examinationNotes': 'Epigastric tenderness mild'},
          }
        ],
      );

      expect(visit.auditTrail.length, 1);
      expect(visit.auditTrail.first['reason'], 'Corrected typographical error in clinical notes');
      expect(visit.auditTrail.first['modifiedBy'], 'doc_main');
    });
  });
}
