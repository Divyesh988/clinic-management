import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/clinic_service.dart';
import '../services/doctor_service.dart';
import '../theme/app_colors.dart';
import 'add_patient_screen.dart';
import 'predefined_medicines_screen.dart';

class Dashboard extends StatefulWidget {
  final ValueChanged<int>? onNavigateTab;

  const Dashboard({
    super.key,
    this.onNavigateTab,
  });

  @override
  State<Dashboard> createState() => _DashboardState();
}

// Backwards compatibility alias
// ignore: camel_case_types
typedef dashboard = Dashboard;

class _DashboardState extends State<Dashboard> {
  String? _selectedClinicId;

  // ────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final doctorId = DoctorService.currentDoctorId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopHeader(),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('patients')
                    .where('doctorId', isEqualTo: doctorId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final allDocs = snapshot.data?.docs ?? [];
                  final allPatients = allDocs.map((d) {
                    final data = Map<String, dynamic>.from(d.data());
                    data['_docId'] = d.id;
                    return data;
                  }).toList();

                  // Filter by clinic if one is chosen
                  final patients = _selectedClinicId == null
                      ? allPatients
                      : allPatients.where((p) {
                          final cId = p['clinicId']?.toString() ?? '';
                          return cId == _selectedClinicId;
                        }).toList();

                  // Sort by createdAt descending (most recent first)
                  patients.sort((a, b) {
                    final dtA = _parseDateTime(a['createdAt']);
                    final dtB = _parseDateTime(b['createdAt']);
                    if (dtA == null && dtB == null) return 0;
                    if (dtA == null) return 1;
                    if (dtB == null) return -1;
                    return dtB.compareTo(dtA);
                  });

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        _buildGreetingSection(),
                        const SizedBox(height: 14),
                        _buildClinicSelectorPills(),
                        const SizedBox(height: 20),
                        _buildPerformancePulseSection(patients),
                        const SizedBox(height: 20),
                        _buildClinicalRadarSection(patients),
                        const SizedBox(height: 22),
                        _buildQueueTimelineSection(patients),
                        const SizedBox(height: 22),
                        _buildPracticeDynamicsSection(patients),
                        const SizedBox(height: 80),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 1. TOP HEADER (Clinic Selector, Alerts, Profile)
  // ==========================================
  Widget _buildTopHeader() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ClinicService.streamDoctorClinics(),
      builder: (context, snapshot) {
        final clinics = snapshot.data ?? [];
        String activeLabel = 'All My Clinics';
        if (_selectedClinicId != null) {
          final matched = clinics.firstWhere(
            (c) => c['docId'] == _selectedClinicId,
            orElse: () => <String, dynamic>{},
          );
          if (matched.isNotEmpty) {
            activeLabel = matched['name']?.toString() ?? 'Clinic';
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Clinic Selector Pill
              PopupMenuButton<String?>(
                tooltip: 'Select Clinic',
                onSelected: (val) {
                  setState(() {
                    _selectedClinicId = val;
                  });
                },
                itemBuilder: (ctx) {
                  return [
                    const PopupMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          Icon(Icons.domain_rounded, size: 16, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('All My Clinics', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    ...clinics.map((c) => PopupMenuItem<String?>(
                          value: c['docId']?.toString(),
                          child: Row(
                            children: [
                              Icon(
                                c['isPrimary'] == true ? Icons.star_rounded : Icons.local_hospital_rounded,
                                size: 16,
                                color: c['isPrimary'] == true ? AppColors.warning : AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c['name']?.toString() ?? 'Clinic',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (c['isPrimary'] == true)
                                const Text(' (Primary)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                            ],
                          ),
                        )),
                  ];
                },
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
                          activeLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
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
              ),

              // Actions: Quick Add Patient + Doctor Avatar
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddPatientScreen(
                            initialClinicId: _selectedClinicId,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Add',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => widget.onNavigateTab?.call(3), // Navigate to Profile
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 2. GREETING & DATE SECTION (Dynamic Stream)
  // ==========================================
  Widget _buildGreetingSection() {
    final now = DateTime.now();
    final hour = now.hour;
    final timeGreeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final formattedDate = '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';

    return StreamBuilder<Map<String, dynamic>>(
      stream: DoctorService.streamDoctorProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? {};
        final doctorName = profile['name']?.toString() ?? 'Doctor';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CLINICAL DASHBOARD',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Live Feed',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$timeGreeting, $doctorName 👋',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.22,
                  letterSpacing: -0.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                formattedDate,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 3. HORIZONTAL CLINIC SELECTOR PILLS
  // ==========================================
  Widget _buildClinicSelectorPills() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ClinicService.streamDoctorClinics(),
      builder: (context, snapshot) {
        final clinics = snapshot.data ?? [];
        if (clinics.isEmpty) {
          return const SizedBox.shrink();
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildClinicPill(
                id: null,
                icon: Icons.domain_rounded,
                title: 'All Clinics',
              ),
              ...clinics.map((c) {
                final id = c['docId']?.toString();
                final name = c['name']?.toString() ?? 'Clinic';
                final isPrimary = c['isPrimary'] == true;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildClinicPill(
                    id: id,
                    icon: isPrimary ? Icons.star_rounded : Icons.local_hospital_rounded,
                    title: name,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClinicPill({
    required String? id,
    required IconData icon,
    required String title,
  }) {
    final isSelected = _selectedClinicId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedClinicId = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryContainer : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 4. PERFORMANCE PULSE SECTION (Real-Time)
  // ==========================================
  Widget _buildPerformancePulseSection(List<Map<String, dynamic>> patients) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 7));

    final totalEnrolled = patients.length;
    int thisWeekCount = 0;
    int todayCount = 0;
    int paidCount = 0;
    int pendingCount = 0;
    int partialCount = 0;

    for (final p in patients) {
      final dt = _parseDateTime(p['createdAt']);
      if (dt != null) {
        if (dt.isAfter(weekStart)) thisWeekCount++;
        if (dt.isAfter(todayStart)) todayCount++;
      }
      final status = (p['billStatus']?.toString() ?? 'Pending').toLowerCase();
      if (status == 'paid') {
        paidCount++;
      } else if (status == 'partial') {
        partialCount++;
      } else {
        pendingCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Performance Pulse',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Live metrics',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Card 1: Total Enrolled Patients
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.groups_rounded,
                              size: 19,
                              color: AppColors.secondaryPurple,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 11,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  totalEnrolled > 0 ? 'Active' : 'New',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Total Enrolled Patients',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$totalEnrolled',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '+$thisWeekCount this past week',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Card 2: Today's Consultations / Active Visits
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Today’s Patients',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$todayCount',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            todayCount == 1 ? 'registered' : 'total today',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _buildMiniStatusPill('$paidCount Paid', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                          const SizedBox(width: 4),
                          _buildMiniStatusPill('$pendingCount Due', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
                          if (partialCount > 0) ...[
                            const SizedBox(width: 4),
                            _buildMiniStatusPill('$partialCount Part', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusPill(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  // ==========================================
  // 5. CLINICAL RADAR SECTION (Real-Time Alerts)
  // ==========================================
  Widget _buildClinicalRadarSection(List<Map<String, dynamic>> patients) {
    double totalPending = 0;
    int pendingPatientsCount = 0;
    for (final p in patients) {
      final pending = (p['pendingAmount'] as num?)?.toDouble() ?? 0;
      if (pending > 0) {
        totalPending += pending;
        pendingPatientsCount++;
      }
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayPatients = patients.where((p) {
      final dt = _parseDateTime(p['createdAt']);
      return dt != null && dt.isAfter(todayStart);
    }).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Clinical Radar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                'Live Action items',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Radar Item 1: Pending Balance Alert
          _buildRadarCard(
            icon: Icons.pending_actions_rounded,
            iconBg: pendingPatientsCount > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFCCFBF1),
            iconColor: pendingPatientsCount > 0 ? AppColors.error : AppColors.primary,
            title: pendingPatientsCount > 0
                ? '₹${totalPending.toInt()} Uncollected Dues'
                : 'All Accounts Cleared',
            badgeText: pendingPatientsCount > 0 ? '$pendingPatientsCount Patients' : '100% Settled',
            badgeBg: pendingPatientsCount > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFCCFBF1),
            badgeColor: pendingPatientsCount > 0 ? AppColors.error : AppColors.primary,
            subtitle: pendingPatientsCount > 0
                ? 'Tap to review outstanding balances in patient directory'
                : 'Zero outstanding dues across recorded visits',
            onTap: () => widget.onNavigateTab?.call(1), // Switch to Patients tab
            actionWidget: _buildCircleArrow(),
          ),
          const SizedBox(height: 10),

          // Radar Item 2: Today's Consultations Alert
          _buildRadarCard(
            icon: Icons.schedule_rounded,
            iconBg: const Color(0xFFCCFBF1),
            iconColor: AppColors.primary,
            title: '$todayPatients Consultations Today',
            badgeText: 'Today',
            badgeBg: const Color(0xFFCCFBF1),
            badgeColor: AppColors.primary,
            subtitle: todayPatients > 0
                ? 'Active patient records logged today'
                : 'No patients registered yet today. Tap + to add',
            onTap: () {
              if (todayPatients > 0) {
                widget.onNavigateTab?.call(1);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddPatientScreen()),
                );
              }
            },
            actionWidget: _buildCircleArrow(),
          ),
          const SizedBox(height: 10),

          // Radar Item 3: Medicine Catalogue & Inventory
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('predefined_medicines').snapshots(),
            builder: (context, snap) {
              final medCount = snap.data?.size ?? 0;
              return _buildRadarCard(
                icon: Icons.medication_rounded,
                iconBg: const Color(0xFFF5F3FF),
                iconColor: const Color(0xFF7C3AED),
                title: '$medCount Formulary Medicines',
                badgeText: 'Catalogue',
                badgeBg: const Color(0xFFF5F3FF),
                badgeColor: const Color(0xFF7C3AED),
                subtitle: 'Tap to manage predefined medicines & import Excel/CSV',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PredefinedMedicinesScreen()),
                  );
                },
                actionWidget: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Manage',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRadarCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String badgeText,
    required Color badgeBg,
    required Color badgeColor,
    required String subtitle,
    required Widget actionWidget,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
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
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            actionWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildCircleArrow() {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  // ==========================================
  // 6. QUEUE TIMELINE SECTION (Real-Time Live Queue)
  // ==========================================
  Widget _buildQueueTimelineSection(List<Map<String, dynamic>> patients) {
    // Show top 4 recent registered patients
    final queuePatients = patients.take(4).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Queue Timeline',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => widget.onNavigateTab?.call(1), // Switch to Patients tab
                child: Row(
                  children: [
                    Text(
                      'View All (${patients.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (queuePatients.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 36, color: AppColors.textMuted),
                    const SizedBox(height: 10),
                    const Text(
                      'No Patients Queued',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Newly added patients for this clinic will appear here live.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddPatientScreen(
                              initialClinicId: _selectedClinicId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Register Patient'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(queuePatients.length, (idx) {
              final p = queuePatients[idx];
              final isFirst = idx == 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildQueuePatientCard(p, slotNumber: idx + 1, isHighlighted: isFirst),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildQueuePatientCard(
    Map<String, dynamic> p, {
    required int slotNumber,
    bool isHighlighted = false,
  }) {
    final name = p['name']?.toString() ?? 'Unnamed Patient';
    final initials = p['initials']?.toString().isNotEmpty == true
        ? p['initials'].toString()
        : (name.isNotEmpty ? name.substring(0, math.min(2, name.length)).toUpperCase() : 'PT');
    final age = p['age']?.toString() ?? '—';
    final gender = (p['gender']?.toString().isNotEmpty == true)
        ? p['gender'].toString().substring(0, 1).toUpperCase()
        : 'M';
    final diagnosis = (p['diagnosis']?.toString().isNotEmpty == true &&
            p['diagnosis'] != 'Under Clinical Review')
        ? p['diagnosis']
        : (p['disease']?.toString().isNotEmpty == true ? p['disease'] : 'General Consultation');

    final dt = _parseDateTime(p['createdAt']);
    final timeStr = dt != null ? _formatTimeShort(dt) : 'Today';

    final billStatus = p['billStatus']?.toString() ?? 'Paid';
    final pending = (p['pendingAmount'] as num?)?.toDouble() ?? 0;
    final totalBilled = (p['totalBilled'] as num?)?.toDouble() ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted ? const Color(0xFFCCEBE7) : AppColors.border,
          width: isHighlighted ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (isHighlighted)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          else
            ...AppColors.cardShadow,
        ],
      ),
      child: Stack(
        children: [
          // Indicator line on the left
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: isHighlighted ? 4.0 : 3.5,
              decoration: BoxDecoration(
                color: isHighlighted ? AppColors.primary : const Color(0xFF14B8A6),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isHighlighted ? const Color(0xFFCCFBF1) : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isHighlighted ? AppColors.primary : const Color(0xFF334155),
                          ),
                        ),
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$age $gender',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            diagnosis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Slot #$slotNumber',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          billStatus == 'Paid'
                              ? Icons.check_circle_outline_rounded
                              : Icons.schedule_rounded,
                          size: 15,
                          color: billStatus == 'Paid' ? AppColors.primary : AppColors.warning,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          pending > 0 ? 'Due ₹${pending.toInt()}' : 'Paid ₹${totalBilled.toInt()}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: pending > 0 ? AppColors.warning : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _showPatientQuickView(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isHighlighted ? AppColors.primarySurface : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'View Record',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isHighlighted ? AppColors.primary : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPatientQuickView(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primarySurface,
                  child: Text(
                    p['initials']?.toString() ?? 'PT',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name']?.toString() ?? 'Patient',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      Text(
                        '${p['age'] ?? '—'} Yrs • ${p['gender'] ?? '—'} • ${p['phone'] ?? '—'}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 0, color: AppColors.borderSubtle),
            const SizedBox(height: 14),
            _buildDetailRow('Diagnosis', p['diagnosis']?.toString() ?? p['disease']?.toString() ?? '—'),
            const SizedBox(height: 8),
            _buildDetailRow('Clinic', p['clinic']?.toString() ?? 'Default Clinic'),
            const SizedBox(height: 8),
            _buildDetailRow('Bill Status', '${p['billStatus'] ?? 'Paid'} (Total: ₹${p['totalBilled'] ?? 0})'),
            const SizedBox(height: 8),
            _buildDetailRow('Address', p['address']?.toString() ?? '—'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onNavigateTab?.call(1); // Switch to Patients directory
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Open in Patient Directory', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  // ==========================================
  // 7. PRACTICE DYNAMICS SECTION (Real-Time 7-Day Chart & Formulary)
  // ==========================================
  Widget _buildPracticeDynamicsSection(List<Map<String, dynamic>> patients) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Compute last 7 days daily counts
    final dailyCounts = List<int>.filled(7, 0);
    final dayLabels = <String>[];
    const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      if (i == 0) {
        dayLabels.add('Today');
      } else {
        dayLabels.add(weekdaysShort[d.weekday - 1]);
      }
    }

    for (final p in patients) {
      final dt = _parseDateTime(p['createdAt']);
      if (dt == null) continue;
      final pDay = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(pDay).inDays;
      if (diff >= 0 && diff < 7) {
        dailyCounts[6 - diff]++;
      }
    }

    final total7DayPatients = dailyCounts.fold(0, (a, b) => a + b);

    // Aggregate Top Dispensed Medicines from patients
    final medCounts = <String, int>{};
    final medTypes = <String, String>{};

    for (final p in patients) {
      final rawMeds = p['medicines'];
      if (rawMeds is List) {
        for (final m in rawMeds) {
          if (m is Map) {
            final name = m['name']?.toString().trim() ?? '';
            final type = m['type']?.toString().trim() ?? 'Tablet';
            if (name.isNotEmpty) {
              medCounts[name] = (medCounts[name] ?? 0) + 1;
              medTypes[name] = type;
            }
          }
        }
      }
    }

    final sortedMeds = medCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topMeds = sortedMeds.take(3).toList();
    final maxMedCount = topMeds.isNotEmpty ? topMeds.first.value : 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Practice Dynamics',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '7-Day Analysis',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Card 1: Consultation Volume Chart (Dynamic Real Data)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Consultation Volume',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$total7DayPatients Patients',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.trending_up_rounded,
                            size: 13,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            total7DayPatients > 0
                                ? '${(total7DayPatients / 7.0).toStringAsFixed(1)} /day'
                                : '0 /day',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Area Spline Chart (Dynamically painted with real numbers)
                SizedBox(
                  height: 90,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _PracticeSplineChartPainter(dailyCounts: dailyCounts),
                  ),
                ),
                const SizedBox(height: 8),

                // Chart X-Axis Days
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(dayLabels.length, (i) {
                    return _ChartDayLabel(
                      label: dayLabels[i],
                      isToday: i == dayLabels.length - 1,
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Card 2: Top Dispensed Formulary (Real-Time Prescriptions)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Top Prescribed Formulary',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Live Records',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (topMeds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'No medicines prescribed yet in recorded visits.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ...List.generate(topMeds.length, (i) {
                    final med = topMeds[i];
                    final rank = i + 1;
                    final count = med.value;
                    final fillRatio = maxMedCount > 0 ? count / maxMedCount : 0.0;
                    return Padding(
                      padding: EdgeInsets.only(bottom: i < topMeds.length - 1 ? 12 : 0),
                      child: _buildFormularyItem(
                        rank: rank,
                        medicineName: med.key,
                        category: medTypes[med.key] ?? 'Tablet',
                        units: '$count Rx',
                        fillRatio: fillRatio,
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularyItem({
    required int rank,
    required String medicineName,
    required String category,
    required String units,
    required double fillRatio,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicineName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              units,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 4,
            width: double.infinity,
            color: const Color(0xFFE2E8F0),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fillRatio.clamp(0.05, 1.0),
              child: Container(
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────────────────────────
  DateTime? _parseDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _formatTimeShort(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

class _ChartDayLabel extends StatelessWidget {
  final String label;
  final bool isToday;

  const _ChartDayLabel({
    required this.label,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
        color: isToday ? AppColors.primary : AppColors.textMuted,
      ),
    );
  }
}

/// Custom Spline and Area Gradient Chart dynamically painted with real 7-day counts
class _PracticeSplineChartPainter extends CustomPainter {
  final List<int> dailyCounts;

  _PracticeSplineChartPainter({required this.dailyCounts});

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = math.max(dailyCounts.fold(0, math.max), 1);

    // Compute 7 points from normalized counts
    final points = <Offset>[];
    for (int i = 0; i < 7; i++) {
      final x = (i / 6.0) * size.width;
      final count = i < dailyCounts.length ? dailyCounts[i] : 0;
      // Map count to y: higher count -> smaller y (closer to top of container)
      final norm = count / (maxVal * 1.3);
      final y = size.height * (0.85 - (norm * 0.65)).clamp(0.15, 0.85);
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    // Fill path underneath
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF14B8A6).withValues(alpha: 0.35),
          const Color(0xFF14B8A6).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Line stroke
    final strokePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);

    // Highlight dot on the last point ("Today")
    final lastPoint = points.last;

    // Outer glow
    final glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 6.5, glowPaint);

    // Inner solid dot
    final dotPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 3.5, dotPaint);

    final centerWhiteDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 1.5, centerWhiteDot);
  }

  @override
  bool shouldRepaint(covariant _PracticeSplineChartPainter oldDelegate) {
    if (oldDelegate.dailyCounts.length != dailyCounts.length) return true;
    for (int i = 0; i < dailyCounts.length; i++) {
      if (oldDelegate.dailyCounts[i] != dailyCounts[i]) return true;
    }
    return false;
  }
}
