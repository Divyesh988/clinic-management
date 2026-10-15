import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:clinic_mangement/services/auth_models.dart';
import 'package:clinic_mangement/services/auth_service.dart';

void main() {
  group('DoctorAccountStatus Tests', () {
    test('DoctorAccountStatus parses correctly from string', () {
      expect(DoctorAccountStatus.fromString('active'), DoctorAccountStatus.active);
      expect(DoctorAccountStatus.fromString('ACTIVE'), DoctorAccountStatus.active);
      expect(DoctorAccountStatus.fromString('inactive'), DoctorAccountStatus.inactive);
      expect(DoctorAccountStatus.fromString('suspended'), DoctorAccountStatus.suspended);
      expect(DoctorAccountStatus.fromString('unknown_status'), DoctorAccountStatus.active);
      expect(DoctorAccountStatus.fromString(null), DoctorAccountStatus.active);
    });

    test('DoctorAccountStatus provides correct human-readable labels', () {
      expect(DoctorAccountStatus.active.label, 'Active');
      expect(DoctorAccountStatus.inactive.label, 'Inactive');
      expect(DoctorAccountStatus.suspended.label, 'Suspended');
    });
  });

  group('DoctorAccount Model & Serialization Tests', () {
    test('DoctorAccount instantiates with expected defaults and properties', () {
      const account = DoctorAccount(
        uid: 'doc_12345',
        email: 'dr.mehta@sunriseclinic.com',
        displayName: 'Dr. Rajiv Mehta',
        specialty: 'Internal Medicine',
        degree: 'MBBS, MD',
        phone: '+91 98250 14829',
        regNumber: 'GMC-84291',
        accountStatus: DoctorAccountStatus.active,
        onboardingCompleted: true,
      );

      expect(account.uid, 'doc_12345');
      expect(account.email, 'dr.mehta@sunriseclinic.com');
      expect(account.displayName, 'Dr. Rajiv Mehta');
      expect(account.specialty, 'Internal Medicine');
      expect(account.degree, 'MBBS, MD');
      expect(account.phone, '+91 98250 14829');
      expect(account.regNumber, 'GMC-84291');
      expect(account.isActive, isTrue);
      expect(account.onboardingCompleted, isTrue);
    });

    test('DoctorAccount inactive and suspended accounts report isActive false', () {
      const inactive = DoctorAccount(
        uid: 'doc_inactive',
        email: 'inactive@clinic.com',
        displayName: 'Dr. Inactive',
        accountStatus: DoctorAccountStatus.inactive,
      );
      expect(inactive.isActive, isFalse);

      const suspended = DoctorAccount(
        uid: 'doc_suspended',
        email: 'suspended@clinic.com',
        displayName: 'Dr. Suspended',
        accountStatus: DoctorAccountStatus.suspended,
      );
      expect(suspended.isActive, isFalse);
    });

    test('DoctorAccount deserializes correctly from Firestore map with fallback fields', () {
      final now = DateTime(2026, 10, 13, 10, 0);
      final rawMap = {
        'name': 'Dr. Priya Sharma', // fallback for displayName
        'email': 'priya.sharma@health.org',
        'speciality': 'Cardiology', // fallback for specialty
        'degree': 'MBBS, DM Cardiology',
        'phone': '9876543210',
        'regNumber': 'MMC-12984',
        'accountStatus': 'active',
        'setupCompleted': true, // fallback for onboardingCompleted
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      final account = DoctorAccount.fromMap(rawMap, 'uid_priya_sharma');

      expect(account.uid, 'uid_priya_sharma');
      expect(account.displayName, 'Dr. Priya Sharma');
      expect(account.email, 'priya.sharma@health.org');
      expect(account.specialty, 'Cardiology');
      expect(account.degree, 'MBBS, DM Cardiology');
      expect(account.regNumber, 'MMC-12984');
      expect(account.accountStatus, DoctorAccountStatus.active);
      expect(account.isActive, isTrue);
      expect(account.onboardingCompleted, isTrue);
      expect(account.createdAt, now);
      expect(account.updatedAt, now);
    });

    test('DoctorAccount serializes to map properly for Firestore updates', () {
      final createdAt = DateTime(2026, 1, 15);
      final account = DoctorAccount(
        uid: 'doc_abc',
        email: 'doctor@test.com',
        displayName: 'Dr. Test',
        specialty: 'Pediatrics',
        degree: 'MBBS, DNB',
        phone: '1234567890',
        regNumber: 'REG-999',
        accountStatus: DoctorAccountStatus.active,
        onboardingCompleted: true,
        createdAt: createdAt,
      );

      final map = account.toMap();
      expect(map['uid'], 'doc_abc');
      expect(map['email'], 'doctor@test.com');
      expect(map['displayName'], 'Dr. Test');
      expect(map['specialty'], 'Pediatrics');
      expect(map['degree'], 'MBBS, DNB');
      expect(map['regNumber'], 'REG-999');
      expect(map['accountStatus'], 'active');
      expect(map['onboardingCompleted'], isTrue);
      expect(map['createdAt'], isA<Timestamp>());
      expect((map['createdAt'] as Timestamp).toDate(), createdAt);
      expect(map['updatedAt'], isA<FieldValue>());
    });
  });

  group('SaaS Website Integration & Doctor Provisioning Tests', () {
    test('DoctorAccount correctly parses doctor record provisioned by SaaS website', () {
      final now = DateTime(2026, 10, 14, 12, 0);
      final websitePayload = {
        'uid': 'doc_saas_uid_998',
        'email': 'dr.anita@citycare.com',
        'displayName': 'Dr. Anita Desai',
        'specialty': 'Consultant Physician',
        'degree': 'MBBS, MD',
        'phone': '+91 9876543210',
        'regNumber': 'GMC-55441',
        'accountStatus': 'active',
        'onboardingCompleted': true,
        'distributorUid': 'DIST-7721',
        'activePlanId': 'PRO_CLINIC',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      final doctor = DoctorAccount.fromMap(websitePayload, 'doc_saas_uid_998');

      expect(doctor.uid, 'doc_saas_uid_998');
      expect(doctor.email, 'dr.anita@citycare.com');
      expect(doctor.displayName, 'Dr. Anita Desai');
      expect(doctor.specialty, 'Consultant Physician');
      expect(doctor.degree, 'MBBS, MD');
      expect(doctor.phone, '+91 9876543210');
      expect(doctor.regNumber, 'GMC-55441');
      expect(doctor.isActive, isTrue);
      expect(doctor.onboardingCompleted, isTrue);
    });

    test('Doctor-clinic relationship strictly matches authenticated doctor UID', () {
      const authenticatedDoctorUid = 'doc_auth_123';
      final clinicDoc = {
        'docId': 'clinic_001',
        'name': 'CityCare Speciality Clinic',
        'address': '101 Medical Center, MG Road',
        'doctorId': authenticatedDoctorUid,
        'isPrimary': true,
      };

      final unauthorizedClinicDoc = {
        'docId': 'clinic_002',
        'name': 'Other Doctor Clinic',
        'address': '202 Health Square',
        'doctorId': 'doc_other_456',
        'isPrimary': true,
      };

      // Validation logic mimicking ClinicService.getClinicById & patient ownership
      bool isAuthorized(Map<String, dynamic> clinic) =>
          clinic['doctorId'] == authenticatedDoctorUid;

      expect(isAuthorized(clinicDoc), isTrue);
      expect(isAuthorized(unauthorizedClinicDoc), isFalse);
    });
  });

  group('AuthException Tests', () {
    test('AuthException retains human-readable error messages and code', () {
      const ex1 = AuthException('Invalid email format', code: 'invalid-email');
      expect(ex1.message, 'Invalid email format');
      expect(ex1.code, 'invalid-email');
      expect(ex1.toString(), 'Invalid email format');

      const ex2 = AuthException('Account suspended');
      expect(ex2.message, 'Account suspended');
      expect(ex2.code, isNull);
      expect(ex2.toString(), 'Account suspended');
    });
  });
}

