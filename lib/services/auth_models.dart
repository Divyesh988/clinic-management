import 'package:cloud_firestore/cloud_firestore.dart';

/// Doctor account status in the SaaS platform.
enum DoctorAccountStatus {
  active,
  inactive,
  suspended;

  static DoctorAccountStatus fromString(String? val) {
    if (val == null) return DoctorAccountStatus.inactive;
    switch (val.toLowerCase().trim()) {
      case 'active':
        return DoctorAccountStatus.active;
      case 'suspended':
        return DoctorAccountStatus.suspended;
      case 'inactive':
      case 'closed':
        return DoctorAccountStatus.inactive;
      default:
        // A missing, null, or unrecognized status must never be interpreted as active
        return DoctorAccountStatus.inactive;
    }
  }

  String get label {
    switch (this) {
      case DoctorAccountStatus.active:
        return 'Active';
      case DoctorAccountStatus.inactive:
        return 'Inactive';
      case DoctorAccountStatus.suspended:
        return 'Suspended';
    }
  }
}

/// Strongly typed model representing an authorized Doctor account in `doctors/{uid}`.
class DoctorAccount {
  final String uid;
  final String email;
  final String displayName;
  final String specialty;
  final String degree;
  final String phone;
  final String regNumber;
  final DoctorAccountStatus accountStatus;
  final String? suspensionReason;
  final bool onboardingCompleted;
  final bool mustChangePassword;
  final String? distributorUid;
  final String? activePlanId;
  final String? subscriptionStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DoctorAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    this.specialty = 'General Physician',
    this.degree = 'MBBS',
    this.phone = '',
    this.regNumber = '',
    this.accountStatus = DoctorAccountStatus.active,
    this.suspensionReason,
    this.onboardingCompleted = false,
    this.mustChangePassword = false,
    this.distributorUid,
    this.activePlanId,
    this.subscriptionStatus,
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => accountStatus == DoctorAccountStatus.active;
  bool get isSuspended => accountStatus == DoctorAccountStatus.suspended;

  factory DoctorAccount.fromMap(Map<String, dynamic> data, String uid) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return DoctorAccount(
      uid: uid,
      email: data['email']?.toString() ?? '',
      displayName: data['displayName']?.toString() ??
          (data['name']?.toString() ?? 'Dr. Practitioner'),
      specialty: data['specialty']?.toString() ??
          (data['speciality']?.toString() ?? 'Consultant Physician'),
      degree: data['degree']?.toString() ?? 'MBBS',
      phone: data['phone']?.toString() ?? '',
      regNumber: data['regNumber']?.toString() ?? '',
      accountStatus: DoctorAccountStatus.fromString(data['accountStatus']?.toString()),
      suspensionReason: data['suspensionReason']?.toString(),
      onboardingCompleted: data['onboardingCompleted'] == true ||
          data['setupCompleted'] == true,
      mustChangePassword: data['mustChangePassword'] == true,
      distributorUid: data['distributorUid']?.toString(),
      activePlanId: data['activePlanId']?.toString(),
      subscriptionStatus: data['subscriptionStatus']?.toString() ?? 'active',
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'specialty': specialty,
      'degree': degree,
      'phone': phone,
      'regNumber': regNumber,
      'accountStatus': accountStatus.name,
      if (suspensionReason != null) 'suspensionReason': suspensionReason,
      'onboardingCompleted': onboardingCompleted,
      'mustChangePassword': mustChangePassword,
      'distributorUid': distributorUid,
      'activePlanId': activePlanId,
      'subscriptionStatus': subscriptionStatus,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
