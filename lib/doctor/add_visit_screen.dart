import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/clinic_service.dart';
import '../services/ehr_models.dart';
import '../services/ehr_service.dart';
import '../theme/app_colors.dart';

/// Screen allowing the doctor to record a new, independent clinical encounter / visit
/// for an existing patient without overwriting previous visit records.
class AddVisitScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final VisitRecord? previousVisit;

  const AddVisitScreen({
    super.key,
    required this.patient,
    this.previousVisit,
  });

  @override
  State<AddVisitScreen> createState() => _AddVisitScreenState();
}

class _AddVisitScreenState extends State<AddVisitScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _complaintController = TextEditingController();
  final _examNotesController = TextEditingController();
  final _diseaseController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _treatmentPlanController = TextEditingController();
  final _clinicalNotesController = TextEditingController();
  final _followUpInstructionsController = TextEditingController();

  // Vitals Controllers
  final _bpController = TextEditingController();
  final _pulseController = TextEditingController();
  final _tempController = TextEditingController();
  final _weightController = TextEditingController();
  final _spo2Controller = TextEditingController();

  // Billing Controllers
  final _consultFeeController = TextEditingController(text: '500');
  final _medFeeController = TextEditingController(text: '200');

  // Medicine items & inputs
  final List<Map<String, String>> _medicines = [];
  final _medNameController = TextEditingController();
  final _medDosageController = TextEditingController(text: '1-0-1');
  final _medDurationController = TextEditingController(text: '5 Days');
  final _medInstructionsController = TextEditingController(text: 'After meals');
  String _selectedMedType = 'Tablet';

  // Predefined Formulary Search & Filter States
  final _medSearchController = TextEditingController();
  String _medSearchQuery = '';
  String _medFilterType = 'All';
  final List<String> _medFilterOptions = ['All', 'Tablet', 'Syrup', 'Capsule', 'Injection', 'Drops', 'Ointment'];
  bool _showCustomMedForm = false;

  // Selection states
  String _selectedVisitType = 'Follow-up';
  DateTime _selectedVisitDate = DateTime.now();
  DateTime? _selectedFollowUpDate;
  String _selectedDiseaseCategory = 'General & Infectious';
  String _selectedBillStatus = 'Paid';
  String _selectedPaymentMethod = 'UPI';

  // Clinic Selection
  String? _selectedClinicId;
  String _selectedClinicName = '';
  String _selectedClinicAddress = '';
  List<Map<String, dynamic>> _doctorClinics = [];

  bool _isSaving = false;
  VisitRecord? _resolvedPreviousVisit;

  final List<String> _visitTypes = [
    'Follow-up',
    'Initial Consultation',
    'Routine Checkup',
    'Emergency / Urgent',
    'Post-Procedure Review',
  ];

  final List<String> _diseaseCategories = [
    'General & Infectious',
    'Respiratory',
    'Cardiovascular',
    'Endocrine & Metabolic',
    'Gastrointestinal & Digestive',
    'Musculoskeletal & Orthopedic',
    'Dermatology & Skin',
    'ENT & Ophthalmology',
    'Neurology & Psychiatric',
    'Other / Uncategorized',
  ];

  @override
  void initState() {
    super.initState();
    _resolvedPreviousVisit = widget.previousVisit;
    _initClinicsAndDefaults();
    _loadPreviousVisitIfNeeded();
  }

  Future<void> _loadPreviousVisitIfNeeded() async {
    if (_resolvedPreviousVisit == null) {
      final patientId = widget.patient['id']?.toString() ?? widget.patient['docId']?.toString() ?? '';
      if (patientId.isNotEmpty) {
        final last = await EhrService.getLatestVisitForPatient(patientId);
        if (mounted && last != null) {
          setState(() {
            _resolvedPreviousVisit = last;
          });
        }
      }
    }
  }

  Future<void> _initClinicsAndDefaults() async {
    try {
      final clinics = await ClinicService.getDoctorClinics();
      if (!mounted) return;

      setState(() {
        _doctorClinics = clinics;
        final patientClinicId = widget.patient['clinicId']?.toString() ?? '';

        if (patientClinicId.isNotEmpty && clinics.any((c) => c['docId'] == patientClinicId)) {
          final matched = clinics.firstWhere((c) => c['docId'] == patientClinicId);
          _selectedClinicId = matched['docId'];
          _selectedClinicName = matched['name']?.toString() ?? 'Clinic';
          _selectedClinicAddress = matched['address']?.toString() ?? '';
          if (matched['consultationFee'] != null) {
            _consultFeeController.text = matched['consultationFee'].toString();
          }
        } else if (clinics.isNotEmpty) {
          final primary = clinics.firstWhere((c) => c['isPrimary'] == true, orElse: () => clinics.first);
          _selectedClinicId = primary['docId'];
          _selectedClinicName = primary['name']?.toString() ?? 'Clinic';
          _selectedClinicAddress = primary['address']?.toString() ?? '';
          if (primary['consultationFee'] != null) {
            _consultFeeController.text = primary['consultationFee'].toString();
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading clinics in AddVisitScreen: $e');
    }
  }

  @override
  void dispose() {
    _complaintController.dispose();
    _examNotesController.dispose();
    _diseaseController.dispose();
    _diagnosisController.dispose();
    _treatmentPlanController.dispose();
    _clinicalNotesController.dispose();
    _followUpInstructionsController.dispose();
    _bpController.dispose();
    _pulseController.dispose();
    _tempController.dispose();
    _weightController.dispose();
    _spo2Controller.dispose();
    _consultFeeController.dispose();
    _medFeeController.dispose();
    _medNameController.dispose();
    _medDosageController.dispose();
    _medDurationController.dispose();
    _medInstructionsController.dispose();
    _medSearchController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final c = double.tryParse(_consultFeeController.text.trim()) ?? 0.0;
    final m = double.tryParse(_medFeeController.text.trim()) ?? 0.0;
    return c + m;
  }

  void _addMedicine() {
    final name = _medNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a medicine name'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _medicines.add({
        'name': name,
        'type': _selectedMedType,
        'dosage': _medDosageController.text.trim().isEmpty ? '1-0-1' : _medDosageController.text.trim(),
        'duration': _medDurationController.text.trim().isEmpty ? '5 Days' : _medDurationController.text.trim(),
        'instructions': _medInstructionsController.text.trim(),
      });
      _medNameController.clear();
      _medDosageController.text = '1-0-1';
      _medDurationController.text = '5 Days';
    });
  }

  IconData _getMedIcon(String type) {
    switch (type.toLowerCase()) {
      case 'tablet':
        return Icons.medication_rounded;
      case 'syrup':
        return Icons.liquor_rounded;
      case 'capsule':
        return Icons.shield_rounded;
      case 'injection':
        return Icons.vaccines_rounded;
      case 'ointment':
      case 'cream':
        return Icons.healing_rounded;
      case 'drops':
        return Icons.water_drop_rounded;
      case 'inhaler':
        return Icons.air_rounded;
      case 'powder':
        return Icons.grain_rounded;
      default:
        return Icons.medication_rounded;
    }
  }

  void _addPredefinedMedicine(Map<String, dynamic> med, {String? customDosage, String? customDuration, String? customInstructions}) {
    final name = med['name']?.toString().trim() ?? '';
    if (name.isEmpty) return;

    final type = med['type']?.toString().trim() ?? 'Tablet';
    final dosage = customDosage ?? (med['dosage']?.toString().trim() ?? '1-0-1');
    final duration = customDuration ?? (med['duration']?.toString().trim() ?? '5 Days');
    final instructions = customInstructions ?? (med['instructions']?.toString().trim() ?? 'After meals');

    final exists = _medicines.any((m) => m['name']?.toLowerCase() == name.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name is already in the prescription!'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _medicines.add({
        'name': name,
        'type': type,
        'dosage': dosage.isEmpty ? '1-0-1' : dosage,
        'duration': duration.isEmpty ? '5 Days' : duration,
        'instructions': instructions.isEmpty ? 'After meals' : instructions,
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Added $name ($dosage, $duration)')),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCustomizeMedicineDialog(Map<String, dynamic> med, {int? existingIndex}) {
    final name = med['name']?.toString() ?? '';
    final type = med['type']?.toString() ?? 'Tablet';
    final doseCtrl = TextEditingController(text: existingIndex != null ? _medicines[existingIndex]['dosage'] : (med['dosage']?.toString() ?? '1-0-1'));
    final durCtrl = TextEditingController(text: existingIndex != null ? _medicines[existingIndex]['duration'] : (med['duration']?.toString() ?? '5 Days'));
    final instCtrl = TextEditingController(text: existingIndex != null ? _medicines[existingIndex]['instructions'] : (med['instructions']?.toString() ?? 'After meals'));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.medication_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                      Text(type, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dosage Schedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: doseCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. 1-0-1 or 1 Tab BD',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['1-0-0', '1-0-1', '1-1-1', '0-0-1', 'SOS'].map((d) {
                      return ActionChip(
                        label: Text(d, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        onPressed: () => setDialogState(() => doseCtrl.text = d),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('Duration', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: durCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. 5 Days or 1 Month',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['3 Days', '5 Days', '7 Days', '10 Days', '15 Days', '1 Month'].map((d) {
                      return ActionChip(
                        label: Text(d, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        onPressed: () => setDialogState(() => durCtrl.text = d),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('Instructions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: instCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. After meals, with warm water',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['After meals', 'Before meals', 'With milk', 'At bedtime'].map((d) {
                      return ActionChip(
                        label: Text(d, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        onPressed: () => setDialogState(() => instCtrl.text = d),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (existingIndex != null) {
                    setState(() {
                      _medicines[existingIndex]['dosage'] = doseCtrl.text.trim().isEmpty ? '1-0-1' : doseCtrl.text.trim();
                      _medicines[existingIndex]['duration'] = durCtrl.text.trim().isEmpty ? '5 Days' : durCtrl.text.trim();
                      _medicines[existingIndex]['instructions'] = instCtrl.text.trim().isEmpty ? 'After meals' : instCtrl.text.trim();
                    });
                  } else {
                    _addPredefinedMedicine(
                      med,
                      customDosage: doseCtrl.text.trim(),
                      customDuration: durCtrl.text.trim(),
                      customInstructions: instCtrl.text.trim(),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(existingIndex != null ? 'Update Rx' : 'Add to Rx'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openPredefinedMedicinesPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Predefined Formulary',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Tap any medicine to add it to prescription',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: TextField(
                      onChanged: (v) => setModalState(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Search formulary medicines...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        isDense: true,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('predefined_medicines').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                        }

                        final docs = snapshot.data!.docs;
                        final filtered = docs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final name = (data['name']?.toString() ?? '').toLowerCase();
                          final generic = (data['genericName']?.toString() ?? '').toLowerCase();
                          final type = (data['type']?.toString() ?? '').toLowerCase();
                          final q = query.toLowerCase();
                          return q.isEmpty || name.contains(q) || generic.contains(q) || type.contains(q);
                        }).toList();

                        if (docs.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.medication_liquid_outlined, size: 40, color: AppColors.textSecondary),
                                  SizedBox(height: 10),
                                  Text('No Predefined Medicines Yet', style: TextStyle(fontWeight: FontWeight.w700)),
                                  SizedBox(height: 4),
                                  Text(
                                    'Go to Doctor Profile > Predefined Medicines to add or import an Excel file.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        if (filtered.isEmpty) {
                          return const Center(child: Text('No medicines found matching search'));
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final data = filtered[i].data() as Map<String, dynamic>;
                            final name = data['name']?.toString() ?? '';
                            final type = data['type']?.toString() ?? 'Tablet';
                            final dosage = data['dosage']?.toString() ?? '1-0-1';
                            final duration = data['duration']?.toString() ?? '5 Days';

                            final isAlreadyAdded = _medicines.any((m) => m['name']?.toLowerCase() == name.toLowerCase());

                            return ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isAlreadyAdded ? const Color(0xFFCCFBF1) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isAlreadyAdded ? Icons.check_circle_rounded : _getMedIcon(type),
                                  size: 18,
                                  color: isAlreadyAdded ? AppColors.primary : AppColors.textSecondary,
                                ),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              subtitle: Text('$type • $dosage • $duration', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              trailing: isAlreadyAdded
                                  ? const Icon(Icons.check_rounded, color: AppColors.success, size: 20)
                                  : const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                              onTap: () {
                                if (isAlreadyAdded) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$name is already in the prescription!'),
                                      backgroundColor: AppColors.warning,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                } else {
                                  Navigator.pop(ctx);
                                  _addPredefinedMedicine(data);
                                }
                              },
                            );
                          },
                        );
                      },
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

  void _copyRxFromPreviousVisit() {
    if (_resolvedPreviousVisit == null || _resolvedPreviousVisit!.prescriptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous prescription found to copy.'),
          backgroundColor: AppColors.info,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      for (final rx in _resolvedPreviousVisit!.prescriptions) {
        final name = rx['name']?.toString() ?? '';
        if (name.isNotEmpty && !_medicines.any((m) => m['name']?.toLowerCase() == name.toLowerCase())) {
          _medicines.add({
            'name': name,
            'type': rx['type']?.toString() ?? 'Tablet',
            'dosage': rx['dosage']?.toString() ?? '1-0-1',
            'duration': rx['duration']?.toString() ?? '5 Days',
            'instructions': rx['instructions']?.toString() ?? 'After meals',
          });
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${_resolvedPreviousVisit!.prescriptions.length} medicine(s) from previous visit for review.'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submitEncounter() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all mandatory clinical fields.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedClinicId == null || _selectedClinicId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an authorized clinic branch for this visit.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final patientId = widget.patient['id']?.toString() ?? widget.patient['docId']?.toString() ?? '';
      final patientName = widget.patient['name']?.toString() ?? 'Patient';
      final patientPhone = widget.patient['phone']?.toString() ?? '';

      // Commit typed pending medicine if any
      final pendingName = _medNameController.text.trim();
      if (pendingName.isNotEmpty) {
        _medicines.add({
          'name': pendingName,
          'type': _selectedMedType,
          'dosage': _medDosageController.text.trim().isEmpty ? '1-0-1' : _medDosageController.text.trim(),
          'duration': _medDurationController.text.trim().isEmpty ? '5 Days' : _medDurationController.text.trim(),
          'instructions': _medInstructionsController.text.trim(),
        });
        _medNameController.clear();
      }

      final vitals = <String, dynamic>{};
      if (_bpController.text.trim().isNotEmpty) vitals['bp'] = _bpController.text.trim();
      if (_pulseController.text.trim().isNotEmpty) vitals['pulse'] = _pulseController.text.trim();
      if (_tempController.text.trim().isNotEmpty) vitals['temperature'] = _tempController.text.trim();
      if (_weightController.text.trim().isNotEmpty) vitals['weight'] = _weightController.text.trim();
      if (_spo2Controller.text.trim().isNotEmpty) vitals['spo2'] = _spo2Controller.text.trim();

      final consultFee = double.tryParse(_consultFeeController.text.trim()) ?? 500.0;
      final medFee = double.tryParse(_medFeeController.text.trim()) ?? 0.0;

      final savedVisit = await EhrService.saveNewVisit(
        patientId: patientId,
        patientName: patientName,
        patientPhone: patientPhone,
        clinicId: _selectedClinicId!,
        clinicName: _selectedClinicName,
        clinicAddress: _selectedClinicAddress,
        visitType: _selectedVisitType,
        visitDate: _selectedVisitDate,
        chiefComplaint: _complaintController.text.trim().isEmpty
            ? 'Routine Consultation'
            : _complaintController.text.trim(),
        symptoms: [_complaintController.text.trim().isEmpty ? 'Follow-up consultation' : _complaintController.text.trim()],
        vitals: vitals,
        examinationNotes: _examNotesController.text.trim(),
        disease: _diseaseController.text.trim().isEmpty ? 'Follow-up Review' : _diseaseController.text.trim(),
        diagnosis: _diagnosisController.text.trim().isEmpty ? 'Condition Stable' : _diagnosisController.text.trim(),
        diseaseCategory: _selectedDiseaseCategory,
        prescriptions: _medicines,
        clinicalNotes: _clinicalNotesController.text.trim(),
        treatmentPlan: _treatmentPlanController.text.trim(),
        followUpDate: _selectedFollowUpDate,
        followUpInstructions: _followUpInstructionsController.text.trim(),
        consultationFee: consultFee,
        medicineFee: medFee,
        billStatus: _selectedBillStatus,
        paymentMethod: _selectedPaymentMethod,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Visit #${savedVisit.visitNumber} created successfully!'),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, savedVisit);
    } catch (e) {
      debugPrint('Error saving new visit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save visit encounter. Please check your connection and try again.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patient['name']?.toString() ?? 'Patient';
    final patientId = widget.patient['id']?.toString() ?? 'PT-0000';
    final age = widget.patient['age']?.toString() ?? '--';
    final gender = widget.patient['gender']?.toString() ?? '--';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Clinical Consultation',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '$patientName ($patientId)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _submitEncounter,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.check_circle_rounded, color: AppColors.primary),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Visit',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          children: [
            // Patient Identification Banner
            _buildPatientBanner(patientName, patientId, age, gender),
            const SizedBox(height: 16),

            // Clinic & Visit Metadata Card
            _buildEncounterConfigCard(),
            const SizedBox(height: 16),

            // Previous Visit Snapshot (Clinical Reference)
            if (_resolvedPreviousVisit != null) ...[
              _buildPreviousVisitReferenceCard(),
              const SizedBox(height: 16),
            ],

            // Clinical Presentation & Vitals
            _buildSymptomsAndVitalsCard(),
            const SizedBox(height: 16),

            // Diagnosis & Classification Card
            _buildDiagnosisCard(),
            const SizedBox(height: 16),

            // Prescription Card
            _buildPrescriptionCard(),
            const SizedBox(height: 16),

            // Treatment Plan & Follow-up Card
            _buildTreatmentPlanCard(),
            const SizedBox(height: 16),

            // Billing & Payment Card
            _buildBillingCard(),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _submitEncounter,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                label: Text(
                  _isSaving ? 'Recording Encounter...' : 'Save & Finalize Consultation',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // WIDGET BUILDERS
  // ==========================================

  Widget _buildPatientBanner(String name, String id, String age, String gender) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'P',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: $id  •  $age Yrs  •  $gender  •  Blood: ${widget.patient['bloodGroup'] ?? 'N/A'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'EHR Active',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncounterConfigCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ENCOUNTER SETTINGS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),

          // Clinic Branch Dropdown
          DropdownButtonFormField<String>(
            initialValue: _selectedClinicId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Clinic Branch *',
              prefixIcon: const Icon(Icons.local_hospital_rounded, color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: _doctorClinics.map((c) {
              return DropdownMenuItem<String>(
                value: c['docId']?.toString(),
                child: Text(
                  c['name']?.toString() ?? 'Clinic',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                final matched = _doctorClinics.firstWhere((c) => c['docId'] == val);
                setState(() {
                  _selectedClinicId = val;
                  _selectedClinicName = matched['name']?.toString() ?? '';
                  _selectedClinicAddress = matched['address']?.toString() ?? '';
                  if (matched['consultationFee'] != null) {
                    _consultFeeController.text = matched['consultationFee'].toString();
                  }
                });
              }
            },
          ),
          const SizedBox(height: 12),

          // Visit Type & Date
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedVisitType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Visit Type',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: _visitTypes.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(
                        t,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedVisitType = val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedVisitDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() => _selectedVisitDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(
                    '${_selectedVisitDate.day}/${_selectedVisitDate.month}/${_selectedVisitDate.year}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviousVisitReferenceCard() {
    final pv = _resolvedPreviousVisit!;
    final dateStr = '${pv.visitDate.day}/${pv.visitDate.month}/${pv.visitDate.year}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_edu_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PREVIOUS VISIT REFERENCE (#${pv.visitNumber} • $dateStr)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.5),
                ),
              ),
              TextButton.icon(
                onPressed: _copyRxFromPreviousVisit,
                icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                label: const Text('Copy Rx', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Prior Diagnosis: ${pv.diagnosis.isNotEmpty ? pv.diagnosis : pv.disease}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          if (pv.prescriptions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Prior Rx: ${pv.prescriptions.map((m) => '${m['name']} (${m['dosage']})').join(', ')}',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF15803D), fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSymptomsAndVitalsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CHIEF COMPLAINT & VITALS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _complaintController,
            decoration: InputDecoration(
              labelText: 'Chief Complaint / Presenting Symptoms *',
              hintText: 'e.g. Fever for 3 days, dry cough, body ache',
              prefixIcon: const Icon(Icons.sick_outlined, color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Please enter presenting complaint' : null,
          ),
          const SizedBox(height: 12),

          // Vitals Grid
          const Text('Clinical Vitals (Optional)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _bpController,
                  decoration: InputDecoration(
                    labelText: 'BP (mmHg)',
                    hintText: '120/80',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _pulseController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Pulse (bpm)',
                    hintText: '72',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _tempController,
                  decoration: InputDecoration(
                    labelText: 'Temp (°F)',
                    hintText: '98.6',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _weightController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Weight (kg)',
                    hintText: '68',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _spo2Controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'SpO2 (%)',
                    hintText: '99',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _examNotesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Examination Findings & Observations',
              hintText: 'e.g. Chest clear, throat congested, abdomen soft',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIAGNOSIS & CLINICAL ASSESSMENT',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _diseaseController,
            decoration: InputDecoration(
              labelText: 'Disease / Condition *',
              hintText: 'e.g. Acute Viral Bronchitis',
              prefixIcon: const Icon(Icons.biotech_rounded, color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Please enter disease/condition' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _diagnosisController,
            decoration: InputDecoration(
              labelText: 'Definitive Doctor Diagnosis *',
              hintText: 'e.g. Upper Respiratory Tract Infection with Mild Bronchospasm',
              prefixIcon: const Icon(Icons.assignment_turned_in_rounded, color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Please enter diagnosis' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedDiseaseCategory,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Disease Category',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: _diseaseCategories.map((cat) {
              return DropdownMenuItem(
                value: cat,
                child: Text(
                  cat,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedDiseaseCategory = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.medication_rounded, color: AppColors.primary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PRESCRIPTION (RX)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _medicines.isNotEmpty ? const Color(0xFFDCFCE7) : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_medicines.length} Prescribed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _medicines.isNotEmpty ? const Color(0xFF15803D) : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.fullscreen_rounded, color: AppColors.primary, size: 20),
                    tooltip: 'Open Fullscreen Formulary Modal',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openPredefinedMedicinesPicker,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- PREDEFINED FORMULARY / UPLOADED MEDICINES SECTION ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_done_rounded, color: AppColors.primary, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Search & Select Uploaded Medicines',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Formulary Catalog • Tap medicine to prescribe',
                            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen_rounded, color: AppColors.primary, size: 20),
                      tooltip: 'Open Fullscreen Formulary Modal',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openPredefinedMedicinesPicker,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Search Field
                TextField(
                  controller: _medSearchController,
                  onChanged: (v) => setState(() => _medSearchQuery = v),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Search uploaded medicine (e.g. Paracetamol, Amox)...',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
                    suffixIcon: _medSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textSecondary),
                            onPressed: () {
                              _medSearchController.clear();
                              setState(() => _medSearchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Formulation Chips Filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _medFilterOptions.map((f) {
                      final isSelected = _medFilterType == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setState(() => _medFilterType = f),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),

                // Live Stream of Predefined Medicines
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('predefined_medicines').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Error loading medicines: ${snapshot.error}', style: const TextStyle(fontSize: 11, color: AppColors.error)),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No predefined medicines found in formulary.\nGo to Profile > Predefined Medicines to import an Excel file or load starters.',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final List<Map<String, dynamic>> allMeds = [];
                    for (final d in docs) {
                      final map = Map<String, dynamic>.from(d.data() as Map);
                      map['docId'] = d.id;
                      allMeds.add(map);
                    }

                    final q = _medSearchQuery.trim().toLowerCase();
                    final filtered = allMeds.where((m) {
                      final name = (m['name']?.toString() ?? '').toLowerCase();
                      final generic = (m['genericName']?.toString() ?? '').toLowerCase();
                      final type = (m['type']?.toString() ?? '').toLowerCase();

                      final matchesQuery = q.isEmpty || name.contains(q) || generic.contains(q);
                      final matchesType = _medFilterType == 'All' || type == _medFilterType.toLowerCase();

                      return matchesQuery && matchesType;
                    }).toList();

                    if (filtered.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'No uploaded medicine matching "$_medSearchQuery"',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showCustomMedForm = true;
                                  _medNameController.text = _medSearchQuery;
                                });
                              },
                              icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                              label: Text(
                                'Add "$_medSearchQuery" as custom medicine',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Display Scrollable Matching Medicines
                    return Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        itemBuilder: (context, i) {
                          final med = filtered[i];
                          final name = med['name']?.toString() ?? '';
                          final generic = med['genericName']?.toString() ?? '';
                          final type = med['type']?.toString() ?? 'Tablet';
                          final dosage = med['dosage']?.toString() ?? '1-0-1';
                          final duration = med['duration']?.toString() ?? '5 Days';
                          final fee = med['fee'];

                          final bool isAlreadyAdded = _medicines.any(
                            (m) => m['name']?.toLowerCase() == name.toLowerCase(),
                          );

                          return InkWell(
                            onTap: () {
                              if (isAlreadyAdded) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$name is already in the prescription!'),
                                    backgroundColor: AppColors.warning,
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              } else {
                                _addPredefinedMedicine(med);
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              child: Row(
                                children: [
                                  // Type icon container
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: isAlreadyAdded ? const Color(0xFFCCFBF1) : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isAlreadyAdded ? AppColors.primary : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Icon(
                                      isAlreadyAdded ? Icons.check_circle_rounded : _getMedIcon(type),
                                      size: 18,
                                      color: isAlreadyAdded ? AppColors.primary : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Medicine info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: isAlreadyAdded ? AppColors.primary : AppColors.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE2E8F0),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                type,
                                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (generic.isNotEmpty) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            generic,
                                            style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        const SizedBox(height: 3),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 2,
                                          children: [
                                            Text('Dose: $dosage', style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                                            const Text('•', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                                            Text(duration, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                                            if (fee != null && (fee as num) > 0) ...[
                                              const Text('•', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                                              Text('₹$fee', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Actions: Customize or Quick Add
                                  IconButton(
                                    icon: const Icon(Icons.tune_rounded, size: 18, color: AppColors.textSecondary),
                                    tooltip: 'Customize Dose & Duration',
                                    onPressed: () => _showCustomizeMedicineDialog(med),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isAlreadyAdded ? const Color(0xFFDCFCE7) : AppColors.primarySurface,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isAlreadyAdded ? Icons.check_rounded : Icons.add_rounded,
                                          size: 13,
                                          color: isAlreadyAdded ? const Color(0xFF15803D) : AppColors.primary,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          isAlreadyAdded ? 'Added' : 'Add',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isAlreadyAdded ? const Color(0xFF15803D) : AppColors.primary,
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
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- CUSTOM MEDICINE MANUAL ENTRY TOGGLE / FORM ---
          InkWell(
            onTap: () => setState(() => _showCustomMedForm = !_showCustomMedForm),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _showCustomMedForm ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showCustomMedForm ? 'Hide Custom / Unlisted Medicine Form' : 'Add Custom / Unlisted Medicine',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),

          if (_showCustomMedForm) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _medNameController,
                          decoration: InputDecoration(
                            labelText: 'Medicine Name',
                            hintText: 'e.g. Paracetamol 650mg',
                            prefixIcon: const Icon(Icons.medication_rounded, color: AppColors.primary),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedMedType,
                        underline: const SizedBox(),
                        items: ['Tablet', 'Syrup', 'Capsule', 'Injection', 'Drops', 'Ointment'].map((t) {
                          return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12.5)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedMedType = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _medDosageController,
                          decoration: InputDecoration(
                            labelText: 'Dosage',
                            hintText: '1-0-1',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _medDurationController,
                          decoration: InputDecoration(
                            labelText: 'Duration',
                            hintText: '5 Days',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _medInstructionsController,
                          decoration: InputDecoration(
                            labelText: 'Instructions',
                            hintText: 'e.g. After meals',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addMedicine,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Rx'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // --- PRESCRIBED MEDICINES LIST ---
          if (_medicines.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PRESCRIBED MEDICINES FOR THIS VISIT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary),
                ),
                TextButton(
                  onPressed: () => setState(() => _medicines.clear()),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Clear All', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _medicines.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final m = _medicines[idx];
                final type = m['type'] ?? 'Tablet';
                final instructions = m['instructions'] ?? '';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_getMedIcon(type), color: const Color(0xFF16A34A), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m['name'] ?? '',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF14532D)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    type,
                                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${m['dosage']}  •  ${m['duration']}${instructions.isNotEmpty ? '  •  $instructions' : ''}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () => _showCustomizeMedicineDialog(m, existingIndex: idx),
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF16A34A)),
                        tooltip: 'Edit Dose & Schedule',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () => setState(() => _medicines.removeAt(idx)),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                        tooltip: 'Remove',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTreatmentPlanCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TREATMENT PLAN & FOLLOW-UP',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _treatmentPlanController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Treatment Plan & Clinical Advice',
              hintText: 'e.g. Steam inhalation twice daily, drink plenty of warm fluids, rest',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedFollowUpDate ?? DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _selectedFollowUpDate = picked);
                    }
                  },
                  icon: const Icon(Icons.event_repeat_rounded, size: 16),
                  label: Text(
                    _selectedFollowUpDate != null
                        ? 'Follow-up: ${_selectedFollowUpDate!.day}/${_selectedFollowUpDate!.month}/${_selectedFollowUpDate!.year}'
                        : 'Select Follow-up Date',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (_selectedFollowUpDate != null)
                IconButton(
                  onPressed: () => setState(() => _selectedFollowUpDate = null),
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear follow-up',
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _followUpInstructionsController,
            decoration: InputDecoration(
              labelText: 'Follow-up Instructions (Optional)',
              hintText: 'e.g. Return sooner if high fever persists or breathing difficulty occurs',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BILLING & PAYMENT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
              ),
              Text(
                'Total: ₹${_totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _consultFeeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Consultation Fee (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _medFeeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Medicine Fee (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedBillStatus,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: ['Paid', 'Pending'].map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(
                        s,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBillStatus = val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMethod,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Mode',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: ['UPI', 'Cash', 'Card', 'NetBanking'].map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text(
                        m,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedPaymentMethod = val);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
