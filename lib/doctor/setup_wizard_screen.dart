import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../mainshell.dart';
import '../services/setup_service.dart';
import '../theme/app_colors.dart';
import 'clinic_form_sheet.dart';
import 'predefined_medicines_screen.dart';

/// First-Time Setup Wizard Screen
/// Guides the doctor through initial clinic configuration and medicine catalogue setup.
/// Persists completion state directly into Firebase Cloud Firestore.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  bool _isLoading = true;
  bool _isFinalizing = false;
  int _clinicCount = 0;
  int _medicineCount = 0;
  bool _manualMedicineConfirmed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = await SetupService.checkSetupStatus(reconcileFirestore: true);
      if (!mounted) return;
      setState(() {
        _clinicCount = status.clinicCount;
        _medicineCount = status.medicineCount;
        _manualMedicineConfirmed = status.manualMedicineSetupConfirmed;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not sync setup status: $e';
      });
    }
  }

  bool get _isClinicTaskDone => _clinicCount > 0;
  bool get _isMedicineTaskDone => _medicineCount > 0 || _manualMedicineConfirmed;
  bool get _isReadyToLaunch => _isClinicTaskDone && _isMedicineTaskDone;
  int get _completedTasksCount => (_isClinicTaskDone ? 1 : 0) + (_isMedicineTaskDone ? 1 : 0);

  Future<void> _handleStartUsingApp() async {
    if (!_isReadyToLaunch || _isFinalizing) return;

    setState(() => _isFinalizing = true);
    try {
      // Re-verify authoritative status from Firestore before proceeding
      final verifiedStatus = await SetupService.checkSetupStatus(reconcileFirestore: true);
      if (!verifiedStatus.isComplete) {
        if (!mounted) return;
        setState(() {
          _clinicCount = verifiedStatus.clinicCount;
          _medicineCount = verifiedStatus.medicineCount;
          _manualMedicineConfirmed = verifiedStatus.manualMedicineSetupConfirmed;
          _isFinalizing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete both setup tasks before proceeding.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      await SetupService.completeSetup();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const mainshell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFinalizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finalizing setup: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openAddClinic() async {
    final result = await showAddEditClinicSheet(context);
    if (result != null) {
      await _refreshStatus();
    }
  }

  Future<void> _openImportMedicines() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return BulkImportSheet(
          onMedicinesImported: (imported) async {
            Navigator.pop(ctx);
            await _saveImportedMedicines(imported);
          },
          onSeedDefaults: () async {
            Navigator.pop(ctx);
            await _seedStarterMedicines();
          },
        );
      },
    );
    await _refreshStatus();
  }

  Future<void> _saveImportedMedicines(List<Map<String, dynamic>> medicines) async {
    if (medicines.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final collection = FirebaseFirestore.instance.collection('predefined_medicines');
      final batch = FirebaseFirestore.instance.batch();

      for (final m in medicines) {
        final doc = collection.doc();
        batch.set(doc, {
          'name': m['name'] ?? 'Unnamed Medicine',
          'genericName': m['genericName'] ?? '',
          'type': m['type'] ?? 'Tablet',
          'dosage': m['dosage'] ?? '1-0-1',
          'duration': m['duration'] ?? '5 Days',
          'fee': (m['fee'] as num?)?.toDouble() ?? 50.0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      await _refreshStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported ${medicines.length} medicines into Firebase!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk import error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _seedStarterMedicines() async {
    setState(() => _isLoading = true);
    try {
      final starterList = [
        {'name': 'Paracetamol 650mg', 'type': 'Tablet', 'dosage': '1-0-1', 'duration': '3 Days', 'fee': 30.0, 'genericName': 'Paracetamol'},
        {'name': 'Amoxicillin 500mg', 'type': 'Capsule', 'dosage': '1-0-1', 'duration': '5 Days', 'fee': 85.0, 'genericName': 'Amoxicillin'},
        {'name': 'Cetirizine 10mg', 'type': 'Tablet', 'dosage': '0-0-1', 'duration': '5 Days', 'fee': 25.0, 'genericName': 'Cetirizine'},
        {'name': 'Pantoprazole 40mg', 'type': 'Tablet', 'dosage': '1-0-0', 'duration': '7 Days', 'fee': 60.0, 'genericName': 'Pantoprazole'},
        {'name': 'Azithromycin 500mg', 'type': 'Tablet', 'dosage': '1-0-0', 'duration': '3 Days', 'fee': 110.0, 'genericName': 'Azithromycin'},
        {'name': 'Cough Relief Syrup', 'type': 'Syrup', 'dosage': '2 tsp TDS', 'duration': '5 Days', 'fee': 95.0, 'genericName': 'Dextromethorphan'},
      ];

      final collection = FirebaseFirestore.instance.collection('predefined_medicines');
      final batch = FirebaseFirestore.instance.batch();

      for (final m in starterList) {
        final doc = collection.doc();
        batch.set(doc, {
          ...m,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      await _refreshStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Starter clinical medicines loaded into Firebase!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading starter medicines: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _handleConfirmManualMedicines() async {
    setState(() => _isLoading = true);
    try {
      await SetupService.confirmManualMedicines();
      await _refreshStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Manual medicine entry confirmed. You can add medicines anytime later.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving preference: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent bypassing setup wizard
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.medical_services_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Clinical Setup Wizard',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
              tooltip: 'Refresh Status',
              onPressed: _isLoading ? null : _refreshStatus,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Checking Firebase setup status...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _refreshStatus,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card
                      _buildHeaderCard(),
                      const SizedBox(height: 18),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                              ),
                              TextButton(
                                onPressed: _refreshStatus,
                                child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Task 1: Clinic Setup Card
                      _buildClinicTaskCard(),
                      const SizedBox(height: 16),

                      // Task 2: Medicine Catalogue Setup Card
                      _buildMedicineTaskCard(),
                      const SizedBox(height: 28),

                      // Bottom CTA
                      _buildBottomCta(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final progress = _completedTasksCount / 2.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'FIRST-TIME CONFIGURATION',
              style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Welcome to Your Clinic Management System',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.25),
          ),
          const SizedBox(height: 8),
          const Text(
            'Set up your clinic and medicine catalogue before you start managing patients.',
            style: TextStyle(color: Color(0xFFE6FFFA), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),

          // Progress indicator bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_completedTasksCount of 2 tasks completed',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicTaskCard() {
    final isDone = _isClinicTaskDone;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
          width: isDone ? 1.5 : 1,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFFECFDF5) : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.apartment_rounded,
                  color: isDone ? const Color(0xFF10B981) : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Task 1: Clinic Setup',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 6),
                        _buildStatusBadge(isDone ? 'Completed' : 'Required', isDone),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDone
                          ? '$_clinicCount clinic location${_clinicCount > 1 ? 's' : ''} configured in Cloud Firestore'
                          : 'Configure at least one clinical branch or practice location.',
                      style: TextStyle(fontSize: 12, color: isDone ? const Color(0xFF047857) : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Actions
          if (!isDone) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAddClinic,
                icon: const Icon(Icons.add_location_alt_rounded, size: 18, color: Colors.white),
                label: const Text('Add Your First Clinic', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openAddClinic,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Another Clinic'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                        SizedBox(width: 6),
                        Text('Ready', style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicineTaskCard() {
    final isDone = _isMedicineTaskDone;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
          width: isDone ? 1.5 : 1,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.medication_rounded,
                  color: isDone ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Task 2: Medicine Catalogue',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 6),
                        _buildStatusBadge(isDone ? 'Completed' : 'Required', isDone),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _medicineCount > 0
                          ? '$_medicineCount medicine record${_medicineCount > 1 ? 's' : ''} in cloud catalogue'
                          : (_manualMedicineConfirmed
                              ? 'Manual medicine entry selected (can import anytime)'
                              : 'Import from Excel/CSV, load starter defaults, or opt for manual entry.'),
                      style: TextStyle(fontSize: 12, color: isDone ? const Color(0xFF047857) : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Actions
          if (!isDone) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openImportMedicines,
                icon: const Icon(Icons.file_upload_outlined, size: 18, color: Colors.white),
                label: const Text('Import Medicines (Excel / CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: _handleConfirmManualMedicines,
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.textSecondary),
                label: const Text(
                  'I will add medicines manually later',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PredefinedMedicinesScreen()),
                      ).then((_) => _refreshStatus());
                    },
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View Catalogue'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openImportMedicines,
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('Import More'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text, bool isCompleted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isCompleted ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted ? Icons.check_circle_rounded : Icons.pending_rounded,
            size: 11,
            color: isCompleted ? const Color(0xFF059669) : const Color(0xFFD97706),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isCompleted ? const Color(0xFF047857) : const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCta() {
    final ready = _isReadyToLaunch;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: ready && !_isFinalizing ? _handleStartUsingApp : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: ready ? AppColors.primary : const Color(0xFF94A3B8),
              disabledBackgroundColor: const Color(0xFFCBD5E1),
              elevation: ready ? 2 : 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isFinalizing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Start Using the App',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        if (!ready)
          const Text(
            'Complete both Clinic and Medicine setup tasks to unlock your practice dashboard.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            textAlign: TextAlign.center,
          )
        else
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                'Setup complete. Tap above to enter your clinical workspace.',
                style: TextStyle(color: Color(0xFF047857), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }
}
