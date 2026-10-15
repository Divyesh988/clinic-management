import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/analytics_models.dart';
import '../services/analytics_service.dart';
import '../services/clinic_service.dart';
import '../theme/app_colors.dart';

class analytics extends StatefulWidget {
  const analytics({super.key});

  @override
  State<analytics> createState() => _analyticsState();
}

class _analyticsState extends State<analytics> with SingleTickerProviderStateMixin {
  // ── Filters ─────────────────────────────────────
  DateRangePreset _preset = DateRangePreset.last30Days;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _selectedClinicId; // null = All clinics
  String _selectedClinicName = 'All My Clinics';
  List<Map<String, dynamic>> _doctorClinics = [];

  // ── Data State ───────────────────────────────────
  bool _loading = false;
  String? _error;
  AnalyticsSummary? _summary;
  List<TrendPoint> _registrationTrend = [];
  List<TrendPoint> _revenueTrend = [];
  List<MedicineDemand> _medicineDemand = [];
  List<MedicineCategoryDemand> _categoryDemand = [];
  List<ClinicSummary> _clinicComparison = [];
  List<DiagnosisCount> _topDiagnoses = [];

  // Feature 1: Location Analytics Data
  LocationSummary? _locationSummary;
  List<AreaDistribution> _areaDistribution = [];
  List<CityDistribution> _cityDistribution = [];
  List<PinCodeDistribution> _pinCodeDistribution = [];
  List<ClinicLocationComparison> _clinicLocationComparison = [];

  // Feature 2: Disease Analytics Data
  DiseaseSummary? _diseaseSummary;
  List<DiseaseRecord> _diseaseRankings = [];
  List<DiseaseCategoryDistribution> _diseaseCategoryDist = [];
  List<TrendPoint> _diseaseTrend = [];
  List<ClinicDiseaseComparison> _clinicDiseaseComparison = [];
  String? _selectedTrendCategory;

  DateTime _lastRefreshed = DateTime.now();

  // ── UI State ─────────────────────────────────────
  int _medicineLimitIndex = 0; // 0=Top10, 1=Top20
  final List<int> _medicineLimits = [10, 20];

  int _areaLimitIndex = 1; // 0=Top5, 1=Top10, 2=Top20
  final List<int> _areaLimits = [5, 10, 20];

  int _diseaseLimitIndex = 1; // 0=Top5, 1=Top10, 2=Top20
  final List<int> _diseaseLimits = [5, 10, 20];

  final TextEditingController _locationSearchController = TextEditingController();
  String _locationSearchQuery = '';

  final TextEditingController _diseaseSearchController = TextEditingController();
  String _diseaseSearchQuery = '';

  late TabController _tabController;

  // ────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadClinicsAndData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationSearchController.dispose();
    _diseaseSearchController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────
  // Data Loading
  // ────────────────────────────────────────────────────────────────
  Future<void> _loadClinicsAndData() async {
    final clinics = await ClinicService.getDoctorClinics();
    if (mounted) setState(() => _doctorClinics = clinics);
    await _loadData();
  }

  List<DateTime> get _dateRange {
    if (_preset == DateRangePreset.custom && _customStart != null && _customEnd != null) {
      return [_customStart!, _customEnd!.add(const Duration(days: 1))];
    }
    return _preset.toDateRange();
  }

  List<DateTime> get _prevDateRange {
    if (_preset == DateRangePreset.custom && _customStart != null && _customEnd != null) {
      final dur = _customEnd!.difference(_customStart!);
      return [_customStart!.subtract(dur + const Duration(days: 1)), _customStart!];
    }
    return _preset.toPreviousPeriodRange();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final range = _dateRange;
      final prev = _prevDateRange;
      final cId = _selectedClinicId;
      final medLimit = _medicineLimits[_medicineLimitIndex];
      final areaLimit = _areaLimits[_areaLimitIndex];
      final diseaseLimit = _diseaseLimits[_diseaseLimitIndex];

      final results = await Future.wait([
        // 0-6: Existing overview, medicines, clinics
        AnalyticsService.fetchSummary(
          start: range[0],
          end: range[1],
          prevStart: prev[0],
          prevEnd: prev[1],
          clinicId: cId,
        ),
        AnalyticsService.fetchRegistrationTrend(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchRevenueTrend(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchMedicineDemand(start: range[0], end: range[1], clinicId: cId, limit: medLimit),
        AnalyticsService.fetchMedicineCategoryDemand(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchClinicComparison(start: range[0], end: range[1]),
        AnalyticsService.fetchTopDiagnoses(start: range[0], end: range[1], clinicId: cId),

        // 7-11: Feature 1 - Patient Location Analytics
        AnalyticsService.fetchLocationSummary(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchAreaDistribution(
          start: range[0],
          end: range[1],
          prevStart: prev[0],
          prevEnd: prev[1],
          clinicId: cId,
          limit: areaLimit,
        ),
        AnalyticsService.fetchCityDistribution(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchPinCodeDistribution(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchClinicLocationComparison(start: range[0], end: range[1]),

        // 12-16: Feature 2 - Disease & Diagnosis Analytics
        AnalyticsService.fetchDiseaseSummary(
          start: range[0],
          end: range[1],
          prevStart: prev[0],
          prevEnd: prev[1],
          clinicId: cId,
        ),
        AnalyticsService.fetchDiseaseRankings(
          start: range[0],
          end: range[1],
          prevStart: prev[0],
          prevEnd: prev[1],
          clinicId: cId,
          limit: diseaseLimit,
        ),
        AnalyticsService.fetchDiseaseCategoryDistribution(start: range[0], end: range[1], clinicId: cId),
        AnalyticsService.fetchDiseaseTrend(
          start: range[0],
          end: range[1],
          clinicId: cId,
          targetCategory: _selectedTrendCategory,
        ),
        AnalyticsService.fetchClinicDiseaseComparison(start: range[0], end: range[1]),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as AnalyticsSummary;
        _registrationTrend = results[1] as List<TrendPoint>;
        _revenueTrend = results[2] as List<TrendPoint>;
        _medicineDemand = results[3] as List<MedicineDemand>;
        _categoryDemand = results[4] as List<MedicineCategoryDemand>;
        _clinicComparison = results[5] as List<ClinicSummary>;
        _topDiagnoses = results[6] as List<DiagnosisCount>;

        _locationSummary = results[7] as LocationSummary;
        _areaDistribution = results[8] as List<AreaDistribution>;
        _cityDistribution = results[9] as List<CityDistribution>;
        _pinCodeDistribution = results[10] as List<PinCodeDistribution>;
        _clinicLocationComparison = results[11] as List<ClinicLocationComparison>;

        _diseaseSummary = results[12] as DiseaseSummary;
        _diseaseRankings = results[13] as List<DiseaseRecord>;
        _diseaseCategoryDist = results[14] as List<DiseaseCategoryDistribution>;
        _diseaseTrend = results[15] as List<TrendPoint>;
        _clinicDiseaseComparison = results[16] as List<ClinicDiseaseComparison>;

        _loading = false;
        _lastRefreshed = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Filter Helpers
  // ────────────────────────────────────────────────────────────────
  void _applyClinicFilter(String? clinicId, String clinicName) {
    setState(() {
      _selectedClinicId = clinicId;
      _selectedClinicName = clinicName;
    });
    _loadData();
  }

  void _applyPreset(DateRangePreset p) {
    setState(() => _preset = p);
    _loadData();
  }

  Future<void> _pickCustomRange() async {
    final today = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: _customStart ?? today.subtract(const Duration(days: 6)),
        end: _customEnd ?? today,
      ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _preset = DateRangePreset.custom;
      });
      _loadData();
    }
  }

  // ────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: _loading
                  ? _buildLoadingState()
                  : _error != null
                      ? _buildErrorState()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOverviewTab(),
                            _buildLocationTab(),
                            _buildDiseaseTab(),
                            _buildMedicineTab(),
                            _buildClinicTab(),
                            _buildPatientTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // HEADER
  // ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.insights_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clinic Analytics',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Real-time data from your patient records',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
                onPressed: _loading ? null : _loadData,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Filter row
          Row(
            children: [
              Expanded(child: _buildPresetPicker()),
              const SizedBox(width: 8),
              _buildClinicPicker(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 11, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                'Updated: ${_formatTime(_lastRefreshed)}',
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedClinicName,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetPicker() {
    return InkWell(
      onTap: _showPresetSheet,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              _preset == DateRangePreset.custom && _customStart != null
                  ? '${_fmtShort(_customStart!)} – ${_fmtShort(_customEnd!)}'
                  : _preset.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicPicker() {
    return InkWell(
      onTap: _showClinicSheet,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_hospital_rounded, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                _selectedClinicId == null ? 'All' : _selectedClinicName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  // ── Tab Bar (6 Tabs) ─────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Location'),
          Tab(text: 'Diseases'),
          Tab(text: 'Medicines'),
          Tab(text: 'Clinics'),
          Tab(text: 'Demographics'),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // LOADING / ERROR STATES
  // ────────────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          SizedBox(height: 16),
          Text('Loading analytics...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text('Could not load analytics', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // TAB 1: OVERVIEW
  // ────────────────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final s = _summary;
    if (s == null) return _buildEmptyData('No data available');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('Key Metrics', Icons.speed_rounded),
          const SizedBox(height: 10),
          _buildKpiGrid(s),
          const SizedBox(height: 20),
          _buildSectionLabel('Registration Trend', Icons.trending_up_rounded,
              subtitle: 'Patient registrations over selected period'),
          const SizedBox(height: 10),
          _buildRegistrationChart(),
          const SizedBox(height: 20),
          _buildSectionLabel('Revenue Trend', Icons.currency_rupee_rounded,
              subtitle: 'Billed amount over time'),
          const SizedBox(height: 10),
          _buildRevenueChart(),
          const SizedBox(height: 20),
          _buildSectionLabel('Payment Status', Icons.payment_rounded),
          const SizedBox(height: 10),
          _buildPaymentStatusRow(s),
          const SizedBox(height: 20),
          _buildSectionLabel('Payment Methods', Icons.account_balance_wallet_rounded),
          const SizedBox(height: 10),
          _buildPaymentMethodBars(s),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(AnalyticsSummary s) {
    final pChange = AnalyticsService.percentChange(
        s.patientsRegistered.toDouble(), s.patientsRegisteredPrev.toDouble());
    final rChange = AnalyticsService.percentChange(s.totalBilled, s.totalBilledPrev);
    final cChange = AnalyticsService.percentChange(s.totalCollected, s.totalCollectedPrev);

    final kpis = [
      _KpiItem(
        icon: Icons.person_add_rounded,
        iconColor: AppColors.primary,
        bgColor: AppColors.primarySurface,
        label: 'Patients Registered',
        value: s.patientsRegistered.toString(),
        change: pChange,
        tooltip: 'Number of new patient records created in this period',
      ),
      _KpiItem(
        icon: Icons.currency_rupee_rounded,
        iconColor: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF5F3FF),
        label: 'Total Billed',
        value: _fmtCurrency(s.totalBilled),
        change: rChange,
        tooltip: 'Total amount billed to patients in this period',
      ),
      _KpiItem(
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.success,
        bgColor: AppColors.successLight,
        label: 'Amount Collected',
        value: _fmtCurrency(s.totalCollected),
        change: cChange,
        tooltip: 'Total billed minus outstanding balance',
      ),
      _KpiItem(
        icon: Icons.pending_rounded,
        iconColor: AppColors.warning,
        bgColor: AppColors.warningLight,
        label: 'Pending Balance',
        value: _fmtCurrency(s.pendingAmount),
        tooltip: 'Outstanding unpaid amount as of today',
      ),
      _KpiItem(
        icon: Icons.local_hospital_rounded,
        iconColor: AppColors.info,
        bgColor: AppColors.infoLight,
        label: 'Consultation Revenue',
        value: _fmtCurrency(s.consultationRevenue),
        tooltip: 'Total consultation fees billed',
      ),
      _KpiItem(
        icon: Icons.medication_rounded,
        iconColor: const Color(0xFFDB2777),
        bgColor: const Color(0xFFFCE7F3),
        label: 'Medicine Revenue',
        value: _fmtCurrency(s.medicineRevenue),
        tooltip: 'Total medicine fees billed (not confirmed sales)',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.32,
      ),
      itemCount: kpis.length,
      itemBuilder: (_, i) => _buildKpiCard(kpis[i]),
    );
  }

  Widget _buildKpiCard(_KpiItem item) {
    return Tooltip(
      message: item.tooltip ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: item.bgColor, borderRadius: BorderRadius.circular(8)),
                  child: Icon(item.icon, color: item.iconColor, size: 14),
                ),
                const Spacer(),
                if (item.change != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.change! >= 0 ? AppColors.successLight : AppColors.errorLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.change! >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 9,
                          color: item.change! >= 0 ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${item.change!.abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: item.change! >= 0 ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary, height: 1.15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrationChart() {
    if (_registrationTrend.isEmpty) return _buildEmptyData('No registration data');
    final hasData = _registrationTrend.any((p) => p.value > 0);
    if (!hasData) return _buildEmptyData('No patient registrations in this period');

    final points = _sampleTrendPoints(_registrationTrend, 30);
    final maxY = points.map((p) => p.value).reduce(math.max);

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? (maxY / 4).ceilToDouble().clamp(1, double.infinity) : 1,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderSubtle, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (points.length / 5).floorToDouble().clamp(1, double.infinity),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      points[idx].label,
                      style: const TextStyle(fontSize: 8.5, color: AppColors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(points.length, (i) => FlSpot(i.toDouble(), points[i].value)),
              isCurved: true,
              color: AppColors.primary,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, idx) => FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.primary,
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt().clamp(0, points.length - 1);
                return LineTooltipItem(
                  '${points[idx].label}\n${s.y.toInt()} patients',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRevenueChart() {
    if (_revenueTrend.isEmpty) return _buildEmptyData('No revenue data');
    final hasData = _revenueTrend.any((p) => p.value > 0);
    if (!hasData) return _buildEmptyData('No revenue in this period');

    final points = _sampleTrendPoints(_revenueTrend, 30);
    final maxY = points.map((p) => p.value).reduce(math.max);

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? (maxY / 4).ceilToDouble().clamp(1, double.infinity) : 1,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderSubtle, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, _) => Text(
                  _fmtCurrencyCompact(v),
                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (points.length / 5).floorToDouble().clamp(1, double.infinity),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      points[idx].label,
                      style: const TextStyle(fontSize: 8.5, color: AppColors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(points.length, (i) => FlSpot(i.toDouble(), points[i].value)),
              isCurved: true,
              color: const Color(0xFF7C3AED),
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, idx) => FlDotCirclePainter(
                  radius: 3,
                  color: const Color(0xFF7C3AED),
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [const Color(0xFF7C3AED).withValues(alpha: 0.15), const Color(0xFF7C3AED).withValues(alpha: 0.0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt().clamp(0, points.length - 1);
                return LineTooltipItem(
                  '${points[idx].label}\n₹${s.y.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentStatusRow(AnalyticsSummary s) {
    final total = s.patientsRegistered == 0 ? 1 : s.patientsRegistered;
    return Row(
      children: [
        Expanded(child: _buildStatusCard('Paid', s.paidCount, total, AppColors.success, AppColors.successLight, Icons.check_circle_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatusCard('Partial', s.partialCount, total, AppColors.warning, AppColors.warningLight, Icons.timelapse_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatusCard('Pending', s.pendingCount, total, AppColors.error, AppColors.errorLight, Icons.pending_rounded)),
      ],
    );
  }

  Widget _buildStatusCard(String label, int count, int total, Color color, Color bg, IconData icon) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 6),
          Text(count.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text('$pct%', style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodBars(AnalyticsSummary s) {
    if (s.paymentMethodCounts.isEmpty) return _buildEmptyData('No payment data');
    final total = s.paymentMethodCounts.values.fold(0, (a, b) => a + b);
    final colors = [AppColors.primary, const Color(0xFF7C3AED), AppColors.info, AppColors.warning, AppColors.success];
    final entries = s.paymentMethodCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: List.generate(entries.length, (i) {
          final e = entries[i];
          final pct = total > 0 ? e.value / total : 0.0;
          final color = colors[i % colors.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('${e.value} (${(pct * 100).toStringAsFixed(1)}%)',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppColors.borderSubtle,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // FEATURE 1: LOCATION ANALYTICS TAB
  // ────────────────────────────────────────────────────────────────
  Widget _buildLocationTab() {
    final s = _locationSummary;
    if (s == null) return _buildEmptyData('No location data available');

    final filteredAreas = _locationSearchQuery.isEmpty
        ? _areaDistribution
        : _areaDistribution.where((a) =>
            a.area.toLowerCase().contains(_locationSearchQuery.toLowerCase()) ||
            a.city.toLowerCase().contains(_locationSearchQuery.toLowerCase()) ||
            a.pinCode.contains(_locationSearchQuery)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_rounded, size: 15, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Geographic distribution analyzed from patients’ saved residential addresses and 6-digit Indian PIN codes.',
                    style: TextStyle(fontSize: 11, color: AppColors.primaryDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Location Summary KPIs
          _buildSectionLabel('Location Overview', Icons.map_rounded),
          const SizedBox(height: 10),
          _buildLocationKpiGrid(s),
          const SizedBox(height: 20),

          // Area Bar Chart
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionLabel('Patients by Area', Icons.holiday_village_rounded,
                  subtitle: 'Top patient origins'),
              _buildAreaLimitToggle(),
            ],
          ),
          const SizedBox(height: 10),
          _buildAreaBarChart(),
          const SizedBox(height: 16),

          // Area Table with search
          _buildAreaTable(filteredAreas),
          const SizedBox(height: 20),

          // City Distribution
          _buildSectionLabel('Patients by City', Icons.location_city_rounded,
              subtitle: 'City-level geographic share'),
          const SizedBox(height: 10),
          _buildCityDistributionSection(),
          const SizedBox(height: 20),

          // PIN Code Section
          _buildSectionLabel('Patients by PIN Code', Icons.pin_drop_rounded,
              subtitle: 'Valid 6-digit postal codes'),
          const SizedBox(height: 10),
          _buildPinCodeSection(),

          // Multi-clinic comparison if All Clinics selected
          if (_selectedClinicId == null && _clinicLocationComparison.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionLabel('Clinic Location Comparison', Icons.compare_arrows_rounded,
                subtitle: 'Patient geographical reach across clinics'),
            const SizedBox(height: 10),
            _buildClinicLocationTable(),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationKpiGrid(LocationSummary s) {
    final kpis = [
      _KpiItem(
        icon: Icons.person_pin_circle_rounded,
        iconColor: AppColors.primary,
        bgColor: AppColors.primarySurface,
        label: 'Patients With Location',
        value: '${s.totalWithLocation}',
        tooltip: 'Number of distinct patients with usable address details',
      ),
      _KpiItem(
        icon: Icons.percent_rounded,
        iconColor: AppColors.success,
        bgColor: AppColors.successLight,
        label: 'Location Coverage',
        value: '${s.locationCoveragePct.toStringAsFixed(1)}%',
        tooltip: 'Percentage of eligible patient records containing location data',
      ),
      _KpiItem(
        icon: Icons.holiday_village_rounded,
        iconColor: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF5F3FF),
        label: 'Top Patient Area',
        value: s.topArea,
        tooltip: 'Locality or area contributing the most patients',
      ),
      _KpiItem(
        icon: Icons.location_city_rounded,
        iconColor: AppColors.info,
        bgColor: AppColors.infoLight,
        label: 'Top Patient City',
        value: s.topCity,
        tooltip: 'City with the highest patient count',
      ),
      _KpiItem(
        icon: Icons.pin_drop_rounded,
        iconColor: AppColors.warning,
        bgColor: AppColors.warningLight,
        label: 'Top PIN Code',
        value: s.topPinCode,
        tooltip: '6-digit postal code with the highest patient concentration',
      ),
      _KpiItem(
        icon: Icons.layers_rounded,
        iconColor: const Color(0xFFDB2777),
        bgColor: const Color(0xFFFCE7F3),
        label: 'Areas Covered',
        value: '${s.areasCovered}',
        tooltip: 'Total distinct localities represented in your records',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.32,
      ),
      itemCount: kpis.length,
      itemBuilder: (_, i) => _buildKpiCard(kpis[i]),
    );
  }

  Widget _buildAreaLimitToggle() {
    return Row(
      children: List.generate(_areaLimits.length, (i) {
        final isSelected = i == _areaLimitIndex;
        return GestureDetector(
          onTap: () {
            setState(() => _areaLimitIndex = i);
            _loadData();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.horizontal(
                left: i == 0 ? const Radius.circular(8) : Radius.zero,
                right: i == _areaLimits.length - 1 ? const Radius.circular(8) : Radius.zero,
              ),
            ),
            child: Text(
              'Top ${_areaLimits[i]}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAreaBarChart() {
    if (_areaDistribution.isEmpty) return _buildEmptyData('No location data found in this period');
    final maxVal = _areaDistribution.map((a) => a.patientCount).reduce(math.max).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
      height: math.max(180, _areaDistribution.length * 36.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final a = _areaDistribution[group.x.toInt()];
                return BarTooltipItem(
                  '${a.area} (${a.city})\n${rod.toY.toInt()} patients (${a.percentageShare.toStringAsFixed(1)}%)',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                    style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= _areaDistribution.length) return const SizedBox.shrink();
                  final name = _areaDistribution[idx].area;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      name.length > 7 ? '${name.substring(0, 6)}…' : name,
                      style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxVal > 0 ? (maxVal / 4).ceilToDouble() : 1,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderSubtle, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(_areaDistribution.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _areaDistribution[i].patientCount.toDouble(),
                  color: AppColors.primary,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
          maxY: maxVal > 0 ? maxVal * 1.2 : 5,
        ),
      ),
    );
  }

  Widget _buildAreaTable(List<AreaDistribution> areas) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _locationSearchController,
              decoration: InputDecoration(
                hintText: 'Search area, city or PIN...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
                suffixIcon: _locationSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _locationSearchController.clear();
                          setState(() => _locationSearchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _locationSearchQuery = v.trim()),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.vertical(top: Radius.zero),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Area / Locality', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('City', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('PIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Patients', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Share', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              ],
            ),
          ),
          const Divider(height: 0, color: AppColors.border),
          if (areas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No areas match your search', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            ...List.generate(areas.length, (i) {
              final a = areas[i];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(a.area, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(a.city, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(a.pinCode, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${a.patientCount}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${a.percentageShare.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
                  if (i < areas.length - 1) const Divider(height: 0, color: AppColors.borderSubtle),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCityDistributionSection() {
    if (_cityDistribution.isEmpty) return _buildEmptyData('No city data available');
    final colors = [AppColors.primary, const Color(0xFF7C3AED), AppColors.info, AppColors.warning, AppColors.success];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sections: List.generate(_cityDistribution.length, (i) {
                  final c = _cityDistribution[i];
                  return PieChartSectionData(
                    color: colors[i % colors.length],
                    value: c.patientCount.toDouble(),
                    title: '${c.percentageShare.toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  );
                }),
                centerSpaceRadius: 36,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Column(
            children: List.generate(_cityDistribution.length, (i) {
              final c = _cityDistribution[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.city, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          if (c.topAreas.isNotEmpty)
                            Text('Areas: ${c.topAreas.join(", ")}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text('${c.patientCount} (${c.percentageShare.toStringAsFixed(1)}%)',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPinCodeSection() {
    if (_pinCodeDistribution.isEmpty) return _buildEmptyData('No 6-digit Indian PIN codes detected in patient records');

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('PIN Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 3, child: Text('Sample Locality', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Patients', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Share', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              ],
            ),
          ),
          const Divider(height: 0, color: AppColors.border),
          ...List.generate(_pinCodeDistribution.length, (i) {
            final pin = _pinCodeDistribution[i];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(pin.pinCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(pin.area, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('${pin.patientCount}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('${pin.percentageShare.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
                if (i < _pinCodeDistribution.length - 1) const Divider(height: 0, color: AppColors.borderSubtle),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildClinicLocationTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          dataTextStyle: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('Clinic')),
            DataColumn(label: Text('With Location'), numeric: true),
            DataColumn(label: Text('Top Area')),
            DataColumn(label: Text('Top City')),
            DataColumn(label: Text('Coverage'), numeric: true),
          ],
          rows: _clinicLocationComparison.map((c) {
            return DataRow(
              cells: [
                DataCell(Text(c.clinicName)),
                DataCell(Text('${c.patientsWithLocation} / ${c.totalPatients}')),
                DataCell(Text(c.topArea)),
                DataCell(Text(c.topCity)),
                DataCell(Text('${c.coveragePct.toStringAsFixed(1)}%',
                    style: TextStyle(color: c.coveragePct > 50 ? AppColors.success : AppColors.warning))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // FEATURE 2: DISEASE & DIAGNOSIS ANALYTICS TAB
  // ────────────────────────────────────────────────────────────────
  Widget _buildDiseaseTab() {
    final s = _diseaseSummary;
    if (s == null) return _buildEmptyData('No disease/diagnosis data available');

    final filteredDiseases = _diseaseSearchQuery.isEmpty
        ? _diseaseRankings
        : _diseaseRankings.where((d) =>
            d.diagnosis.toLowerCase().contains(_diseaseSearchQuery.toLowerCase()) ||
            d.category.toLowerCase().contains(_diseaseSearchQuery.toLowerCase())).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.medical_services_rounded, size: 15, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Clinical diagnoses and chief complaints recorded by the physician. Distinct patient counts represent unique patient files.',
                    style: TextStyle(fontSize: 11, color: AppColors.infoText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Disease Summary KPIs
          _buildSectionLabel('Clinical Overview', Icons.health_and_safety_rounded),
          const SizedBox(height: 10),
          _buildDiseaseKpiGrid(s),
          const SizedBox(height: 20),

          // Top Diseases Bar Chart
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionLabel('Most Recorded Conditions', Icons.sick_rounded,
                  subtitle: 'Ranked by distinct patient count'),
              _buildDiseaseLimitToggle(),
            ],
          ),
          const SizedBox(height: 10),
          _buildDiseaseBarChart(),
          const SizedBox(height: 16),

          // Detailed Disease Table
          _buildDiseaseTable(filteredDiseases),
          const SizedBox(height: 20),

          // Disease Category Analysis
          _buildSectionLabel('Clinical Categories', Icons.pie_chart_rounded,
              subtitle: 'Distribution across medical specialities'),
          const SizedBox(height: 10),
          _buildDiseaseCategorySection(),
          const SizedBox(height: 20),

          // Diagnosis Trends Over Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionLabel('Diagnosis Trends', Icons.trending_up_rounded,
                  subtitle: 'Case volume over time'),
              if (_diseaseCategoryDist.isNotEmpty) _buildCategoryFilterDropdown(),
            ],
          ),
          const SizedBox(height: 10),
          _buildDiseaseTrendChart(),

          // Multi-clinic comparison if All Clinics selected
          if (_selectedClinicId == null && _clinicDiseaseComparison.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionLabel('Clinic Disease Comparison', Icons.compare_arrows_rounded,
                subtitle: 'Case distribution across your clinics'),
            const SizedBox(height: 10),
            _buildClinicDiseaseTable(),
          ],
        ],
      ),
    );
  }

  Widget _buildDiseaseKpiGrid(DiseaseSummary s) {
    final kpis = [
      _KpiItem(
        icon: Icons.sick_rounded,
        iconColor: AppColors.primary,
        bgColor: AppColors.primarySurface,
        label: 'Top Diagnosis',
        value: s.topDiagnosis,
        tooltip: 'Most frequently recorded diagnosis or chief complaint',
      ),
      _KpiItem(
        icon: Icons.personal_injury_rounded,
        iconColor: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF5F3FF),
        label: 'Patients With Diagnosis',
        value: '${s.distinctPatientsWithDiagnosis}',
        tooltip: 'Number of distinct patient records with clinical diagnosis',
      ),
      _KpiItem(
        icon: Icons.category_rounded,
        iconColor: AppColors.info,
        bgColor: AppColors.infoLight,
        label: 'Top Disease Category',
        value: s.topCategory,
        tooltip: 'Most prevalent medical specialty category',
      ),
      _KpiItem(
        icon: Icons.layers_rounded,
        iconColor: const Color(0xFFDB2777),
        bgColor: const Color(0xFFFCE7F3),
        label: 'Recorded Categories',
        value: '${s.distinctCategories}',
        tooltip: 'Total distinct clinical categories recorded',
      ),
      _KpiItem(
        icon: Icons.verified_user_rounded,
        iconColor: AppColors.success,
        bgColor: AppColors.successLight,
        label: 'Diagnosis Coverage',
        value: '${s.diagnosisCoveragePct.toStringAsFixed(1)}%',
        tooltip: 'Percentage of patients with non-generic diagnosis notes',
      ),
      _KpiItem(
        icon: Icons.trending_up_rounded,
        iconColor: s.changePercent != null && s.changePercent! >= 0 ? AppColors.success : AppColors.error,
        bgColor: s.changePercent != null && s.changePercent! >= 0 ? AppColors.successLight : AppColors.errorLight,
        label: 'Case Volume Trend',
        value: s.changePercent != null
            ? '${s.changePercent! >= 0 ? '+' : ''}${s.changePercent!.toStringAsFixed(1)}%'
            : '—',
        tooltip: 'Change in recorded cases vs previous equivalent period',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.32,
      ),
      itemCount: kpis.length,
      itemBuilder: (_, i) => _buildKpiCard(kpis[i]),
    );
  }

  Widget _buildDiseaseLimitToggle() {
    return Row(
      children: List.generate(_diseaseLimits.length, (i) {
        final isSelected = i == _diseaseLimitIndex;
        return GestureDetector(
          onTap: () {
            setState(() => _diseaseLimitIndex = i);
            _loadData();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.horizontal(
                left: i == 0 ? const Radius.circular(8) : Radius.zero,
                right: i == _diseaseLimits.length - 1 ? const Radius.circular(8) : Radius.zero,
              ),
            ),
            child: Text(
              'Top ${_diseaseLimits[i]}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDiseaseBarChart() {
    if (_diseaseRankings.isEmpty) return _buildEmptyData('No diagnosis records found in this period');
    final maxVal = _diseaseRankings.map((d) => d.patientCount).reduce(math.max).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
      height: math.max(180, _diseaseRankings.length * 36.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final d = _diseaseRankings[group.x.toInt()];
                return BarTooltipItem(
                  '${d.diagnosis}\n${d.category}\n${rod.toY.toInt()} patients (${d.percentageShare.toStringAsFixed(1)}%)',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                    style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= _diseaseRankings.length) return const SizedBox.shrink();
                  final name = _diseaseRankings[idx].diagnosis;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      name.length > 7 ? '${name.substring(0, 6)}…' : name,
                      style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxVal > 0 ? (maxVal / 4).ceilToDouble() : 1,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderSubtle, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(_diseaseRankings.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _diseaseRankings[i].patientCount.toDouble(),
                  color: const Color(0xFF7C3AED),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
          maxY: maxVal > 0 ? maxVal * 1.2 : 5,
        ),
      ),
    );
  }

  Widget _buildDiseaseTable(List<DiseaseRecord> diseases) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _diseaseSearchController,
              decoration: InputDecoration(
                hintText: 'Search disease or clinical category...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
                suffixIcon: _diseaseSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _diseaseSearchController.clear();
                          setState(() => _diseaseSearchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _diseaseSearchQuery = v.trim()),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.vertical(top: Radius.zero),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Diagnosis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Category', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Patients', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Share', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              ],
            ),
          ),
          const Divider(height: 0, color: AppColors.border),
          if (diseases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No diseases match your search', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            ...List.generate(diseases.length, (i) {
              final d = diseases[i];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(d.diagnosis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(5)),
                            child: Text(d.category, style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${d.patientCount}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${d.percentageShare.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
                  if (i < diseases.length - 1) const Divider(height: 0, color: AppColors.borderSubtle),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDiseaseCategorySection() {
    if (_diseaseCategoryDist.isEmpty) return _buildEmptyData('No category data available');
    final colors = [
      AppColors.primary, const Color(0xFF7C3AED), AppColors.info, AppColors.warning,
      AppColors.success, const Color(0xFFDB2777), const Color(0xFF0284C7), const Color(0xFFEA580C)
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sections: List.generate(_diseaseCategoryDist.length, (i) {
                  final c = _diseaseCategoryDist[i];
                  return PieChartSectionData(
                    color: colors[i % colors.length],
                    value: c.patientCount.toDouble(),
                    title: '${c.percentageShare.toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  );
                }),
                centerSpaceRadius: 36,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: List.generate(_diseaseCategoryDist.length, (i) {
              final c = _diseaseCategoryDist[i];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('${c.category} (${c.patientCount})', style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterDropdown() {
    return DropdownButton<String?>(
      value: _selectedTrendCategory,
      hint: const Text('All Categories', style: TextStyle(fontSize: 11, color: AppColors.primary)),
      underline: const SizedBox.shrink(),
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary, size: 18),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All Categories', style: TextStyle(fontSize: 11))),
        ..._diseaseCategoryDist.map((c) => DropdownMenuItem<String?>(
              value: c.category,
              child: Text(c.category, style: const TextStyle(fontSize: 11)),
            )),
      ],
      onChanged: (v) {
        setState(() => _selectedTrendCategory = v);
        _loadData();
      },
    );
  }

  Widget _buildDiseaseTrendChart() {
    if (_diseaseTrend.isEmpty) return _buildEmptyData('No diagnosis trends available');
    final hasData = _diseaseTrend.any((p) => p.value > 0);
    if (!hasData) return _buildEmptyData('No cases recorded in this period for the selected category');

    final points = _sampleTrendPoints(_diseaseTrend, 30);
    final maxY = points.map((p) => p.value).reduce(math.max);

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? (maxY / 4).ceilToDouble().clamp(1, double.infinity) : 1,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderSubtle, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (points.length / 5).floorToDouble().clamp(1, double.infinity),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      points[idx].label,
                      style: const TextStyle(fontSize: 8.5, color: AppColors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(points.length, (i) => FlSpot(i.toDouble(), points[i].value)),
              isCurved: true,
              color: const Color(0xFFDB2777),
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, idx) => FlDotCirclePainter(
                  radius: 3,
                  color: const Color(0xFFDB2777),
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [const Color(0xFFDB2777).withValues(alpha: 0.15), const Color(0xFFDB2777).withValues(alpha: 0.0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt().clamp(0, points.length - 1);
                return LineTooltipItem(
                  '${points[idx].label}\n${s.y.toInt()} cases',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClinicDiseaseTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          dataTextStyle: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('Clinic')),
            DataColumn(label: Text('Diagnosed Patients'), numeric: true),
            DataColumn(label: Text('Top Diagnosis')),
            DataColumn(label: Text('Top Category')),
          ],
          rows: _clinicDiseaseComparison.map((c) {
            return DataRow(
              cells: [
                DataCell(Text(c.clinicName)),
                DataCell(Text('${c.patientsWithDiagnosis}')),
                DataCell(Text(c.topDiagnosis)),
                DataCell(Text(c.topCategory)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // TAB 4: MEDICINES
  // ────────────────────────────────────────────────────────────────
  Widget _buildMedicineTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This shows medicines prescribed (not confirmed sales). Each medicine listed in a patient record is counted.',
                    style: TextStyle(fontSize: 11, color: AppColors.infoText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionLabel('Prescription by Type', Icons.pie_chart_rounded,
              subtitle: 'Distribution by medicine category'),
          const SizedBox(height: 10),
          _buildCategoryChart(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionLabel('Most Prescribed', Icons.bar_chart_rounded),
              _buildLimitToggle(),
            ],
          ),
          const SizedBox(height: 10),
          _buildMedicineBarChart(),
          const SizedBox(height: 16),
          _buildMedicineTable(),
        ],
      ),
    );
  }

  Widget _buildLimitToggle() {
    return Row(
      children: List.generate(_medicineLimits.length, (i) {
        final isSelected = i == _medicineLimitIndex;
        return GestureDetector(
          onTap: () {
            setState(() => _medicineLimitIndex = i);
            _loadData();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.horizontal(
                left: i == 0 ? const Radius.circular(8) : Radius.zero,
                right: i == _medicineLimits.length - 1 ? const Radius.circular(8) : Radius.zero,
              ),
            ),
            child: Text(
              'Top ${_medicineLimits[i]}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCategoryChart() {
    if (_categoryDemand.isEmpty) return _buildEmptyData('No medicine prescription data');

    final colors = [
      AppColors.primary, const Color(0xFF7C3AED), AppColors.info, AppColors.warning,
      AppColors.success, const Color(0xFFDB2777), AppColors.error,
    ];
    final total = _categoryDemand.fold(0, (s, c) => s + c.count);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: List.generate(_categoryDemand.length, (i) {
                  final c = _categoryDemand[i];
                  final pct = total > 0 ? c.count / total : 0.0;
                  return PieChartSectionData(
                    color: colors[i % colors.length],
                    value: c.count.toDouble(),
                    title: '${(pct * 100).toStringAsFixed(0)}%',
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                  );
                }),
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: List.generate(_categoryDemand.length, (i) {
              final c = _categoryDemand[i];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('${c.category} (${c.count})', style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineBarChart() {
    if (_medicineDemand.isEmpty) return _buildEmptyData('No prescribed medicines in this period');
    final top = _medicineDemand.take(10).toList();
    final maxVal = top.map((m) => m.prescriptionCount).reduce(math.max).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
      height: math.max(200, top.length * 38.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final m = top[group.x.toInt()];
                return BarTooltipItem(
                  '${m.name}\n${rod.toY.toInt()} prescriptions',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                    style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, meta) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= top.length) return const SizedBox.shrink();
                  final name = top[idx].name;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      name.length > 8 ? '${name.substring(0, 7)}…' : name,
                      style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxVal > 0 ? (maxVal / 4).ceilToDouble() : 1,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderSubtle, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(top.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].prescriptionCount.toDouble(),
                  color: AppColors.primary,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
          maxY: maxVal > 0 ? maxVal * 1.2 : 5,
        ),
      ),
    );
  }

  Widget _buildMedicineTable() {
    if (_medicineDemand.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Medicine', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Type', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 1, child: Text('Rx Count', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                Expanded(flex: 1, child: Text('Patients', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              ],
            ),
          ),
          const Divider(height: 0, color: AppColors.border),
          ...List.generate(_medicineDemand.length, (i) {
            final m = _medicineDemand[i];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Center(
                                child: Text('${i + 1}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(m.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(5)),
                          child: Text(m.type, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(m.prescriptionCount.toString(), textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(m.totalPatients.toString(), textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
                if (i < _medicineDemand.length - 1) const Divider(height: 0, color: AppColors.borderSubtle),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // TAB 5: CLINIC COMPARISON
  // ────────────────────────────────────────────────────────────────
  Widget _buildClinicTab() {
    if (_clinicComparison.isEmpty) {
      return _buildEmptyData('No clinics found.\nAdd clinics from the Profile page.');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('Clinic Performance Comparison', Icons.compare_arrows_rounded,
              subtitle: 'All your registered clinics • ${_preset.label}'),
          const SizedBox(height: 10),
          _buildClinicComparisonCards(),
          const SizedBox(height: 16),
          _buildClinicComparisonTable(),
        ],
      ),
    );
  }

  Widget _buildClinicComparisonCards() {
    return Column(
      children: _clinicComparison.map((c) {
        final isPrimary = _doctorClinics.any((dc) => dc['docId'] == c.clinicId && dc['isPrimary'] == true);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
            border: isPrimary ? Border.all(color: AppColors.primaryBorder, width: 1.5) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.local_hospital_rounded, size: 14, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(c.clinicName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            if (isPrimary) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: AppColors.mintBadgeBg, borderRadius: BorderRadius.circular(5)),
                                child: const Text('Primary', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.mintBadgeText)),
                              ),
                            ],
                          ],
                        ),
                        Text('${c.patientsRegistered} patients registered', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 0, color: AppColors.borderSubtle),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildClinicMetric('Billed', _fmtCurrency(c.totalBilled), const Color(0xFF7C3AED))),
                  Expanded(child: _buildClinicMetric('Collected', _fmtCurrency(c.totalCollected), AppColors.success)),
                  Expanded(child: _buildClinicMetric('Pending', _fmtCurrency(c.pendingAmount), AppColors.warning)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildClinicMetric('Consultation', _fmtCurrency(c.consultationRevenue), AppColors.info)),
                  Expanded(child: _buildClinicMetric('Medicine', _fmtCurrency(c.medicineRevenue), const Color(0xFFDB2777))),
                  Expanded(child: _buildClinicMetric('Patients', c.patientsRegistered.toString(), AppColors.primary)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildClinicMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _buildClinicComparisonTable() {
    if (_clinicComparison.length < 2) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text('Comparison Table', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
          const Divider(height: 0, color: AppColors.border),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              dataTextStyle: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Clinic')),
                DataColumn(label: Text('Patients'), numeric: true),
                DataColumn(label: Text('Billed'), numeric: true),
                DataColumn(label: Text('Collected'), numeric: true),
                DataColumn(label: Text('Pending'), numeric: true),
              ],
              rows: _clinicComparison.map((c) {
                return DataRow(
                  cells: [
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(c.clinicName, overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(c.patientsRegistered.toString())),
                    DataCell(Text(_fmtCurrency(c.totalBilled))),
                    DataCell(Text(_fmtCurrency(c.totalCollected))),
                    DataCell(Text(_fmtCurrency(c.pendingAmount),
                        style: TextStyle(color: c.pendingAmount > 0 ? AppColors.warning : AppColors.textSecondary))),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // TAB 6: PATIENT DEMOGRAPHICS
  // ────────────────────────────────────────────────────────────────
  Widget _buildPatientTab() {
    final s = _summary;
    if (s == null) return _buildEmptyData('No data available');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('Gender Distribution', Icons.people_alt_rounded),
          const SizedBox(height: 10),
          _buildGenderChart(s),
          const SizedBox(height: 20),
          _buildSectionLabel('Age Group Distribution', Icons.bar_chart_rounded),
          const SizedBox(height: 10),
          _buildAgeGroupChart(s),
          const SizedBox(height: 20),
          _buildSectionLabel('Top Diagnoses', Icons.medical_information_rounded,
              subtitle: 'Most frequent diagnoses in this period'),
          const SizedBox(height: 10),
          _buildDiagnosesSection(),
        ],
      ),
    );
  }

  Widget _buildGenderChart(AnalyticsSummary s) {
    if (s.genderCounts.isEmpty) return _buildEmptyData('No gender data available');
    final total = s.genderCounts.values.fold(0, (a, b) => a + b);
    final genderColors = {'Male': AppColors.info, 'Female': const Color(0xFFDB2777), 'Other': AppColors.textMuted};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: Row(
        children: [
          SizedBox(
            height: 130,
            width: 130,
            child: PieChart(
              PieChartData(
                sections: s.genderCounts.entries.map((e) {
                  final pct = total > 0 ? e.value / total : 0.0;
                  final color = genderColors[e.key] ?? AppColors.textMuted;
                  return PieChartSectionData(
                    color: color,
                    value: e.value.toDouble(),
                    title: '${(pct * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                  );
                }).toList(),
                centerSpaceRadius: 30,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: s.genderCounts.entries.map((e) {
                final pct = total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0.0';
                final color = genderColors[e.key] ?? AppColors.textMuted;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('${e.key}\n${e.value} ($pct%)',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeGroupChart(AnalyticsSummary s) {
    if (s.ageGroupCounts.isEmpty) return _buildEmptyData('No age data available');

    final orderedGroups = ['0–12', '13–17', '18–29', '30–44', '45–59', '60+'];
    final entries = orderedGroups
        .where((g) => s.ageGroupCounts.containsKey(g))
        .map((g) => MapEntry(g, s.ageGroupCounts[g]!))
        .toList();
    if (entries.isEmpty) return _buildEmptyData('No age data');

    final maxVal = entries.map((e) => e.value).reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: Column(
        children: entries.map((e) {
          final pct = maxVal > 0 ? e.value / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(width: 42, child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.borderSubtle,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text('${e.value}', textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDiagnosesSection() {
    if (_topDiagnoses.isEmpty) return _buildEmptyData('No diagnosis data in this period');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: List.generate(_topDiagnoses.length, (i) {
          final d = _topDiagnoses[i];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i == 0 ? AppColors.primarySurface : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: i == 0 ? AppColors.primary : AppColors.textSecondary,
                            )),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(d.diagnosis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.mintBadgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${d.count}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.mintBadgeText)),
                    ),
                  ],
                ),
              ),
              if (i < _topDiagnoses.length - 1) const Divider(height: 0, color: AppColors.borderSubtle),
            ],
          );
        }),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // FILTER SHEETS
  // ────────────────────────────────────────────────────────────────
  void _showPresetSheet() {
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
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            const Text('Select Date Range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            ...DateRangePreset.values.where((p) => p != DateRangePreset.custom).map((preset) {
              final isSelected = _preset == preset;
              return InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _applyPreset(preset);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primarySurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected ? Border.all(color: AppColors.primaryBorder) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 15, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(preset.label, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.primary : AppColors.textPrimary)),
                      const Spacer(),
                      if (isSelected) const Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              );
            }),
            InkWell(
              onTap: () {
                Navigator.pop(ctx);
                _pickCustomRange();
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _preset == DateRangePreset.custom ? AppColors.primarySurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: _preset == DateRangePreset.custom ? Border.all(color: AppColors.primaryBorder) : null,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.date_range_rounded, size: 15, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Text('Custom Range', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                    Spacer(),
                    Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClinicSheet() {
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
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Text('Filter by Clinic', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            _buildClinicOption(ctx, null, 'All My Clinics', _selectedClinicId == null),
            const SizedBox(height: 6),
            ..._doctorClinics.map((c) {
              final cId = c['docId']?.toString() ?? '';
              final cName = c['name']?.toString() ?? 'Clinic';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildClinicOption(ctx, cId, cName, _selectedClinicId == cId),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicOption(BuildContext ctx, String? clinicId, String name, bool isSelected) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _applyClinicFilter(clinicId, clinicId == null ? 'All My Clinics' : name);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySurface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: AppColors.primaryBorder) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.local_hospital_rounded, size: 15, color: isSelected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(name, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textPrimary)),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // COMMON WIDGETS
  // ────────────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String title, IconData icon, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyData(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.analytics_outlined, size: 32, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // FORMATTING HELPERS
  // ────────────────────────────────────────────────────────────────
  String _fmtCurrency(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  String _fmtCurrencyCompact(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtShort(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  List<TrendPoint> _sampleTrendPoints(List<TrendPoint> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil();
    final sampled = <TrendPoint>[];
    for (int i = 0; i < points.length; i += step) {
      sampled.add(points[i]);
    }
    return sampled;
  }
}

// ────────────────────────────────────────────────────────────────
// Internal helper model
// ────────────────────────────────────────────────────────────────
class _KpiItem {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String label;
  final String value;
  final double? change;
  final String? tooltip;

  const _KpiItem({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.value,
    this.change,
    this.tooltip,
  });
}
