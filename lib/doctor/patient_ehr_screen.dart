import 'package:flutter/material.dart';
import '../services/ehr_models.dart';
import '../services/ehr_service.dart';
import '../theme/app_colors.dart';
import 'add_visit_screen.dart';

/// Central Electronic Health Record (EHR) Profile & Longitudinal Timeline Screen.
/// Displays permanent patient demographics, chronological visit timeline,
/// encounter details, and side-by-side encounter comparison.
class PatientEhrScreen extends StatefulWidget {
  final Map<String, dynamic> patient;

  const PatientEhrScreen({
    super.key,
    required this.patient,
  });

  @override
  State<PatientEhrScreen> createState() => _PatientEhrScreenState();
}

class _PatientEhrScreenState extends State<PatientEhrScreen> {
  late String _patientId;
  late String _patientName;
  late Map<String, dynamic> _patientData;

  @override
  void initState() {
    super.initState();
    _patientData = Map<String, dynamic>.from(widget.patient);
    _patientId = _patientData['id']?.toString() ?? _patientData['docId']?.toString() ?? 'PT-00000';
    _patientName = _patientData['name']?.toString() ?? 'Patient';
  }

  void _openNewVisit({VisitRecord? previousVisit}) async {
    final result = await Navigator.push<VisitRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => AddVisitScreen(
          patient: _patientData,
          previousVisit: previousVisit,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        final currentVisits = (_patientData['totalVisits'] as num?)?.toInt() ?? 1;
        _patientData['totalVisits'] = currentVisits + 1;
        _patientData['lastVisit'] = 'Today, Just now';
      });
    }
  }

  void _showEncounterDetailModal(VisitRecord visit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EncounterDetailSheet(visit: visit),
    );
  }

  void _showCompareVisitsDialog(List<VisitRecord> visits) {
    if (visits.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least 2 visits are required to compare encounters.'),
          backgroundColor: AppColors.info,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _CompareVisitsDialog(visits: visits),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Patient EHR Profile',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '$_patientName ($_patientId)',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Record New Consultation',
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 24),
            onPressed: () => _openNewVisit(),
          ),
        ],
      ),
      body: StreamBuilder<List<VisitRecord>>(
        stream: EhrService.streamPatientVisits(_patientId),
        builder: (context, snapshot) {
          final visits = snapshot.data ?? [];
          final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Patient Demographic Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: _buildDemographicCard(visits.length),
                ),
              ),

              // Action Toolbar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: () => _openNewVisit(
                            previousVisit: visits.isNotEmpty ? visits.first : null,
                          ),
                          icon: const Icon(Icons.note_add_rounded, size: 18, color: Colors.white),
                          label: const Text(
                            '+ New Visit',
                            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 13.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: () => _showCompareVisitsDialog(visits),
                          icon: const Icon(Icons.compare_arrows_rounded, size: 18, color: AppColors.primary),
                          label: const Text(
                            'Compare',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Section Header: Timeline
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timeline_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'CLINICAL ENCOUNTER TIMELINE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${visits.length} Recorded Visits',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Timeline Content
              if (isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                )
              else if (visits.isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptyTimelineState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final visit = visits[index];
                        final isLast = index == visits.length - 1;
                        return _buildTimelineNode(visit, isLast);
                      },
                      childCount: visits.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // DEMOGRAPHIC PROFILE CARD
  // ==========================================

  Widget _buildDemographicCard(int actualVisitsCount) {
    final age = _patientData['age']?.toString() ?? '--';
    final gender = _patientData['gender']?.toString() ?? '--';
    final blood = _patientData['bloodGroup']?.toString() ?? 'N/A';
    final phone = _patientData['phone']?.toString() ?? 'N/A';
    final address = _patientData['address']?.toString() ?? 'Ahmedabad, Gujarat';
    final allergies = _patientData['allergies']?.toString() ?? 'No known drug allergies';
    final clinic = _patientData['clinic']?.toString() ?? 'Sunrise Clinic';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _patientData['initials']?.toString() ?? (_patientName.isNotEmpty ? _patientName[0].toUpperCase() : 'P'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _patientName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$age Yrs • $gender • Blood: $blood',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Patient ID: $_patientId  •  $clinic',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(phone, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const Spacer(),
                    const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFFB45309)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Allergies: $allergies',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TIMELINE NODE
  // ==========================================

  Widget _buildTimelineNode(VisitRecord visit, bool isLast) {
    final dateStr = '${visit.visitDate.day} ${_getMonth(visit.visitDate.month)} ${visit.visitDate.year}';
    final hasPending = visit.pendingAmount > 0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Spine
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: visit.visitNumber == 1 ? AppColors.primaryAccent : AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '#${visit.visitNumber}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Visit Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () => _showEncounterDetailModal(visit),
                borderRadius: BorderRadius.circular(16),
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
                      // Header Row: Type & Date
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              visit.visitType,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                dateStr,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Chief Complaint / Symptoms
                      Text(
                        visit.chiefComplaint.isNotEmpty ? visit.chiefComplaint : 'Clinical Review',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),

                      // Diagnosis Pill
                      Row(
                        children: [
                          const Icon(Icons.medical_services_outlined, size: 14, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              visit.diagnosis.isNotEmpty ? visit.diagnosis : visit.disease,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),

                      // Vitals Summary (if any)
                      if (visit.vitals.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: visit.vitals.entries.map((e) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${e.key.toUpperCase()}: ${e.value}',
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // Prescriptions Snippet
                      if (visit.prescriptions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDCFCE7)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.medication_rounded, size: 14, color: Color(0xFF16A34A)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  visit.prescriptions.map((m) => '${m['name']} (${m['dosage']})').join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                                ),
                              ),
                              Text(
                                '${visit.prescriptions.length} Meds',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 8),

                      // Footer Row: Clinic & Billing
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.local_hospital_outlined, size: 13, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                visit.clinicName,
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasPending ? AppColors.errorLight : AppColors.successLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              hasPending
                                  ? 'Due ₹${visit.pendingAmount.toStringAsFixed(0)}'
                                  : 'Paid ₹${visit.totalAmount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: hasPending ? AppColors.errorText : AppColors.successText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTimelineState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.note_add_rounded, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Encounters Recorded Yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start the longitudinal EHR record by creating the first clinical consultation for this patient.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openNewVisit(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Start First Visit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  static String _getMonth(int month) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return m[month - 1];
  }
}

// ============================================================================
// ENCOUNTER DETAIL MODAL SHEET (READ-ONLY FINALIZED VIEW)
// ============================================================================

class _EncounterDetailSheet extends StatelessWidget {
  final VisitRecord visit;

  const _EncounterDetailSheet({required this.visit});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${visit.visitDate.day}/${visit.visitDate.month}/${visit.visitDate.year}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
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

            // Header Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_turned_in_rounded, color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visit #${visit.visitNumber} • ${visit.visitType}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Date: $dateStr  •  ${visit.clinicName}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Finalized',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
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
                  // Chief Complaint
                  _buildSectionHeader('CHIEF COMPLAINT & SYMPTOMS', Icons.sick_outlined),
                  const SizedBox(height: 6),
                  Text(
                    visit.chiefComplaint.isNotEmpty ? visit.chiefComplaint : 'General Follow-up Checkup',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 14),

                  // Vitals Grid
                  if (visit.vitals.isNotEmpty) ...[
                    _buildSectionHeader('RECORDED VITALS', Icons.monitor_heart_outlined),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: visit.vitals.entries.map((e) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${e.key.toUpperCase()}: ',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                              ),
                              Text(
                                e.value.toString(),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Examination Notes
                  if (visit.examinationNotes.isNotEmpty) ...[
                    _buildSectionHeader('EXAMINATION NOTES', Icons.visibility_outlined),
                    const SizedBox(height: 6),
                    Text(
                      visit.examinationNotes,
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Diagnosis
                  _buildSectionHeader('DIAGNOSIS & ASSESSMENT', Icons.biotech_outlined),
                  const SizedBox(height: 6),
                  Text(
                    visit.diagnosis.isNotEmpty ? visit.diagnosis : visit.disease,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                  Text(
                    'Category: ${visit.diseaseCategory}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),

                  // Prescriptions
                  _buildSectionHeader('PRESCRIBED MEDICINES', Icons.medication_rounded),
                  const SizedBox(height: 8),
                  if (visit.prescriptions.isNotEmpty)
                    Column(
                      children: visit.prescriptions.map((m) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFDCFCE7)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m['name']?.toString() ?? '',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF14532D)),
                                    ),
                                    Text(
                                      '${m['type'] ?? 'Tablet'} • ${m['duration'] ?? '5 Days'}${m['instructions'] != null && (m['instructions'] as String).isNotEmpty ? ' • ${m['instructions']}' : ''}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
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
                                  m['dosage']?.toString() ?? '1-0-1',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    const Text('No medicines prescribed during this visit.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 14),

                  // Treatment Plan & Follow-up
                  if (visit.treatmentPlan.isNotEmpty || visit.followUpDate != null) ...[
                    _buildSectionHeader('TREATMENT PLAN & FOLLOW-UP', Icons.event_repeat_rounded),
                    const SizedBox(height: 6),
                    if (visit.treatmentPlan.isNotEmpty)
                      Text(visit.treatmentPlan, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    if (visit.followUpDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Scheduled Follow-up: ${visit.followUpDate!.day}/${visit.followUpDate!.month}/${visit.followUpDate!.year}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ],
                    if (visit.followUpInstructions.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Instructions: ${visit.followUpInstructions}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],

                  // Billing Snapshot
                  _buildSectionHeader('BILLING TRANSACTION', Icons.receipt_long_rounded),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBillItem('Consultation', '₹${visit.consultationFee.toStringAsFixed(0)}'),
                        _buildBillItem('Medicines', '₹${visit.medicineFee.toStringAsFixed(0)}'),
                        _buildBillItem('Total Billed', '₹${visit.totalAmount.toStringAsFixed(0)}', isBold: true),
                        _buildBillItem('Status', visit.billStatus, color: visit.billStatus == 'Paid' ? AppColors.successText : AppColors.errorText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildBillItem(String title, String val, {bool isBold = false, Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// COMPARE VISITS DIALOG (SIDE-BY-SIDE CLINICAL PROGRESSION)
// ============================================================================

class _CompareVisitsDialog extends StatefulWidget {
  final List<VisitRecord> visits;

  const _CompareVisitsDialog({required this.visits});

  @override
  State<_CompareVisitsDialog> createState() => _CompareVisitsDialogState();
}

class _CompareVisitsDialogState extends State<_CompareVisitsDialog> {
  late VisitRecord _visitA;
  late VisitRecord _visitB;

  @override
  void initState() {
    super.initState();
    // Default: compare most recent with the one prior
    _visitA = widget.visits[0];
    _visitB = widget.visits[1];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Clinical Encounter Comparison',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Selectors for Visit A & Visit B
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<VisitRecord>(
                    initialValue: _visitA,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Visit 1 (Newer)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    items: widget.visits.map((v) {
                      return DropdownMenuItem(
                        value: v,
                        child: Text(
                          '#${v.visitNumber} (${v.visitDate.day}/${v.visitDate.month})',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _visitA = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<VisitRecord>(
                    initialValue: _visitB,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Visit 2 (Prior)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    items: widget.visits.map((v) {
                      return DropdownMenuItem(
                        value: v,
                        child: Text(
                          '#${v.visitNumber} (${v.visitDate.day}/${v.visitDate.month})',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _visitB = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),

            // Comparison Rows
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildCompareRow('Encounter Date', '${_visitA.visitDate.day}/${_visitA.visitDate.month}/${_visitA.visitDate.year}', '${_visitB.visitDate.day}/${_visitB.visitDate.month}/${_visitB.visitDate.year}'),
                    _buildCompareRow('Clinic Branch', _visitA.clinicName, _visitB.clinicName),
                    _buildCompareRow('Chief Complaint', _visitA.chiefComplaint, _visitB.chiefComplaint),
                    _buildCompareRow('Diagnosis', _visitA.diagnosis.isNotEmpty ? _visitA.diagnosis : _visitA.disease, _visitB.diagnosis.isNotEmpty ? _visitB.diagnosis : _visitB.disease),
                    _buildCompareRow(
                      'Vitals',
                      _visitA.vitals.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                      _visitB.vitals.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                    ),
                    _buildCompareRow(
                      'Prescriptions',
                      _visitA.prescriptions.map((m) => '${m['name']} (${m['dosage']})').join('\n'),
                      _visitB.prescriptions.map((m) => '${m['name']} (${m['dosage']})').join('\n'),
                    ),
                    _buildCompareRow('Treatment Advice', _visitA.treatmentPlan, _visitB.treatmentPlan),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompareRow(String label, String valA, String valB) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    valA.isNotEmpty ? valA : 'N/A',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF14532D)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    valB.isNotEmpty ? valB : 'N/A',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
