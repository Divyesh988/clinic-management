import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/clinic_service.dart';
import '../services/doctor_service.dart';
import '../services/ehr_service.dart';
import '../theme/app_colors.dart';
import 'clinic_form_sheet.dart';
import 'patient_ehr_screen.dart';

class AddPatientScreen extends StatefulWidget {
  final String? initialClinicId;
  final String? initialClinicName;
  final double? initialConsultationFee;

  const AddPatientScreen({
    super.key,
    this.initialClinicId,
    this.initialClinicName,
    this.initialConsultationFee,
  });

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _areaController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinCodeController = TextEditingController();
  final _diseaseController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _consultationFeeController = TextEditingController(text: '500');
  final _medicineFeeController = TextEditingController(text: '200');

  // Dropdown & Selection states
  String _selectedGender = 'Male';
  String _selectedBloodGroup = 'B+';
  String _selectedDiseaseCategory = 'General & Infectious';
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
  String _selectedPaymentMethod = 'UPI';
  String _selectedPaymentStatus = 'Paid';
  bool _isSaving = false;

  // Selected Clinic State (Clinic-wise Patient Storage)
  String? _selectedClinicId;
  String _selectedClinicName = '';
  String _selectedClinicAddress = '';
  bool _hasExplicitlySelectedClinic = false;
  List<Map<String, dynamic>> _fetchedClinics = [];

  // Medicine items list
  final List<Map<String, String>> _medicines = [];

  final _medNameController = TextEditingController();
  final _medDosageController = TextEditingController(text: '1-0-1');
  final _medDurationController = TextEditingController(text: '5 Days');
  final _medInstructionsController = TextEditingController(text: 'After meals');
  String _selectedMedType = 'Tablet';

  final List<String> _mealTimingOptions = [
    'After meals',
    'Before meals',
    'With meals',
    'At bedtime',
    'Empty stomach',
    'As needed (SOS)',
  ];

  // Uploaded/Predefined Medicines Search State
  final _medSearchController = TextEditingController();
  String _medSearchQuery = '';
  String _medFilterType = 'All';
  bool _showCustomMedForm = false;

  final List<String> _medFilterOptions = [
    'All', 'Tablet', 'Capsule', 'Syrup', 'Injection', 'Drops', 'Ointment', 'Powder', 'Inhaler'
  ];

  final List<String> _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'
  ];

  final List<String> _medicineTypes = [
    'Tablet', 'Syrup', 'Capsule', 'Injection', 'Ointment', 'Drops'
  ];

  // Existing Patient Detection & Duplicate Prevention
  List<Map<String, dynamic>> _matchingExistingPatients = [];

  @override
  void initState() {
    super.initState();
    _fetchClinicsAndPrompt();
    _mobileController.addListener(_onMobileChanged);
    _nameController.addListener(_onNameChanged);
  }

  void _onMobileChanged() {
    _checkExistingPatients(_mobileController.text);
  }

  void _onNameChanged() {
    if (_mobileController.text.trim().length < 5) {
      _checkExistingPatients(_nameController.text);
    }
  }

  Future<void> _checkExistingPatients(String query) async {
    final clean = query.trim();
    if (clean.length < 4) {
      if (_matchingExistingPatients.isNotEmpty) {
        setState(() => _matchingExistingPatients = []);
      }
      return;
    }

    final results = await EhrService.searchExistingPatients(clean);
    if (!mounted) return;
    setState(() {
      _matchingExistingPatients = results;
    });
  }

  Future<void> _fetchClinicsAndPrompt() async {
    try {
      final list = await ClinicService.getDoctorClinics();
      if (!mounted) return;

      setState(() {
        _fetchedClinics = list;
        if (widget.initialClinicId != null && list.any((c) => c['docId'] == widget.initialClinicId)) {
          final matched = list.firstWhere((c) => c['docId'] == widget.initialClinicId);
          _selectedClinicId = matched['docId'];
          _selectedClinicName = matched['name']?.toString() ?? widget.initialClinicName ?? 'Clinic';
          _selectedClinicAddress = matched['address']?.toString() ?? '';
          _hasExplicitlySelectedClinic = true;
          if (matched['consultationFee'] != null) {
            _consultationFeeController.text = matched['consultationFee'].toString();
          } else if (widget.initialConsultationFee != null) {
            _consultationFeeController.text = widget.initialConsultationFee.toString();
          }
        } else if (list.isNotEmpty) {
          final primary = list.firstWhere((c) => c['isPrimary'] == true, orElse: () => list.first);
          _selectedClinicId = primary['docId'];
          _selectedClinicName = primary['name']?.toString() ?? 'Clinic';
          _selectedClinicAddress = primary['address']?.toString() ?? '';
          if (primary['consultationFee'] != null) {
            _consultationFeeController.text = primary['consultationFee'].toString();
          }
        } else {
          _selectedClinicId = null;
          _selectedClinicName = '';
          _selectedClinicAddress = '';
        }
      });

      // Explicitly prompt the user to choose/confirm which clinic this patient belongs to only if not preselected
      if (widget.initialClinicId == null && list.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showClinicSelectionModal(context, isMandatoryPrompt: false);
        });
      }
    } catch (e) {
      debugPrint('Error fetching clinics for patient screen: $e');
    }
  }

  @override
  void dispose() {
    _mobileController.removeListener(_onMobileChanged);
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _mobileController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pinCodeController.dispose();
    _diseaseController.dispose();
    _diagnosisController.dispose();
    _consultationFeeController.dispose();
    _medicineFeeController.dispose();
    _medNameController.dispose();
    _medDosageController.dispose();
    _medDurationController.dispose();
    _medInstructionsController.dispose();
    _medSearchController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final consult = double.tryParse(_consultationFeeController.text) ?? 0.0;
    final meds = double.tryParse(_medicineFeeController.text) ?? 0.0;
    return consult + meds;
  }

  void _addMedicine() {
    final name = _medNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a medicine name'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final instructions = _medInstructionsController.text.trim();

    setState(() {
      _medicines.add({
        'name': name,
        'type': _selectedMedType,
        'dosage': _medDosageController.text.trim().isEmpty ? '1-0-1' : _medDosageController.text.trim(),
        'duration': _medDurationController.text.trim().isEmpty ? '5 Days' : _medDurationController.text.trim(),
        'instructions': instructions.isEmpty ? 'After meals' : instructions,
      });
      _medNameController.clear();
      _medDosageController.text = '1-0-1';
      _medDurationController.text = '5 Days';
      _medInstructionsController.text = 'After meals';
    });
  }

  void _removeMedicine(int index) {
    setState(() {
      _medicines.removeAt(index);
    });
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
            Expanded(child: Text('Added $name ($dosage, $duration • $instructions)')),
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
    final instCtrl = TextEditingController(text: existingIndex != null ? (_medicines[existingIndex]['instructions'] ?? 'After meals') : (med['instructions']?.toString() ?? 'After meals'));

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
                      Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
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
                  const Text('Dosage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: doseCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['1-0-1', '1-0-0', '0-0-1', '1-1-1', 'SOS'].map((d) {
                      final isSelected = doseCtrl.text.trim() == d;
                      return InkWell(
                        onTap: () => setDialogState(() => doseCtrl.text = d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Duration', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: durCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['3 Days', '5 Days', '7 Days', '15 Days', '30 Days'].map((dur) {
                      final isSelected = durCtrl.text.trim() == dur;
                      return InkWell(
                        onTap: () => setDialogState(() => durCtrl.text = dur),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            dur,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Instructions / Meal Timing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: instCtrl,
                    decoration: const InputDecoration(
                      hintText: 'e.g. After meals, Before meals',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _mealTimingOptions.map((opt) {
                      final isSelected = instCtrl.text.trim() == opt;
                      return InkWell(
                        onTap: () => setDialogState(() => instCtrl.text = opt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            opt,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
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
                      customDosage: doseCtrl.text.trim().isEmpty ? '1-0-1' : doseCtrl.text.trim(),
                      customDuration: durCtrl.text.trim().isEmpty ? '5 Days' : durCtrl.text.trim(),
                      customInstructions: instCtrl.text.trim().isEmpty ? 'After meals' : instCtrl.text.trim(),
                    );
                  }
                },
                child: Text(
                  existingIndex != null ? 'Update Medicine' : 'Add to Prescription',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getMedIcon(String type) {
    switch (type.toLowerCase()) {
      case 'syrup':
        return Icons.water_drop_outlined;
      case 'injection':
        return Icons.vaccines_outlined;
      case 'capsule':
        return Icons.medication_liquid_outlined;
      case 'ointment':
        return Icons.healing_outlined;
      case 'drops':
        return Icons.opacity_rounded;
      case 'inhaler':
        return Icons.air_rounded;
      case 'powder':
        return Icons.grain_rounded;
      default:
        return Icons.medication_rounded;
    }
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
              height: MediaQuery.of(context).size.height * 0.75,
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Predefined Formulary',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                            Text(
                              'Tap any medicine to add it to prescription',
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
                          final type = (data['type']?.toString() ?? '').toLowerCase();
                          final q = query.toLowerCase();
                          return q.isEmpty || name.contains(q) || type.contains(q);
                        }).toList();

                        if (docs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
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

                            return ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCCFBF1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.medication_rounded, size: 18, color: AppColors.primary),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              subtitle: Text('$type • $dosage • $duration', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              trailing: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                              onTap: () {
                                final isAlreadyAdded = _medicines.any((m) => m['name']?.toLowerCase() == name.toLowerCase());
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

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required patient details'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_hasExplicitlySelectedClinic || _selectedClinicName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select which clinic this patient belongs to'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _showClinicSelectionModal(context, isMandatoryPrompt: true);
      return;
    }

    // Auto-commit any typed medicine currently in the fields
    final pendingMedName = _medNameController.text.trim();
    if (pendingMedName.isNotEmpty) {
      _medicines.add({
        'name': pendingMedName,
        'type': _selectedMedType,
        'dosage': _medDosageController.text.trim().isEmpty ? '1-0-1' : _medDosageController.text.trim(),
        'duration': _medDurationController.text.trim().isEmpty ? '5 Days' : _medDurationController.text.trim(),
        'instructions': _medInstructionsController.text.trim().isEmpty ? 'After meals' : _medInstructionsController.text.trim(),
      });
      _medNameController.clear();
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);

    // Pre-submission validation: Revalidate clinic existence and ownership immediately before committing patient records
    if (_selectedClinicId == null || _selectedClinicId!.trim().isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an active clinic for this patient.'),
          backgroundColor: AppColors.error,
        ),
      );
      _showClinicSelectionModal(context, isMandatoryPrompt: true);
      return;
    }

    try {
      final clinic = await ClinicService.getClinicById(_selectedClinicId!);
      if (clinic == null) {
        setState(() => _isSaving = false);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Clinic Not Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'The clinic assigned to this record is not registered under your profile or has been deleted. Please select an active clinic before saving.',
                style: TextStyle(fontSize: 13),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _fetchClinicsAndPrompt();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Select Active Clinic', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Clinic existence check error: $e');
    }

    final name = _nameController.text.trim();
    final initials = name.split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() : '').take(2).join();
    final total = _totalAmount.toInt();
    final pending = _selectedPaymentStatus == 'Paid' ? 0 : total;

    final medSummary = _medicines.isNotEmpty
        ? _medicines
            .map((m) =>
                '${m['name']} (${m['dosage']}${m['instructions'] != null && m['instructions']!.isNotEmpty ? ' - ${m['instructions']}' : ''})')
            .join(', ')
        : 'None Prescribed';

    final String id = "PT-${10000 + DateTime.now().millisecondsSinceEpoch % 90000}";

    final Map<String, dynamic> patientData = {
      'id': id,
      'doctorId': DoctorService.currentDoctorId,
      'name': name,
      'initials': initials.isEmpty ? 'PT' : initials,
      'age': int.tryParse(_ageController.text.trim()) ?? 30,
      'gender': _selectedGender,
      'phone': _mobileController.text.trim(),
      'address': _addressController.text.trim(),
      'area': _areaController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim(),
      'pinCode': _pinCodeController.text.trim(),
      'email': '${name.toLowerCase().replaceAll(' ', '')}@email.com',
      'bloodGroup': _selectedBloodGroup,
      'clinic': _selectedClinicName,
      'clinicId': _selectedClinicId ?? '',
      'clinicAddress': _selectedClinicAddress,
      'lastVisit': 'Today, Just now',
      'disease': _diseaseController.text.trim().isEmpty ? 'General Consultation' : _diseaseController.text.trim(),
      'diagnosis': _diagnosisController.text.trim().isEmpty ? 'Under Clinical Review' : _diagnosisController.text.trim(),
      'diseaseCategory': _selectedDiseaseCategory,
      'totalVisits': 1,
      'billStatus': _selectedPaymentStatus,
      'pendingAmount': pending,
      'totalBilled': total,
      'lastBillDate': 'Today',
      'allergies': 'No known drug allergies',
      'recentRx': medSummary,
      'medicines': _medicines.map((m) => {
        'name': m['name'] ?? '',
        'type': m['type'] ?? 'Tablet',
        'dosage': m['dosage'] ?? '1-0-1',
        'duration': m['duration'] ?? '5 Days',
        'instructions': m['instructions'] ?? 'After meals',
      }).toList(),
      'consultationFee': double.tryParse(_consultationFeeController.text.trim()) ?? 500.0,
      'medicineFee': double.tryParse(_medicineFeeController.text.trim()) ?? 200.0,
      'totalAmount': _totalAmount,
      'paymentMethod': _selectedPaymentMethod,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final Map<String, dynamic> visitDetails = {
      'visitDate': DateTime.now(),
      'clinicId': _selectedClinicId ?? '',
      'clinicName': _selectedClinicName,
      'clinicAddress': _selectedClinicAddress,
      'chiefComplaint': _diseaseController.text.trim().isEmpty ? 'General Consultation' : _diseaseController.text.trim(),
      'disease': _diseaseController.text.trim().isEmpty ? 'General Consultation' : _diseaseController.text.trim(),
      'diagnosis': _diagnosisController.text.trim().isEmpty ? 'Under Clinical Review' : _diagnosisController.text.trim(),
      'diseaseCategory': _selectedDiseaseCategory,
      'prescriptions': _medicines.map((m) => {
        'name': m['name'] ?? '',
        'type': m['type'] ?? 'Tablet',
        'dosage': m['dosage'] ?? '1-0-1',
        'duration': m['duration'] ?? '5 Days',
        'instructions': m['instructions'] ?? 'After meals',
      }).toList(),
      'consultationFee': double.tryParse(_consultationFeeController.text.trim()) ?? 500.0,
      'medicineFee': double.tryParse(_medicineFeeController.text.trim()) ?? 200.0,
      'billStatus': _selectedPaymentStatus,
      'paymentMethod': _selectedPaymentMethod,
    };

    try {
      await EhrService.savePatientWithFirstVisit(
        patientData: patientData,
        visitDetails: visitDetails,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Patient registered successfully!')),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      debugPrint('Patient save error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved locally. Records will synchronize automatically.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context, patientData);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Digital Patient Record',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Practice Directory • $_selectedClinicName',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_matchingExistingPatients.isNotEmpty)
                _buildExistingPatientFoundBanner(),
              _buildClinicSelectorCard(),
              const SizedBox(height: 18),
              _buildSectionHeader(
                icon: Icons.person_add_alt_1_rounded,
                title: '1. Basic Patient Information',
                subtitle: 'Personal identity and contact details',
              ),
              const SizedBox(height: 12),
              _buildCardContainer([
                _buildTextField(
                  controller: _nameController,
                  label: 'Patient Full Name *',
                  hint: 'e.g. Ramesh Chandra Patel',
                  icon: Icons.badge_outlined,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter patient name' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        controller: _mobileController,
                        label: 'Mobile Number *',
                        hint: 'e.g. 98765 43210',
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                        validator: (v) => v == null || v.trim().length < 8 ? 'Valid phone required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _ageController,
                        label: 'Age *',
                        hint: 'e.g. 35',
                        icon: Icons.cake_outlined,
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter age' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gender',
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
                                value: _selectedGender,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                items: ['Male', 'Female', 'Other'].map((g) {
                                  return DropdownMenuItem(value: g, child: Text(g));
                                }).toList(),
                                onChanged: (v) => setState(() => _selectedGender = v!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Blood Group',
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
                                value: _selectedBloodGroup,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                items: _bloodGroups.map((bg) {
                                  return DropdownMenuItem(value: bg, child: Text(bg));
                                }).toList(),
                                onChanged: (v) => setState(() => _selectedBloodGroup = v!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _addressController,
                  label: 'Residential Address Line',
                  hint: 'e.g. 402, Shivalik Heights, 132 Feet Ring Road',
                  icon: Icons.location_on_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        controller: _areaController,
                        label: 'Area / Locality',
                        hint: 'e.g. Central District',
                        icon: Icons.holiday_village_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        controller: _pinCodeController,
                        label: 'PIN Code',
                        hint: 'e.g. 110001',
                        icon: Icons.pin_drop_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _cityController,
                        label: 'City',
                        hint: 'e.g. City Name',
                        icon: Icons.location_city_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _stateController,
                        label: 'State',
                        hint: 'e.g. Gujarat',
                        icon: Icons.map_outlined,
                      ),
                    ),
                  ],
                ),
              ]),

              const SizedBox(height: 20),
              _buildSectionHeader(
                icon: Icons.medical_services_outlined,
                title: '2. Disease & Clinical Diagnosis',
                subtitle: 'Symptoms, complaints, category and doctor diagnosis',
              ),
              const SizedBox(height: 12),
              _buildCardContainer([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clinical Category',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedDiseaseCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          items: _diseaseCategories.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedDiseaseCategory = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _diseaseController,
                  label: 'Disease / Chief Complaint *',
                  hint: 'e.g. High fever, chills & body ache since 2 days',
                  icon: Icons.sick_outlined,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter disease or symptoms' : null,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _diagnosisController,
                  label: 'Clinical Diagnosis *',
                  hint: 'e.g. Acute Viral Pyrexia with Dehydration',
                  icon: Icons.health_and_safety_outlined,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter doctor diagnosis' : null,
                ),
              ]),

              const SizedBox(height: 20),
              _buildSectionHeader(
                icon: Icons.medication_outlined,
                title: '3. Prescribed Medicines (Type & Dose)',
                subtitle: 'Record medicines given to the patient',
              ),
              const SizedBox(height: 12),
              _buildCardContainer([
                // Section 3 Header: Prescribed Medicines
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Prescribed Medicines (${_medicines.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_medicines.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _medicines.clear()),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: AppColors.error),
                        label: const Text('Clear All', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Added Medicines List
                if (_medicines.isNotEmpty) ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _medicines.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final med = _medicines[i];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFCCFBF1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getMedIcon(med['type'] ?? 'Tablet'),
                                size: 17,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    med['name']!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 2,
                                    children: [
                                      Text(
                                        '${med['type']} • ${med['dosage']} • ${med['duration']}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      if ((med['instructions'] ?? '').toString().trim().isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: Text(
                                            med['instructions']!,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                              tooltip: 'Adjust dose or duration',
                              onPressed: () => _showCustomizeMedicineDialog(med, existingIndex: i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                              tooltip: 'Remove',
                              onPressed: () => _removeMedicine(i),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                // Empty state if no medicines yet
                if (_medicines.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No medicines prescribed yet. Search uploaded medicines below and tap "+ Add" to prescribe with 1 tap.',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Uploaded Medicines Direct Search & Select View
                _buildUploadedMedicinesSection(),
                const SizedBox(height: 12),

                // Manual / Custom Medicine Entry Accordion
                _buildCustomMedicineEntryForm(),
              ]),

              const SizedBox(height: 20),
              _buildSectionHeader(
                icon: Icons.receipt_long_rounded,
                title: '4. Billing & Payment Collected',
                subtitle: 'Consultation fee, medicine charges & total amount taken',
              ),
              const SizedBox(height: 12),
              _buildCardContainer([
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _consultationFeeController,
                        label: 'Consultation Fee (₹)',
                        hint: '500',
                        icon: Icons.currency_rupee_rounded,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _medicineFeeController,
                        label: 'Medicines / Other (₹)',
                        hint: '200',
                        icon: Icons.local_pharmacy_outlined,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Payment Status & Method
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Status',
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
                                value: _selectedPaymentStatus,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                items: ['Paid', 'Pending', 'Partial'].map((s) {
                                  return DropdownMenuItem(value: s, child: Text(s));
                                }).toList(),
                                onChanged: (v) => setState(() => _selectedPaymentStatus = v!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Mode',
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
                                value: _selectedPaymentMethod,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                items: ['UPI', 'Cash', 'Card'].map((m) {
                                  return DropdownMenuItem(value: m, child: Text(m));
                                }).toList(),
                                onChanged: (v) => setState(() => _selectedPaymentMethod = v!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Total Amount Taken Highlight Box
                Container(
                  padding: const EdgeInsets.all(14),
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
                        children: [
                          const Text(
                            'TOTAL AMOUNT COLLECTED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Status: $_selectedPaymentStatus via $_selectedPaymentMethod',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₹${_totalAmount.toInt()}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _savePatient,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                  label: Text(
                    _isSaving ? 'Saving Patient Record...' : 'Save Patient Record',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showClinicSelectionModal(BuildContext context, {bool isMandatoryPrompt = false}) async {
    List<Map<String, dynamic>> clinics = [];
    try {
      clinics = await ClinicService.getDoctorClinics();
    } catch (e) {
      debugPrint('Error getting clinics for modal: $e');
    }

    if (clinics.isEmpty && _fetchedClinics.isNotEmpty) {
      clinics = List.from(_fetchedClinics);
    }

    if (!mounted || !context.mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    String tempSelectedId = _selectedClinicId ?? (clinics.isNotEmpty ? (clinics.first['docId']?.toString() ?? '') : '');
    String tempSelectedName = _selectedClinicName.isNotEmpty
        ? _selectedClinicName
        : (clinics.isNotEmpty ? (clinics.first['name']?.toString() ?? '') : '');
    String tempSelectedAddress = _selectedClinicAddress.isNotEmpty
        ? _selectedClinicAddress
        : (clinics.isNotEmpty ? (clinics.first['address']?.toString() ?? '') : '');
    double tempFee = double.tryParse(_consultationFeeController.text) ??
        (clinics.isNotEmpty ? ((clinics.first['consultationFee'] as num?)?.toDouble() ?? 500.0) : 500.0);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !isMandatoryPrompt,
      enableDrag: !isMandatoryPrompt,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primaryBorder),
                        ),
                        child: const Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Which Clinic Does This Patient Belong To?',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                height: 1.25,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Select the clinical practice branch for this patient record',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (!isMandatoryPrompt)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (clinics.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'No Clinics Registered Yet',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Add a clinic location to assign patient records.',
                                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final created = await showAddEditClinicSheet(context);
                                if (created != null && mounted) {
                                  final refreshed = await ClinicService.getDoctorClinics();
                                  setModalState(() {
                                    clinics = refreshed;
                                    tempSelectedId = created['id']?.toString() ?? '';
                                    tempSelectedName = created['name']?.toString() ?? '';
                                    tempSelectedAddress = created['address']?.toString() ?? '';
                                    tempFee = (created['consultationFee'] as num?)?.toDouble() ?? 500.0;
                                  });
                                  _fetchClinicsAndPrompt();
                                }
                              },
                              icon: const Icon(Icons.add_location_alt_rounded, size: 16, color: AppColors.primary),
                              label: const Text('+ Add Clinic Now', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: clinics.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final clinic = clinics[idx];
                          final id = clinic['docId']?.toString() ?? '';
                          final name = clinic['name']?.toString() ?? 'Clinic';
                          final address = clinic['address']?.toString() ?? '';
                          final isPrimary = clinic['isPrimary'] == true;
                          final fee = (clinic['consultationFee'] as num?)?.toDouble() ?? 500.0;
                          final isSelected = tempSelectedId == id || tempSelectedName == name;

                          return InkWell(
                            onTap: () {
                              setModalState(() {
                                tempSelectedId = id;
                                tempSelectedName = name;
                                tempSelectedAddress = address;
                                tempFee = fee;
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                                  width: isSelected ? 1.8 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                    color: isSelected ? AppColors.primary : const Color(0xFF94A3B8),
                                    size: 22,
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
                                                name,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isPrimary) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE0F2FE),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Primary',
                                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (address.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
                                              const SizedBox(width: 3),
                                              Expanded(
                                                child: Text(
                                                  address,
                                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.primary : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      '₹${fee.toInt()}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? Colors.white : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: clinics.isEmpty
                          ? () async {
                              final created = await showAddEditClinicSheet(context);
                              if (created != null && mounted) {
                                final refreshed = await ClinicService.getDoctorClinics();
                                setModalState(() {
                                  clinics = refreshed;
                                  tempSelectedId = created['id']?.toString() ?? '';
                                  tempSelectedName = created['name']?.toString() ?? '';
                                  tempSelectedAddress = created['address']?.toString() ?? '';
                                  tempFee = (created['consultationFee'] as num?)?.toDouble() ?? 500.0;
                                });
                                _fetchClinicsAndPrompt();
                              }
                            }
                          : () {
                              setState(() {
                                _selectedClinicId = tempSelectedId;
                                _selectedClinicName = tempSelectedName;
                                _selectedClinicAddress = tempSelectedAddress;
                                _consultationFeeController.text = tempFee.toInt().toString();
                                _hasExplicitlySelectedClinic = true;
                              });
                              Navigator.pop(ctx, true);
                            },
                      icon: Icon(
                        clinics.isEmpty ? Icons.add_rounded : Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        clinics.isEmpty
                            ? 'Register New Clinic'
                            : 'Confirm & Assign to ${tempSelectedName.isEmpty ? "Clinic" : tempSelectedName}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    if (result == true && mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Patient assigned to $_selectedClinicName')),
            ],
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildExistingPatientFoundBanner() {
    final firstMatch = _matchingExistingPatients.first;
    final name = firstMatch['name']?.toString() ?? 'Patient';
    final id = firstMatch['id']?.toString() ?? firstMatch['docId']?.toString() ?? '';
    final phone = firstMatch['phone']?.toString() ?? '';
    final clinic = firstMatch['clinic']?.toString() ?? 'Clinic';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search_rounded, color: Color(0xFFB45309), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Existing Patient Record Found!',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _matchingExistingPatients = []),
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF92400E)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$name  •  $phone  •  ID: $id  •  $clinic',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF78350F)),
          ),
          const SizedBox(height: 6),
          const Text(
            'This patient is already registered. To prevent creating duplicate patient documents, open their EHR to add a consultation visit.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PatientEhrScreen(patient: firstMatch),
                  ),
                );
              },
              icon: const Icon(Icons.folder_shared_rounded, size: 16, color: Colors.white),
              label: const Text(
                'Open EHR & Add Visit',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicSelectorCard() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ClinicService.streamDoctorClinics(),
      builder: (context, snapshot) {
        final clinics = snapshot.data ?? [];

        // If clinics exist and none selected yet, default to primary or first
        if (clinics.isNotEmpty && (_selectedClinicId == null || _selectedClinicName.isEmpty)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final primary = clinics.firstWhere((c) => c['isPrimary'] == true, orElse: () => clinics.first);
            setState(() {
              _selectedClinicId = primary['docId'];
              _selectedClinicName = primary['name']?.toString() ?? 'Clinic';
              _selectedClinicAddress = primary['address']?.toString() ?? '';
              if (primary['consultationFee'] != null) {
                _consultationFeeController.text = primary['consultationFee'].toString();
              }
            });
          });
        }

        final bool isAssigned = _hasExplicitlySelectedClinic && _selectedClinicName.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAssigned ? AppColors.primaryBorder : const Color(0xFFFDE68A),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isAssigned ? AppColors.primary : const Color(0xFFF59E0B)).withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isAssigned ? AppColors.primarySurface : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_hospital_rounded,
                      size: 19,
                      color: isAssigned ? AppColors.primary : const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Clinic / Hospital Branch *',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isAssigned ? const Color(0xFFCCFBF1) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isAssigned ? 'Assigned' : 'Required',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: isAssigned ? AppColors.primary : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Which clinic does this patient belong to?',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showClinicSelectionModal(context),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 15, color: AppColors.primary),
                    label: const Text(
                      'Change',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (clinics.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'No Clinics Registered Yet',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            Text(
                              'Tap + Add or go to Doctor Profile to register a clinic.',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final created = await showAddEditClinicSheet(context);
                          if (created != null && mounted) {
                            setState(() {
                              _selectedClinicId = created['id']?.toString();
                              _selectedClinicName = created['name']?.toString() ?? '';
                              _selectedClinicAddress = created['address']?.toString() ?? '';
                              if (created['consultationFee'] != null) {
                                _consultationFeeController.text = created['consultationFee'].toString();
                              }
                              _hasExplicitlySelectedClinic = true;
                            });
                          }
                        },
                        child: const Text('+ Add', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: clinics.map((data) {
                    final docId = data['docId']?.toString() ?? '';
                    final clinicName = data['name']?.toString() ?? 'Clinic';
                    final address = data['address']?.toString() ?? '';
                    final fee = data['consultationFee'] ?? 500;
                    final isSelected = _selectedClinicId == docId ||
                        (_selectedClinicId == null && _selectedClinicName == clinicName);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedClinicId = docId;
                            _selectedClinicName = clinicName;
                            _selectedClinicAddress = address;
                            _consultationFeeController.text = fee.toString();
                            _hasExplicitlySelectedClinic = true;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
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
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          clinicName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                            color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                          ),
                                        ),
                                        if (data['isPrimary'] == true) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0F2FE),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Primary',
                                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (address.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        address,
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  '₹$fee Fee',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardContainer(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w400),
            prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadedMedicinesSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Formulary Catalog • Tap medicine to prescribe',
                      style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
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
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Unable to load formulary catalog.', style: TextStyle(fontSize: 11, color: AppColors.error)),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: SizedBox(
                      width: 24,
                      height: 24,
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (fee is num && fee > 0)
                                        Text(
                                          '₹${fee.toInt()}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Wrap(
                                    spacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFFCBD5E1)),
                                        ),
                                        child: Text(
                                          type,
                                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                        ),
                                      ),
                                      Text(
                                        '$dosage • $duration',
                                        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                                      ),
                                      if (generic.isNotEmpty)
                                        Text(
                                          '($generic)',
                                          style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Actions
                            if (isAlreadyAdded)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCCFBF1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, size: 13, color: AppColors.primary),
                                    SizedBox(width: 2),
                                    Text(
                                      'Added',
                                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, size: 16, color: AppColors.textSecondary),
                                tooltip: 'Customize dose before adding',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showCustomizeMedicineDialog(med),
                              ),
                              ElevatedButton(
                                onPressed: () => _addPredefinedMedicine(med),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                child: const Text(
                                  '+ Add',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                            ],
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
    );
  }

  Widget _buildCustomMedicineEntryForm() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showCustomMedForm = !_showCustomMedForm),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _showCustomMedForm ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Can\'t find medicine? Enter custom medicine manually',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _showCustomMedForm ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showCustomMedForm) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _medNameController,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Medicine Name (e.g. Paracetamol 500mg)',
                            hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedMedType,
                              isExpanded: true,
                              items: _medicineTypes.map((t) {
                                return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)));
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedMedType = v!),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Dosage',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _medDosageController,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: const InputDecoration(
                                hintText: 'e.g. 1-0-1',
                                hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Duration',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _medDurationController,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: const InputDecoration(
                                hintText: 'e.g. 5 Days',
                                hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['1-0-1', '1-0-0', '0-0-1', '1-1-1', 'SOS'].map((dose) {
                      final isSelected = _medDosageController.text.trim() == dose;
                      return InkWell(
                        onTap: () => setState(() => _medDosageController.text = dose),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryContainer : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryContainer : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            dose,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'How medicine will be taken (Meal Timing / Instructions)',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _medInstructionsController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      hintText: 'e.g. After meals, Before meals',
                      hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _mealTimingOptions.map((opt) {
                      final isSelected = _medInstructionsController.text.trim().toLowerCase() == opt.toLowerCase();
                      return InkWell(
                        onTap: () => setState(() => _medInstructionsController.text = opt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryContainer : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryContainer : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            opt,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addMedicine,
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Colors.white),
                      label: const Text(
                        '+ Add Custom Medicine to Prescription',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
