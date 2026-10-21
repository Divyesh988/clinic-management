import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../services/auth_service.dart';
import '../services/clinic_service.dart';
import '../services/doctor_service.dart';
import '../theme/app_colors.dart';
import '../widgets/update_dialog.dart';
import 'clinic_form_sheet.dart';
import 'doctor_login_screen.dart';
import 'predefined_medicines_screen.dart';

class DoctorProfile extends StatefulWidget {
  const DoctorProfile({super.key});

  @override
  State<DoctorProfile> createState() => _DoctorProfileState();
}

// Backwards compatibility alias
// ignore: camel_case_types
typedef doctor_profile = DoctorProfile;

class _DoctorProfileState extends State<DoctorProfile> {
  bool _isLoading = false;
  bool _isCheckingUpdate = false;

  Future<void> _checkForAppUpdates() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    try {
      final result = await AppUpdateService.checkForUpdates(forceRefresh: true);
      if (!mounted) return;
      if (result.status == AppUpdateStatus.optionalUpdateAvailable && result.config != null) {
        OptionalUpdateDialog.show(
          context,
          currentVersion: result.currentVersion,
          config: result.config!,
        );
      } else if (result.status == AppUpdateStatus.mandatoryUpdateRequired && result.config != null) {
        // Automatically handled by the root builder stack
      } else if (result.status == AppUpdateStatus.upToDate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CliniqCare is up to date (v${result.currentVersion.displayString})'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Unable to complete update check.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  Map<String, dynamic> _profileData = {
    'name': 'Dr. Practitioner',
    'degree': 'MBBS',
    'speciality': 'Consultant Physician',
    'regNumber': '',
    'experience': '',
    'phone': '',
    'email': '',
    'clinicName': 'My Clinic',
    'clinicAddress': '',
    'consultationFee': 500,
    'workingHours': 'Mon - Sat: 09:00 AM - 01:00 PM, 05:00 PM - 08:30 PM',
    'bio': 'Specializing in patient-centered primary healthcare and clinical care.',
  };

  @override
  void initState() {
    super.initState();
    _fetchDoctorProfile();
  }

  Future<void> _fetchDoctorProfile() async {
    try {
      final profile = await DoctorService.ensureDoctorProfile();
      if (profile.isNotEmpty && mounted) {
        setState(() {
          _profileData = {..._profileData, ...profile};
        });
      }
    } catch (e) {
      debugPrint('Error fetching doctor profile: $e');
    }
  }

  Future<void> _saveDoctorProfile(Map<String, dynamic> updated) async {
    setState(() => _isLoading = true);
    try {
      final doctorId = DoctorService.currentDoctorId;
      final targetDocId = (doctorId.isNotEmpty && doctorId != 'doc_main') ? doctorId : 'main';

      final firestore = FirebaseFirestore.instance;

      // 1. Update doctor_profile/{targetDocId}
      await firestore.collection('doctor_profile').doc(targetDocId).set({
        ...updated,
        'doctorId': targetDocId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. If authenticated doctor, also update canonical doctors/{targetDocId}
      if (targetDocId != 'main') {
        final updateAccount = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (updated['name'] != null) updateAccount['displayName'] = updated['name'];
        if (updated['phone'] != null) updateAccount['phone'] = updated['phone'];
        if (updated['speciality'] != null) updateAccount['specialty'] = updated['speciality'];
        if (updated['degree'] != null) updateAccount['degree'] = updated['degree'];
        if (updated['regNumber'] != null) updateAccount['regNumber'] = updated['regNumber'];
        await firestore.collection('doctors').doc(targetDocId).set(updateAccount, SetOptions(merge: true));
      } else {
        // Legacy fallback mirror
        await firestore.collection('doctor_profile').doc('main').set({
          ...updated,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        setState(() {
          _profileData = {..._profileData, ...updated};
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Doctor profile updated successfully!')),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile. Please try again.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showEditProfileSheet() {
    final nameCtrl = TextEditingController(text: _profileData['name']?.toString() ?? '');
    final degreeCtrl = TextEditingController(text: _profileData['degree']?.toString() ?? '');
    final specCtrl = TextEditingController(text: _profileData['speciality']?.toString() ?? '');
    final regCtrl = TextEditingController(text: _profileData['regNumber']?.toString() ?? '');
    final expCtrl = TextEditingController(text: _profileData['experience']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: _profileData['phone']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: _profileData['email']?.toString() ?? '');
    final clinicCtrl = TextEditingController(text: _profileData['clinicName']?.toString() ?? '');
    final addressCtrl = TextEditingController(text: _profileData['clinicAddress']?.toString() ?? '');
    final feeCtrl = TextEditingController(text: _profileData['consultationFee']?.toString() ?? '500');
    final hoursCtrl = TextEditingController(text: _profileData['workingHours']?.toString() ?? '');
    final bioCtrl = TextEditingController(text: _profileData['bio']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
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
                    const Text(
                      'Edit Doctor Profile',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Personal Information', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: degreeCtrl,
                                decoration: const InputDecoration(labelText: 'Degree / Qualifications', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: expCtrl,
                                decoration: const InputDecoration(labelText: 'Experience', hintText: 'e.g. 14 Years', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: specCtrl,
                          decoration: const InputDecoration(labelText: 'Speciality / Designation', prefixIcon: Icon(Icons.medical_services_outlined), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: regCtrl,
                          decoration: const InputDecoration(labelText: 'Medical Council Reg No.', prefixIcon: Icon(Icons.verified_outlined), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 20),
                        const Text('Clinic & Practice Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: clinicCtrl,
                          decoration: const InputDecoration(labelText: 'Clinic Name *', prefixIcon: Icon(Icons.local_hospital_outlined), border: OutlineInputBorder()),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: addressCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Clinic Address', prefixIcon: Icon(Icons.location_on_outlined), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: feeCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Fee (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded), border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: hoursCtrl,
                          decoration: const InputDecoration(labelText: 'Working Hours & Availability', prefixIcon: Icon(Icons.access_time_rounded), border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: bioCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'About Doctor / Clinical Philosophy', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (!formKey.currentState!.validate()) return;
                              Navigator.pop(ctx);
                              final updated = {
                                'name': nameCtrl.text.trim(),
                                'degree': degreeCtrl.text.trim(),
                                'speciality': specCtrl.text.trim(),
                                'regNumber': regCtrl.text.trim(),
                                'experience': expCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim(),
                                'email': emailCtrl.text.trim(),
                                'clinicName': clinicCtrl.text.trim(),
                                'clinicAddress': addressCtrl.text.trim(),
                                'consultationFee': double.tryParse(feeCtrl.text.trim()) ?? 500.0,
                                'workingHours': hoursCtrl.text.trim(),
                                'bio': bioCtrl.text.trim(),
                              };
                              _saveDoctorProfile(updated);
                            },
                            icon: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                            label: const Text('Save Profile Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // CLINIC MANAGEMENT (DATABASE BACKED)
  // ==========================================
  Future<void> _setPrimaryClinic(String docId, Map<String, dynamic> clinic) async {
    setState(() => _isLoading = true);
    try {
      await ClinicService.setPrimaryClinic(docId);
      if (mounted) {
        setState(() {
          _profileData['clinicName'] = clinic['name'];
          _profileData['clinicAddress'] = clinic['address'];
          _profileData['consultationFee'] = clinic['consultationFee'];
          _profileData['workingHours'] = clinic['workingHours'];
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Active clinic switched to ${clinic['name']}!')),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error setting primary clinic. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _deleteClinic(String docId, String clinicName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Delete Clinic', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: Text('Are you sure you want to delete "$clinicName"?\nPatient records already associated with this clinic will remain preserved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                 await ClinicService.deleteClinic(docId);
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$clinicName deleted successfully'), backgroundColor: AppColors.primary),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete clinic. Please try again.'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEditClinicDialog([Map<String, dynamic>? existing, String? docId]) async {
    Map<String, dynamic>? initialData;
    if (existing != null) {
      initialData = Map<String, dynamic>.from(existing);
      if (docId != null) initialData['docId'] = docId;
    }
    final saved = await showAddEditClinicSheet(context, initialData: initialData);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${saved['name']} saved successfully!'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _seedInitialClinic() async {
    setState(() => _isLoading = true);
    try {
      await ClinicService.saveClinic(
        name: _profileData['clinicName'] ?? 'Main Clinic',
        address: _profileData['clinicAddress'] ?? '',
        phone: _profileData['phone'] ?? '',
        email: _profileData['email'] ?? (AuthService.currentUser?.email ?? ''),
        consultationFee: (_profileData['consultationFee'] as num?)?.toDouble() ?? 500.0,
        workingHours: _profileData['workingHours'] ?? 'Mon - Sat: 09:00 AM - 01:00 PM, 05:00 PM - 08:30 PM',
        isPrimary: true,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initial clinic location initialized!'), backgroundColor: AppColors.primary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error initializing clinic. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out of your doctor workspace?\n\nYou will need your email and password to log back in.',
          style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);
      try {
        await AuthService.signOut();
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DoctorLoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to sign out. Please try again.'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Widget _buildClinicsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Clinics & Locations',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Clinic-wise records',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showAddEditClinicDialog(),
                icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                label: const Text('Add Clinic', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: ClinicService.streamDoctorClinics(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Unable to load clinics.'));
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }

              final clinics = snapshot.data ?? [];
              if (clinics.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.add_business_outlined, size: 36, color: AppColors.textSecondary),
                      const SizedBox(height: 8),
                      const Text(
                        'No clinics added yet',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Add your clinic locations to organize and store patient records clinic-wise.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _seedInitialClinic,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
                        label: Text('Initialize "${_profileData['clinicName']}"', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: clinics.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final clinic = clinics[i];
                  final docId = clinic['docId']?.toString() ?? '';
                  final name = clinic['name']?.toString() ?? 'Unnamed Clinic';
                  final address = clinic['address']?.toString() ?? '';
                  final phone = clinic['phone']?.toString() ?? '';
                  final fee = clinic['consultationFee'];
                  final hours = clinic['workingHours']?.toString() ?? '';
                  final isPrimary = clinic['isPrimary'] == true;

                  return Container(
                    decoration: BoxDecoration(
                      color: isPrimary ? const Color(0xFFF0FDFA) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isPrimary ? AppColors.primary : const Color(0xFFE2E8F0),
                        width: isPrimary ? 1.5 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isPrimary ? AppColors.primary : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.apartment_rounded,
                                size: 18,
                                color: isPrimary ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isPrimary) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
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
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                              tooltip: 'Edit Clinic',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _showAddEditClinicDialog(clinic, docId),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                              tooltip: 'Delete Clinic',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteClinic(docId, name),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (fee != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Text('Fee: ₹$fee', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              ),
                            if (hours.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Text(hours, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                              ),
                            if (phone.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Text(phone, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                              ),
                          ],
                        ),
                        if (!isPrimary) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _setPrimaryClinic(docId, clinic),
                              icon: const Icon(Icons.star_outline_rounded, size: 15, color: AppColors.primary),
                              label: const Text('Set as Active Clinic', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(color: AppColors.primary, backgroundColor: AppColors.primarySurface),
                ),
              _buildTopHeader(),
              const SizedBox(height: 16),
              _buildDoctorHeroCard(),
              const SizedBox(height: 16),
              _buildStatsRow(),
              const SizedBox(height: 20),

              // ==========================================
              // OPERATION 2: PREDEFINED MEDICINES & EXCEL
              // ==========================================
              _buildPredefinedMedicinesHubCard(),
              const SizedBox(height: 20),

              // ==========================================
              // OPERATION 3: CLINICS MANAGEMENT (DATABASE)
              // ==========================================
              _buildClinicsSection(),
              const SizedBox(height: 20),

              // ==========================================
              // OPERATION 1: PROFILE MANAGEMENT SECTIONS
              // ==========================================
              _buildSectionTitle('Active Clinic Quick Info'),
              const SizedBox(height: 10),
              _buildClinicInfoCard(),
              const SizedBox(height: 16),
              _buildSectionTitle('Professional Registration & Bio'),
              const SizedBox(height: 10),
              _buildProfessionalCard(),
              const SizedBox(height: 16),
              _buildSectionTitle('SaaS Account & Security'),
              const SizedBox(height: 10),
              _buildAccountSecurityCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Doctor Profile & Setting',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4),
              ),
              Text(
                'Manage clinic identity, formulary & bulk medicines',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _showEditProfileSheet,
              tooltip: 'Edit Profile',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primarySurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _handleSignOut,
              tooltip: 'Sign Out',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFEE2E2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDoctorHeroCard() {
    final initials = (_profileData['name']?.toString() ?? 'DR')
        .split(' ')
        .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
        .take(2)
        .join();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C1E28), Color(0xFF1E3A4C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C1E28).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    initials.isEmpty ? 'DR' : initials,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _profileData['name']?.toString() ?? (AuthService.currentAccount?.displayName ?? 'Doctor'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded, color: Color(0xFF14B8A6), size: 18),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _profileData['degree']?.toString() ?? 'MBBS, MD',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _profileData['speciality']?.toString() ?? 'Consultant Physician',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF38BDF8), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_hospital_outlined, size: 15, color: Color(0xFF14B8A6)),
                  const SizedBox(width: 6),
                  Text(
                    _profileData['clinicName']?.toString() ?? 'Primary Clinic',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                ],
              ),
              InkWell(
                onTap: _showEditProfileSheet,
                child: Row(
                  children: const [
                    Text('Edit Details', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF14B8A6))),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF14B8A6)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatTile('Experience', _profileData['experience']?.toString() ?? '14 Yrs', Icons.military_tech_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _buildStatTile('Consult Fee', '₹${_profileData['consultationFee'] ?? 500}', Icons.currency_rupee_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _buildStatTile('Status', 'Available', Icons.circle, iconColor: AppColors.success)),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon, {Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor ?? AppColors.primary),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  // ==========================================================
  // OPERATION 2: PREDEFINED MEDICINES & EXCEL FORMULARY CARD
  // ==========================================================
  Widget _buildPredefinedMedicinesHubCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFCCFBF1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.medication_liquid_rounded, size: 24, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Predefined Medicines & Formulary',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Manage reusable prescription medicines & bulk Excel upload',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('predefined_medicines').snapshots(),
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          '$count Medicines Available in Formulary',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Live Sync', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PredefinedMedicinesScreen()),
                    );
                  },
                  icon: const Icon(Icons.format_list_bulleted_rounded, size: 16, color: Colors.white),
                  label: const Text('Manage Formulary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PredefinedMedicinesScreen()),
                  );
                },
                icon: const Icon(Icons.upload_file_rounded, size: 16, color: AppColors.primary),
                label: const Text('Excel Upload', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    );
  }

  Widget _buildClinicInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoRow(Icons.local_hospital_outlined, 'Clinic Name', _profileData['clinicName']?.toString() ?? 'Main Clinic'),
          const Divider(height: 16),
          _buildInfoRow(Icons.location_on_outlined, 'Address', _profileData['clinicAddress']?.toString() ?? 'Not specified'),
          const Divider(height: 16),
          _buildInfoRow(Icons.phone_outlined, 'Contact Phone', _profileData['phone']?.toString() ?? 'Not specified'),
          const Divider(height: 16),
          _buildInfoRow(Icons.email_outlined, 'Official Email', _profileData['email']?.toString() ?? (AuthService.currentUser?.email ?? 'Not specified')),
          const Divider(height: 16),
          _buildInfoRow(Icons.access_time_rounded, 'OPD Hours', _profileData['workingHours']?.toString() ?? '09:00 AM - 08:30 PM'),
        ],
      ),
    );
  }

  Widget _buildProfessionalCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.verified_outlined, 'Medical Registration', _profileData['regNumber']?.toString() ?? 'GMC-84291'),
          const Divider(height: 16),
          _buildInfoRow(Icons.school_outlined, 'Qualifications', _profileData['degree']?.toString() ?? 'MBBS, MD'),
          const Divider(height: 16),
          const Text('About & Clinical Philosophy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            _profileData['bio']?.toString() ?? 'Specializing in comprehensive internal medicine and chronic care.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSecurityCard() {
    final user = AuthService.currentUser;
    final email = user?.email ?? (_profileData['email']?.toString() ?? 'doctor@clinic.com');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_user_outlined, color: Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SaaS Doctor Account',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    Text(
                      email,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
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
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(color: Color(0xFF166534), fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // App Updates Section
          Row(
            children: [
              const Icon(Icons.system_update_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CliniqCare Mobile',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    Text(
                      'Version 1.0.0 (build 1)',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _isCheckingUpdate ? null : _checkForAppUpdates,
                icon: _isCheckingUpdate
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Check Updates', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _handleSignOut,
            icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 16),
            label: const Text(
              'Sign Out of Clinic Workspace',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              backgroundColor: const Color(0xFFFFF1F2),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

