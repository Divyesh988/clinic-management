import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/clinic_service.dart';
import '../services/doctor_service.dart';
import '../theme/app_colors.dart';
import 'add_patient_screen.dart';
import 'add_visit_screen.dart';
import 'clinic_form_sheet.dart';
import 'patient_ehr_screen.dart';
import '../services/ehr_service.dart';

class patients extends StatefulWidget {
  const patients({super.key});

  @override
  State<patients> createState() => _patientsState();
}

class _patientsState extends State<patients> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0;
  String _searchQuery = '';
  List<Map<String, dynamic>>? _patientsList;
  List<Map<String, dynamic>> get _currentPatients => _patientsList ??= [];

  StreamSubscription<QuerySnapshot>? _patientsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _clinicsSubscription;
  bool _isLoading = false;
  bool _isCloudConnected = false;
  final Set<String> _selectedPatientIds = {};
  bool _isSelectionMode = false;

  // Clinic Filter State
  String _selectedClinicFilter = 'All';
  List<Map<String, dynamic>> _availableClinics = [];

  // Date Range Filter State
  DateTimeRange? _selectedDateRange;
  String _selectedDatePreset = 'All Time';

  static String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    return '$day $month ${dt.year}';
  }

  static String _formatShortDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = dt.day.toString();
    final month = months[dt.month - 1];
    return '$day $month';
  }

  static Map<String, dynamic> _normalizePatient(Map<String, dynamic> raw, [String? docId]) {
    final name = raw['name']?.toString() ?? 'Unnamed Patient';
    final rawInitials = raw['initials']?.toString();
    final initials = (rawInitials != null && rawInitials.isNotEmpty)
        ? rawInitials
        : name.split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() : '').take(2).join();

    final billStatus = raw['billStatus']?.toString() ?? 'Pending';
    final totalBilled = (raw['totalBilled'] as num?)?.toInt() ??
        ((raw['totalAmount'] as num?)?.toInt() ?? 0);
    final pendingAmount = (raw['pendingAmount'] as num?)?.toInt() ??
        (billStatus == 'Paid' ? 0 : totalBilled);

    final rawMeds = raw['medicines'];
    final List<Map<String, dynamic>> parsedMedicines = [];
    if (rawMeds is List) {
      for (final item in rawMeds) {
        if (item is Map) {
          parsedMedicines.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final medSummary = parsedMedicines.isNotEmpty
        ? parsedMedicines.map((m) {
            final medName = m['name']?.toString() ?? '';
            final dose = m['dosage']?.toString() ?? '';
            return dose.isNotEmpty ? '$medName ($dose)' : medName;
          }).where((s) => s.trim().isNotEmpty).join(', ')
        : (raw['recentRx']?.toString() ?? 'None Prescribed');

    DateTime? recordDate;
    final rawCreatedAt = raw['createdAt'];
    if (rawCreatedAt is Timestamp) {
      recordDate = rawCreatedAt.toDate();
    } else if (rawCreatedAt is DateTime) {
      recordDate = rawCreatedAt;
    } else if (rawCreatedAt is String) {
      recordDate = DateTime.tryParse(rawCreatedAt);
    }

    if (recordDate == null) {
      final lv = raw['lastVisit']?.toString().trim() ?? '';
      if (lv.toLowerCase().contains('today') || lv.toLowerCase().contains('just now')) {
        recordDate = DateTime.now();
      } else {
        final parts = lv.split(' ');
        if (parts.length >= 3) {
          final day = int.tryParse(parts[0]);
          final months = {
            'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
            'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
          };
          final mStr = parts[1].toLowerCase();
          final month = months[mStr.length >= 3 ? mStr.substring(0, 3) : mStr];
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            recordDate = DateTime(year, month, day);
          }
        }
      }
    }
    recordDate ??= DateTime.now();

    return {
      'id': raw['id']?.toString() ?? docId ?? 'PT-00000',
      'docId': docId ?? raw['docId']?.toString() ?? '',
      'name': name,
      'initials': initials.isEmpty ? 'PT' : initials,
      'age': (raw['age'] as num?)?.toInt() ?? 30,
      'gender': raw['gender']?.toString() ?? 'Other',
      'phone': raw['phone']?.toString() ?? '+91 00000 00000',
      'address': raw['address']?.toString() ?? 'Gujarat, India',
      'email': raw['email']?.toString() ?? '',
      'bloodGroup': raw['bloodGroup']?.toString() ?? 'B+',
      'clinic': raw['clinic']?.toString() ?? 'Sunrise Clinic',
      'clinicId': raw['clinicId']?.toString() ?? '',
      'clinicAddress': raw['clinicAddress']?.toString() ?? '',
      'lastVisit': raw['lastVisit']?.toString() ?? 'Recent',
      'disease': raw['disease']?.toString() ?? 'General Consultation',
      'diagnosis': raw['diagnosis']?.toString() ?? 'Under Review',
      'totalVisits': (raw['totalVisits'] as num?)?.toInt() ?? 1,
      'billStatus': billStatus,
      'pendingAmount': pendingAmount,
      'totalBilled': totalBilled,
      'lastBillDate': raw['lastBillDate']?.toString() ?? 'Recent',
      'allergies': raw['allergies']?.toString() ?? 'No known drug allergies',
      'recentRx': medSummary,
      'medicines': parsedMedicines,
      'paymentMethod': raw['paymentMethod']?.toString() ?? 'UPI',
      'recordDate': recordDate,
      'createdAt': raw['createdAt'],
    };
  }



  @override
  void initState() {
    super.initState();
    _patientsList = [];
    _selectedFilterIndex = 0;
    _searchQuery = '';
    _initClinicsStream();
    _initFirestoreStream();
    DoctorService.activeDoctorNotifier.addListener(_onDoctorChanged);
    EhrService.migrateLegacyPatients();
  }

  void _onDoctorChanged() {
    if (!mounted) return;
    _clinicsSubscription?.cancel();
    _patientsSubscription?.cancel();
    _initClinicsStream();
    _initFirestoreStream();
  }

  void _initClinicsStream() {
    try {
      _clinicsSubscription = ClinicService.streamDoctorClinics().listen((clinics) {
        if (!mounted) return;
        setState(() {
          _availableClinics = clinics;
        });
      }, onError: (err) {
        debugPrint('Clinics stream error: $err');
      });
    } catch (e) {
      debugPrint('Clinics stream setup error: $e');
    }
  }

  bool _isPatientOwnedByCurrentDoctor(Map<String, dynamic> patient) {
    final pDocId = patient['doctorId']?.toString();
    if (pDocId != null && pDocId.isNotEmpty) {
      return pDocId == DoctorService.currentDoctorId;
    }
    // If legacy patient record has no doctorId, match clinicId or clinic name against the doctor's verified clinics
    final pClinicId = patient['clinicId']?.toString() ?? '';
    final pClinicName = (patient['clinic']?.toString() ?? '').trim().toLowerCase();
    if (pClinicId.isNotEmpty && _availableClinics.any((c) => c['docId'] == pClinicId)) {
      return true;
    }
    if (pClinicName.isNotEmpty && _availableClinics.any((c) => (c['name']?.toString() ?? '').trim().toLowerCase() == pClinicName)) {
      return true;
    }
    return false;
  }

  bool _matchesClinicFilter(Map<String, dynamic> patient, String filter) {
    if (filter == 'All' || filter == 'All My Clinics') return true;
    final cleanFilter = filter.trim();
    final pClinicId = (patient['clinicId']?.toString() ?? '').trim();
    final pClinicName = (patient['clinic']?.toString() ?? '').trim();

    // Direct match on clinic docId
    if (pClinicId.isNotEmpty && pClinicId == cleanFilter) {
      return true;
    }

    // Direct match on clinic name
    if (pClinicName.isNotEmpty && pClinicName.toLowerCase() == cleanFilter.toLowerCase()) {
      return true;
    }

    // Match via _availableClinics metadata
    for (final clinic in _availableClinics) {
      final cName = (clinic['name']?.toString() ?? '').trim().toLowerCase();
      final cDocId = (clinic['docId']?.toString() ?? '').trim();
      if (cDocId == cleanFilter || cName == cleanFilter.toLowerCase()) {
        if ((pClinicId.isNotEmpty && pClinicId == cDocId) ||
            (pClinicName.isNotEmpty && pClinicName.toLowerCase() == cName)) {
          return true;
        }
      }
    }

    return false;
  }

  void _initFirestoreStream() {
    setState(() => _isLoading = true);
    try {
      _patientsSubscription = FirebaseFirestore.instance
          .collection('patients')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        final List<Map<String, dynamic>> cloudPatients = [];
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final normalized = _normalizePatient(data, doc.id);
          if (_isPatientOwnedByCurrentDoctor(normalized)) {
            cloudPatients.add(normalized);
          }
        }

        _sortAndSetPatients(cloudPatients);
      }, onError: (error) {
        debugPrint('Firestore stream error: $error');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isCloudConnected = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Firestore stream setup error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isCloudConnected = false;
        });
      }
    }
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _selectedDatePreset = preset;
      if (preset == 'All Time') {
        _selectedDateRange = null;
      } else if (preset == 'Today') {
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        _selectedDateRange = DateTimeRange(start: start, end: end);
      } else if (preset == 'Yesterday') {
        final yest = now.subtract(const Duration(days: 1));
        final start = DateTime(yest.year, yest.month, yest.day);
        final end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
        _selectedDateRange = DateTimeRange(start: start, end: end);
      } else if (preset == 'Last 7 Days') {
        final start = now.subtract(const Duration(days: 7));
        _selectedDateRange = DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      } else if (preset == 'This Month') {
        final start = DateTime(now.year, now.month, 1);
        _selectedDateRange = DateTimeRange(
          start: start,
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      }
    });
    fetchpatient();
  }

  Future<void> _selectCustomDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _selectedDatePreset = 'Custom';
      });
      fetchpatient();
    }
  }

  void _sortAndSetPatients(List<Map<String, dynamic>> cloudPatients) {
    cloudPatients.sort((a, b) {
      final aDate = a['recordDate'] as DateTime?;
      final bDate = b['recordDate'] as DateTime?;
      if (aDate != null && bDate != null) {
        return bDate.compareTo(aDate);
      }
      return (b['id']?.toString() ?? '').compareTo(a['id']?.toString() ?? '');
    });

    setState(() {
      _patientsList = cloudPatients;
      _isLoading = false;
      _isCloudConnected = true;
    });
  }

  Future<void> fetchpatient() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance.collection('patients').get();
      if (!mounted) return;
      if (snapshot.docs.isNotEmpty) {
        final List<Map<String, dynamic>> cloudPatients = [];
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          cloudPatients.add(_normalizePatient(data, doc.id));
        }

        _sortAndSetPatients(cloudPatients);
      } else {
        setState(() {
          _isLoading = false;
          _isCloudConnected = true;
        });
      }
    } catch (e) {
      debugPrint('fetchpatient error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isCloudConnected = false;
        });
      }
    }
  }

  @override
  void dispose() {
    DoctorService.activeDoctorNotifier.removeListener(_onDoctorChanged);
    _patientsSubscription?.cancel();
    _clinicsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddPatientScreen() async {
    // 1. Authoritative check: Check if clinics exist in Firestore for current doctor
    try {
      final doctorClinics = await ClinicService.getDoctorClinics();
      if (doctorClinics.isEmpty) {
        if (!mounted) return;
        // Block access and show "Clinic Setup Required" dialog
        final shouldAdd = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Clinic Setup Required',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            content: const Text(
              'You must configure at least one clinic location before adding patient records. Patients must be assigned to an active clinic branch for clinical records and billing.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.add_location_alt_rounded, size: 16, color: Colors.white),
                label: const Text('Add Clinic', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        );

        if (shouldAdd == true && mounted) {
          final newClinic = await showAddEditClinicSheet(context);
          if (newClinic != null && mounted) {
            // Verify write in Firestore before continuing
            final clinicDocId = newClinic['docId']?.toString() ?? '';
            final verifiedClinic = await ClinicService.getClinicById(clinicDocId);

            if (verifiedClinic != null && mounted) {
              // Proceed to AddPatientScreen with preselected clinic
              final newPatient = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (context) => AddPatientScreen(
                    initialClinicId: clinicDocId,
                    initialClinicName: newClinic['name']?.toString(),
                    initialConsultationFee: (newClinic['consultationFee'] as num?)?.toDouble(),
                  ),
                ),
              );

              if (newPatient != null && mounted) {
                final normalized = _normalizePatient(newPatient);
                setState(() {
                  final exists = _currentPatients.any((p) => p['id'] == normalized['id']);
                  if (!exists) {
                    _currentPatients.insert(0, normalized);
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Patient record for ${normalized['name']} stored digitally!'),
                        ),
                      ],
                    ),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          }
        }
        return;
      }
    } catch (e) {
      debugPrint('Error verifying clinics before adding patient: $e');
    }

    if (!mounted) return;

    final newPatient = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const AddPatientScreen()),
    );

    if (newPatient != null && mounted) {
      final normalized = _normalizePatient(newPatient);
      setState(() {
        final exists = _currentPatients.any((p) => p['id'] == normalized['id']);
        if (!exists) {
          _currentPatients.insert(0, normalized);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Patient record for ${normalized['name']} stored digitally!'),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSingle(Map<String, dynamic> patient) async {
    final name = patient['name']?.toString() ?? 'Patient';
    final id = patient['id']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Patient?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                children: [
                  const TextSpan(text: 'Are you sure you want to permanently delete '),
                  TextSpan(
                    text: '$name ($id)',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const TextSpan(
                    text: ' from the clinic database? All consultation, prescription, and billing records will be erased.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone.',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16, color: Colors.white),
            label: const Text('Delete Patient', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePatients([id]);
    }
  }

  Future<void> _confirmBulkDelete() async {
    if (_selectedPatientIds.isEmpty) return;
    final count = _selectedPatientIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete $count Patients?',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete $count selected patient record(s) from Cloud Firestore database?',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All associated prescription and billing entries for these patients will be permanently lost.',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_sweep_rounded, size: 17, color: Colors.white),
            label: Text('Delete ($count)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deletePatients(_selectedPatientIds.toList());
    }
  }

  Future<void> _deletePatients(List<String> ids) async {
    if (ids.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in ids) {
        if (id.isEmpty) continue;
        final match = _currentPatients.firstWhere(
          (p) => p['id'] == id || p['docId'] == id,
          orElse: () => {'id': id, 'docId': id},
        );
        final targetDocId = (match['docId']?.toString().isNotEmpty ?? false)
            ? match['docId']!.toString()
            : match['id']!.toString();
        final docRef = FirebaseFirestore.instance.collection('patients').doc(targetDocId);
        batch.delete(docRef);
      }
      await batch.commit();

      if (mounted) {
        setState(() {
          _patientsList?.removeWhere((p) => ids.contains(p['id']) || ids.contains(p['docId']));
          _selectedPatientIds.clear();
          _isSelectionMode = false;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ids.length == 1
                        ? 'Patient record deleted from database.'
                        : '${ids.length} patient records deleted from database.',
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting patients: $e');
      if (mounted) {
        setState(() {
          _patientsList?.removeWhere((p) => ids.contains(p['id']) || ids.contains(p['docId']));
          _selectedPatientIds.clear();
          _isSelectionMode = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Record removed locally ($e)'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPatients {
    return _currentPatients.where((patient) {
      final name = (patient['name']?.toString() ?? '').toLowerCase();
      final phone = (patient['phone']?.toString() ?? '').toLowerCase();
      final id = (patient['id']?.toString() ?? '').toLowerCase();
      final disease = (patient['disease']?.toString() ?? '').toLowerCase();
      final diagnosis = (patient['diagnosis']?.toString() ?? '').toLowerCase();
      final clinic = (patient['clinic']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();

      final matchesQuery = query.isEmpty ||
          name.contains(query) ||
          phone.contains(query) ||
          id.contains(query) ||
          disease.contains(query) ||
          diagnosis.contains(query) ||
          clinic.contains(query);

      if (!matchesQuery) return false;

      // Clinic-wise filter
      if (!_matchesClinicFilter(patient, _selectedClinicFilter)) {
        return false;
      }

      // Date Range filter
      if (_selectedDateRange != null) {
        final rDate = patient['recordDate'] as DateTime?;
        if (rDate != null) {
          final startDay = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final endDay = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59, 999);
          if (rDate.isBefore(startDay) || rDate.isAfter(endDay)) {
            return false;
          }
        }
      }

      final billStatus = patient['billStatus']?.toString() ?? 'Pending';
      if (_selectedFilterIndex == 1) {
        return billStatus == 'Pending' || billStatus == 'Partial' || billStatus == 'Unbilled';
      } else if (_selectedFilterIndex == 2) {
        return billStatus == 'Paid';
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPatients;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(),
                const SizedBox(height: 8),
                _buildSearchBar(),
                const SizedBox(height: 10),
                _buildDateRangeFilterBar(),
                const SizedBox(height: 10),
                _buildFilterChips(),
                if (_selectedClinicFilter != 'All') ...[
                  const SizedBox(height: 6),
                  _buildActiveClinicFilterBanner(),
                ],
                if (_selectedDateRange != null) ...[
                  const SizedBox(height: 6),
                  _buildActiveDateRangeBanner(),
                ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isSelectionMode
                            ? '${_selectedPatientIds.length} of ${filtered.length} Selected'
                            : 'Showing ${filtered.length} Digital Records',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _isSelectionMode ? 'Tap card to toggle selection' : 'Tap Card for Full Details',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading && filtered.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        )
                      : RefreshIndicator(
                          onRefresh: fetchpatient,
                          color: AppColors.primary,
                          backgroundColor: Colors.white,
                          child: filtered.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  children: [
                                    const SizedBox(height: 60),
                                    _buildEmptyState(),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                                  itemCount: filtered.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final patient = filtered[index];
                                    return _buildPatientCard(patient);
                                  },
                                ),
                        ),
                ),
              ],
            ),

            // Bottom Dual Floating Action Buttons / Bulk Delete Action Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: _isSelectionMode
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C1E28),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isSelectionMode = false;
                                  _selectedPatientIds.clear();
                                });
                              },
                              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                              label: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ),
                            Container(width: 1, height: 20, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 6)),
                            ElevatedButton.icon(
                              onPressed: _selectedPatientIds.isEmpty ? null : _confirmBulkDelete,
                              icon: const Icon(Icons.delete_rounded, size: 16, color: Colors.white),
                              label: Text(
                                _selectedPatientIds.isEmpty
                                    ? 'Select to Delete'
                                    : 'Delete Selected (${_selectedPatientIds.length})',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                disabledBackgroundColor: const Color(0xFF475569),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Primary Add Patient Button
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _openAddPatientScreen,
                              icon: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Add Patient',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Add Bill Button
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryContainer.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddBillModal(context, null),
                              icon: const Icon(
                                Icons.receipt_long_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Add Bill',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryContainer,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TOP APP BAR
  // ==========================================
  Widget _buildTopBar() {
    if (_isSelectionMode) {
      final allFilteredIds = _filteredPatients
          .map((p) => p['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final isAllSelected = allFilteredIds.isNotEmpty && _selectedPatientIds.containsAll(allFilteredIds);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFF0C1E28),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
              tooltip: 'Exit Selection Mode',
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedPatientIds.clear();
                });
              },
            ),
            const SizedBox(width: 4),
            Text(
              '${_selectedPatientIds.length} Selected',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (isAllSelected) {
                    _selectedPatientIds.clear();
                  } else {
                    _selectedPatientIds.addAll(allFilteredIds);
                  }
                });
              },
              icon: Icon(
                isAllSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                color: Colors.white70,
                size: 16,
              ),
              label: Text(
                isAllSelected ? 'Deselect All' : 'Select All',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: _selectedPatientIds.isEmpty ? null : _confirmBulkDelete,
              icon: Icon(
                Icons.delete_sweep_rounded,
                color: _selectedPatientIds.isEmpty ? Colors.white38 : const Color(0xFFF87171),
                size: 22,
              ),
              tooltip: 'Delete Selected Patients',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: ClinicService.streamDoctorClinics(),
            builder: (context, snapshot) {
              final clinics = snapshot.data ?? _availableClinics;

              // Sync _availableClinics from stream without setState during build
              if (snapshot.hasData && snapshot.data!.length != _availableClinics.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _availableClinics = snapshot.data!);
                });
              }

              String pillLabel;
              if (_selectedClinicFilter == 'All' || _selectedClinicFilter == 'All My Clinics') {
                pillLabel = 'All My Clinics';
              } else {
                final matched = clinics.firstWhere(
                  (c) => c['docId'] == _selectedClinicFilter || c['name'] == _selectedClinicFilter,
                  orElse: () => <String, dynamic>{},
                );
                pillLabel = matched.isNotEmpty
                    ? (matched['name']?.toString() ?? _selectedClinicFilter)
                    : _selectedClinicFilter;
              }

              return InkWell(
                onTap: _showClinicFilterSheet,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_hospital_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          pillLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _isCloudConnected ? const Color(0xFFCCFBF1) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isCloudConnected ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                      size: 13,
                      color: _isCloudConnected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isCloudConnected ? 'Cloud Live' : 'Offline',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _isCloudConnected ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                  });
                },
                tooltip: 'Select Patients',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.checklist_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              IconButton(
                onPressed: fetchpatient,
                tooltip: 'Sync from Firebase',
                visualDensity: VisualDensity.compact,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(
                        Icons.sync_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ACTIVE CLINIC FILTER BANNER
  // ==========================================
  Widget _buildActiveClinicFilterBanner() {
    final count = _filteredPatients.length;

    // Resolve the display name from the available clinics list
    String displayName = _selectedClinicFilter;
    if (_selectedClinicFilter != 'All' && _selectedClinicFilter != 'All My Clinics') {
      final matched = _availableClinics.firstWhere(
        (c) => c['docId'] == _selectedClinicFilter || c['name'] == _selectedClinicFilter,
        orElse: () => <String, dynamic>{},
      );
      if (matched.isNotEmpty) {
        displayName = matched['name']?.toString() ?? _selectedClinicFilter;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFCCFBF1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF99F6E4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.business_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Branch: $displayName ($count patients)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => setState(() => _selectedClinicFilter = 'All'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.close_rounded, size: 12, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CLINIC FILTER BOTTOM SHEET
  // ==========================================
  void _showClinicFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final allCount = _currentPatients.length;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Select Clinic Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Filter patient records by clinical branch',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Option: All My Clinics
                  _buildClinicFilterOption(
                    title: 'All My Clinics',
                    subtitle: 'Show patient records across all my registered clinics',
                    count: allCount,
                    isSelected: _selectedClinicFilter == 'All' || _selectedClinicFilter == 'All My Clinics',
                    onTap: () {
                      setState(() => _selectedClinicFilter = 'All');
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 8),

                  // Display ONLY clinics registered by the current doctor — live via stream
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ClinicService.streamDoctorClinics(),
                    builder: (context, snapshot) {
                      final displayClinics = snapshot.data ?? _availableClinics;

                      if (displayClinics.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No clinics registered yet. Add clinics from Doctor Profile.',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: displayClinics.map((clinic) {
                          final name = clinic['name']?.toString() ?? 'Clinic';
                          final docId = clinic['docId']?.toString() ?? '';
                          final address = clinic['address']?.toString() ?? '';
                          final isPrimary = clinic['isPrimary'] == true;
                          final filterKey = docId.isNotEmpty ? docId : name;
                          final clinicCount = _currentPatients.where((p) => _matchesClinicFilter(p, filterKey)).length;
                          final isSelected = _selectedClinicFilter == filterKey ||
                              _selectedClinicFilter.trim().toLowerCase() == name.trim().toLowerCase();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildClinicFilterOption(
                              title: name + (isPrimary ? ' ★ Primary' : ''),
                              subtitle: address.isNotEmpty ? address : 'Clinic Branch',
                              count: clinicCount,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() => _selectedClinicFilter = filterKey);
                                Navigator.pop(ctx);
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClinicFilterOption({
    required String title,
    required String subtitle,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppColors.primary : const Color(0xFF94A3B8),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count pts',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SEARCH BAR
  // ==========================================
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 21,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Search name, disease, mobile, or ID...',
                  hintStyle: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
            InkWell(
              onTap: () => _showComprehensiveFilterSheet(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (_selectedDateRange != null || _selectedClinicFilter != 'All' || _selectedFilterIndex != 0)
                      ? AppColors.primary
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: (_selectedDateRange != null || _selectedClinicFilter != 'All' || _selectedFilterIndex != 0)
                      ? Colors.white
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DATE RANGE FILTER BAR
  // ==========================================
  Widget _buildDateRangeFilterBar() {
    final presets = ['All Time', 'Today', 'Yesterday', 'Last 7 Days', 'This Month'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Custom Calendar Picker Action
          InkWell(
            onTap: () => _selectCustomDateRange(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _selectedDatePreset == 'Custom' ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedDatePreset == 'Custom' ? AppColors.primary : AppColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 14,
                    color: _selectedDatePreset == 'Custom' ? Colors.white : AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _selectedDatePreset == 'Custom' && _selectedDateRange != null
                        ? '${_formatShortDate(_selectedDateRange!.start)} - ${_formatShortDate(_selectedDateRange!.end)}'
                        : 'Custom Range',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _selectedDatePreset == 'Custom' ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Presets
          ...presets.map((preset) {
            final isSelected = _selectedDatePreset == preset;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => _setDatePreset(preset),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0C1E28) : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C1E28) : AppColors.border,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    preset,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==========================================
  // ACTIVE DATE RANGE BANNER
  // ==========================================
  Widget _buildActiveDateRangeBanner() {
    final count = _filteredPatients.length;
    final startStr = _formatDate(_selectedDateRange!.start);
    final endStr = _formatDate(_selectedDateRange!.end);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Date: $startStr - $endStr ($count records)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D4ED8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => _setDatePreset('All Time'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.close_rounded, size: 12, color: Color(0xFF1D4ED8)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // COMPREHENSIVE FILTER MODAL
  // ==========================================
  void _showComprehensiveFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String tempPreset = _selectedDatePreset;
        DateTimeRange? tempRange = _selectedDateRange;
        String tempClinic = _selectedClinicFilter;
        int tempFilterIndex = _selectedFilterIndex;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Filter Patient Records',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Date range, clinic branch & payment status',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            tempPreset = 'All Time';
                            tempRange = null;
                            tempClinic = 'All';
                            tempFilterIndex = 0;
                          });
                        },
                        child: const Text('Reset All', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                  const Divider(height: 18),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. DATE RANGE
                          const Text(
                            '1. Date Range Filter',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All Time', 'Today', 'Yesterday', 'Last 7 Days', 'This Month'].map((preset) {
                              final isSelected = tempPreset == preset;
                              return ChoiceChip(
                                label: Text(preset),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    final now = DateTime.now();
                                    setModalState(() {
                                      tempPreset = preset;
                                      if (preset == 'All Time') {
                                        tempRange = null;
                                      } else if (preset == 'Today') {
                                        tempRange = DateTimeRange(
                                          start: DateTime(now.year, now.month, now.day),
                                          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
                                        );
                                      } else if (preset == 'Yesterday') {
                                        final yest = now.subtract(const Duration(days: 1));
                                        tempRange = DateTimeRange(
                                          start: DateTime(yest.year, yest.month, yest.day),
                                          end: DateTime(yest.year, yest.month, yest.day, 23, 59, 59),
                                        );
                                      } else if (preset == 'Last 7 Days') {
                                        tempRange = DateTimeRange(
                                          start: now.subtract(const Duration(days: 7)),
                                          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
                                        );
                                      } else if (preset == 'This Month') {
                                        tempRange = DateTimeRange(
                                          start: DateTime(now.year, now.month, 1),
                                          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
                                        );
                                      }
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),

                          // Custom Date Range Picker Card
                          InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                initialDateRange: tempRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  tempRange = picked;
                                  tempPreset = 'Custom';
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: tempPreset == 'Custom' ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: tempPreset == 'Custom' ? AppColors.primary : const Color(0xFFE2E8F0),
                                  width: tempPreset == 'Custom' ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_month_rounded, color: tempPreset == 'Custom' ? AppColors.primary : AppColors.textSecondary, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tempRange != null
                                              ? '${_formatDate(tempRange!.start)}  →  ${_formatDate(tempRange!.end)}'
                                              : 'Tap to select custom date range',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: tempPreset == 'Custom' ? AppColors.primary : AppColors.textPrimary,
                                          ),
                                        ),
                                        const Text('Custom start and end calendar dates', style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 2. CLINIC LOCATION
                          const Text(
                            '2. Clinic / Branch Filter',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: () {
                              final List<String> clinicOptions = ['All'];
                              final Set<String> added = {};
                              for (final c in _availableClinics) {
                                final n = (c['name']?.toString() ?? '').trim();
                                if (n.isNotEmpty && added.add(n.toLowerCase())) {
                                  clinicOptions.add(n);
                                }
                              }

                              return clinicOptions.map((opt) {
                                final isAll = opt == 'All';
                                final isSelected = isAll
                                    ? (tempClinic == 'All' || tempClinic == 'All My Clinics')
                                    : (tempClinic.trim().toLowerCase() == opt.trim().toLowerCase());

                                return ChoiceChip(
                                  label: Text(isAll ? 'All My Clinics' : opt),
                                  selected: isSelected,
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : AppColors.textPrimary,
                                  ),
                                  onSelected: (val) => setModalState(() => tempClinic = isAll ? 'All' : opt),
                                );
                              }).toList();
                            }(),
                          ),
                          const SizedBox(height: 20),

                          // 3. PAYMENT / BILLING STATUS
                          const Text(
                            '3. Billing Status',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildModalChoiceChip('All', 0, tempFilterIndex, (idx) => setModalState(() => tempFilterIndex = idx)),
                              const SizedBox(width: 8),
                              _buildModalChoiceChip('Pending / Due', 1, tempFilterIndex, (idx) => setModalState(() => tempFilterIndex = idx)),
                              const SizedBox(width: 8),
                              _buildModalChoiceChip('Paid In Full', 2, tempFilterIndex, (idx) => setModalState(() => tempFilterIndex = idx)),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedDatePreset = tempPreset;
                          _selectedDateRange = tempRange;
                          _selectedClinicFilter = tempClinic;
                          _selectedFilterIndex = tempFilterIndex;
                        });
                        fetchpatient();
                      },
                      icon: const Icon(Icons.filter_alt_rounded, size: 18, color: Colors.white),
                      label: const Text(
                        'Apply Filters & Fetch Data',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalChoiceChip(String label, int index, int current, ValueChanged<int> onSelected) {
    final isSelected = index == current;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0C1E28) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? const Color(0xFF0C1E28) : const Color(0xFFCBD5E1)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // FILTER CHIPS
  // ==========================================
  Widget _buildFilterChips() {
    // Dynamic counts reflecting current clinic and date range filter
    final baseFiltered = _currentPatients.where((patient) {
      if (!_matchesClinicFilter(patient, _selectedClinicFilter)) {
        return false;
      }
      if (_selectedDateRange != null) {
        final rDate = patient['recordDate'] as DateTime?;
        if (rDate != null) {
          final startDay = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final endDay = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59, 999);
          if (rDate.isBefore(startDay) || rDate.isAfter(endDay)) {
            return false;
          }
        }
      }
      return true;
    }).toList();

    final pendingCount = baseFiltered.where((p) =>
        p['billStatus'] == 'Pending' ||
        p['billStatus'] == 'Partial' ||
        p['billStatus'] == 'Unbilled').length;

    final paidCount = baseFiltered.where((p) => p['billStatus'] == 'Paid').length;

    final filters = [
      {'label': 'All Records', 'count': baseFiltered.length.toString()},
      {'label': 'Pending / Due', 'count': pendingCount.toString()},
      {'label': 'Paid In Full', 'count': paidCount.toString()},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(filters.length, (i) {
          final isSelected = _selectedFilterIndex == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilterIndex = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0C1E28) : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF0C1E28) : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filters[i]['label']!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1E3A4C) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        filters[i]['count']!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ==========================================
  // PATIENT CARD
  // ==========================================
  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final String pId = patient['id']?.toString() ?? '';
    final bool isSelected = _selectedPatientIds.contains(pId);

    final billStatus = patient['billStatus']?.toString() ?? 'Pending';
    final isPending = billStatus == 'Pending' || billStatus == 'Partial' || billStatus == 'Unbilled';

    Color statusBg;
    Color statusText;
    String statusLabel;

    if (billStatus == 'Paid') {
      statusBg = AppColors.successLight;
      statusText = AppColors.successText;
      statusLabel = 'Paid ₹${patient['totalBilled']}';
    } else if (billStatus == 'Partial') {
      statusBg = AppColors.warningLight;
      statusText = AppColors.warningText;
      statusLabel = 'Due ₹${patient['pendingAmount']}';
    } else if (billStatus == 'Unbilled') {
      statusBg = const Color(0xFFE0F2FE);
      statusText = const Color(0xFF0284C7);
      statusLabel = 'Ready to Bill';
    } else {
      statusBg = AppColors.errorLight;
      statusText = AppColors.errorText;
      statusLabel = 'Due ₹${patient['pendingAmount']}';
    }

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0FDFA) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : (isPending ? const Color(0xFFE2E8F0) : AppColors.border),
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            if (_isSelectionMode) {
              setState(() {
                if (_selectedPatientIds.contains(pId)) {
                  _selectedPatientIds.remove(pId);
                  if (_selectedPatientIds.isEmpty) {
                    _isSelectionMode = false;
                  }
                } else {
                  _selectedPatientIds.add(pId);
                }
              });
            } else {
              _showPatientDetailSheet(context, patient);
            }
          },
          onLongPress: () {
            setState(() {
              _isSelectionMode = true;
              if (_selectedPatientIds.contains(pId)) {
                _selectedPatientIds.remove(pId);
                if (_selectedPatientIds.isEmpty) {
                  _isSelectionMode = false;
                }
              } else {
                _selectedPatientIds.add(pId);
              }
            });
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primarySurface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isSelectionMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 10, top: 10),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? AppColors.primary : const Color(0xFF94A3B8),
                          size: 22,
                        ),
                      ),
                    ],
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFCCFBF1)
                            : (isPending ? const Color(0xFFF1F5F9) : const Color(0xFFE0F2FE)),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          patient['initials']?.toString() ?? 'PT',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? AppColors.primary
                                : (isPending ? const Color(0xFF334155) : const Color(0xFF0284C7)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  patient['name']?.toString() ?? 'Patient',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${patient['age']} ${patient['gender'].toString().substring(0, 1)} • ${patient['bloodGroup']}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${patient['id']} • ${patient['phone']}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (patient['disease'] != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Disease: ${patient['disease']}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          () {
                            final List meds = (patient['medicines'] is List) ? (patient['medicines'] as List) : [];
                            final String rxSummary = meds.isNotEmpty
                                ? meds.map((m) {
                                    final name = m['name']?.toString() ?? '';
                                    final dose = m['dosage']?.toString() ?? '';
                                    return dose.isNotEmpty ? '$name ($dose)' : name;
                                  }).where((s) => s.trim().isNotEmpty).join(', ')
                                : (patient['recentRx']?.toString() ?? '');

                            if (rxSummary.isNotEmpty &&
                                rxSummary != 'None Prescribed' &&
                                rxSummary != 'No medicines recorded') {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFDCFCE7)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.medication_rounded, size: 12, color: Color(0xFF16A34A)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Rx: $rxSummary',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF15803D),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }(),
                        ],
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.borderSubtle),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.storefront_rounded, size: 12, color: AppColors.primary),
                                const SizedBox(width: 3),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 140),
                                  child: Text(
                                    patient['clinic']?.toString() ?? 'Clinic',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.history_rounded,
                                  size: 13,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    (patient['lastVisit'] != null &&
                                     patient['lastVisit'] != 'Recent' &&
                                     patient['lastVisit'] != 'Today, Just now')
                                        ? patient['lastVisit'].toString()
                                        : (patient['recordDate'] is DateTime
                                            ? _formatDate(patient['recordDate'] as DateTime)
                                            : (patient['lastVisit']?.toString() ?? 'Recent')),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (!_isSelectionMode) ...[
                          InkWell(
                            onTap: () => _confirmDeleteSingle(patient),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.delete_outline_rounded, size: 14.5, color: AppColors.error),
                                  SizedBox(width: 3),
                                  Text(
                                    'Delete',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddVisitScreen(patient: patient),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.add, size: 13, color: AppColors.primary),
                                SizedBox(width: 2),
                                Text(
                                  'Visit',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PatientEhrScreen(patient: patient),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            child: Row(
                              children: const [
                                Text(
                                  'EHR',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // EMPTY STATE
  // ==========================================
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_search_rounded,
                size: 32,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Patient Records Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'No matches found. You can add a new digital patient record right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openAddPatientScreen,
              icon: const Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
              label: const Text('Add Patient Digitally',style: TextStyle(color: Colors.white),),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DETAILED PATIENT BOTTOM SHEET
  // ==========================================
  void _showPatientDetailSheet(BuildContext context, Map<String, dynamic> patient) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final hasPending = ((patient['pendingAmount'] as num?) ?? 0) > 0;

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: Color(0xFFCCFBF1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            patient['initials']?.toString() ?? 'PT',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patient['name']?.toString() ?? 'Patient',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${patient['age']} Years • ${patient['gender']} • Blood: ${patient['bloodGroup']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${patient['id']} • Clinic: ${patient['clinic']}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: AppColors.border),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Contact & Address Details
                      Row(
                        children: [
                          Expanded(
                            child: _buildDetailTile(
                              icon: Icons.phone_outlined,
                              title: 'Mobile Number',
                              value: patient['phone']?.toString() ?? 'N/A',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDetailTile(
                              icon: Icons.bloodtype_outlined,
                              title: 'Blood Group',
                              value: patient['bloodGroup']?.toString() ?? 'N/A',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDetailTile(
                        icon: Icons.location_on_outlined,
                        title: 'Residential Address',
                        value: patient['address']?.toString() ?? 'Ahmedabad, Gujarat',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDetailTile(
                              icon: Icons.local_hospital_outlined,
                              title: 'Clinic Branch',
                              value: patient['clinic']?.toString() ?? 'Sunrise Clinic',
                            ),
                          ),
                          if ((patient['clinicAddress']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDetailTile(
                                icon: Icons.map_outlined,
                                title: 'Clinic Address',
                                value: patient['clinicAddress'].toString(),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Disease & Diagnosis Section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'DISEASE & DIAGNOSIS',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  patient['lastVisit']?.toString() ?? 'Recent',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Disease / Complaint: ${patient['disease'] ?? 'General Checkup'}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Doctor Diagnosis: ${patient['diagnosis'] ?? 'Reviewed'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Prescribed Medicines (Type & Dose)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.medication_rounded, size: 16, color: Color(0xFF16A34A)),
                                SizedBox(width: 6),
                                Text(
                                  'PRESCRIBED MEDICINES',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (patient['medicines'] != null &&
                                patient['medicines'] is List &&
                                (patient['medicines'] as List).isNotEmpty)
                              Column(
                                children: (patient['medicines'] as List).map((m) {
                                  final med = Map<String, dynamic>.from(m as Map);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFDCFCE7)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                med['name'] as String? ?? '',
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF14532D),
                                                ),
                                              ),
                                              Text(
                                                '${med['type'] ?? ''} • ${med['duration'] ?? ''}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF15803D),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            med['dosage'] as String? ?? '',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              )
                            else
                              Text(
                                patient['recentRx'] as String? ?? 'No medicines recorded',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF14532D),
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Billing Overview Section
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: hasPending ? const Color(0xFFFCA5A5) : AppColors.border,
                            width: 1.2,
                          ),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'DIGITAL BILLING RECORD',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: hasPending
                                        ? AppColors.errorLight
                                        : AppColors.successLight,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    hasPending ? 'Due / Pending' : 'Paid in Full',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: hasPending
                                          ? AppColors.errorText
                                          : AppColors.successText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildBillStatItem('Total Amount Billed', '₹${patient['totalBilled']}'),
                                _buildBillStatItem('Pending Balance', '₹${patient['pendingAmount']}', isHighlight: hasPending),
                                _buildBillStatItem('Payment Mode', patient['paymentMethod'] ?? 'UPI'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDeleteSingle(patient);
                            },
                            tooltip: 'Delete Patient Record',
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.errorLight,
                              padding: const EdgeInsets.all(12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFFECACA)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PatientEhrScreen(patient: patient),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.history_edu_rounded, size: 17),
                              label: const Text('EHR Timeline'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary, width: 1.2),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AddVisitScreen(patient: patient),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 17, color: Colors.white),
                              label: const Text(
                                '+ New Visit',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAddBillModal(context, patient);
                          },
                          icon: const Icon(Icons.receipt_rounded, size: 17, color: AppColors.primary),
                          label: const Text(
                            'Manage Bill & Payment',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailTile({
    required IconData icon,
    required String title,
    required String value,
    bool isWarning = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: isWarning ? AppColors.error : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isWarning ? AppColors.error : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBillStatItem(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: isHighlight ? AppColors.error : AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // ADD BILL MODAL BOTTOM SHEET
  // ==========================================
  void _showAddBillModal(BuildContext context, Map<String, dynamic>? preselectedPatient) {
    String selectedPatientName = preselectedPatient != null
        ? preselectedPatient['name']
        : (_currentPatients.isNotEmpty ? _currentPatients.first['name'] : '');

    double consultationFee = 500.0;
    double procedureCharges = 200.0;
    double discount = 0.0;
    String paymentMethod = 'UPI';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final double subtotal = consultationFee + procedureCharges;
            final double total = (subtotal - discount).clamp(0, double.infinity);

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Generate Patient Bill',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Invoice will be recorded under Sunrise Clinic',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Select Patient',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _currentPatients.any((p) => p['name']?.toString() == selectedPatientName)
                              ? selectedPatientName
                              : (_currentPatients.isNotEmpty ? _currentPatients.first['name']?.toString() : null),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          items: _currentPatients.map((p) {
                            final pName = p['name']?.toString() ?? 'Patient';
                            return DropdownMenuItem<String>(
                              value: pName,
                              child: Text(
                                '$pName (${p['id']})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedPatientName = val);
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Consultation Fee (₹)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  '₹${consultationFee.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Procedures / Meds (₹)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  '₹${procedureCharges.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    const Text(
                      'Payment Method',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ['UPI', 'Cash', 'Card', 'Due / Pending'].map((method) {
                        final isSel = paymentMethod == method;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: GestureDetector(
                              onTap: () => setModalState(() => paymentMethod = method),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel ? AppColors.primaryContainer : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    method,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                      color: isSel ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'TOTAL INVOICE AMOUNT',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Subtotal ₹700 - Discount ₹0',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '₹${total.toInt()}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Bill of ₹${total.toInt()} created for $selectedPatientName!'),
                              backgroundColor: AppColors.primary,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                        label: const Text(
                          'Confirm & Generate Receipt',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
