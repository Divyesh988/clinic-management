import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'analytics_models.dart';
import 'clinic_service.dart';
import 'doctor_service.dart';

/// Firebase-powered analytics service for the Clinic Management System.
///
/// All data is sourced from the [patients] Firestore collection.
/// Each patient document represents a registration event with billing info.
///
/// KEY DISTINCTION: A patient document represents a patient REGISTRATION
/// (i.e., first visit). It does NOT represent repeated visit events.
/// Therefore "Patients Registered" is the correct metric, not "Visit Count".
///
/// Fields used from patients/{patientId}:
///   - doctorId, clinicId, clinic (name fallback)
///   - createdAt (registration timestamp)
///   - totalBilled, pendingAmount, consultationFee, medicineFee
///   - billStatus (Paid | Partial | Pending | Unbilled)
///   - paymentMethod
///   - medicines (List of {name, type, dosage, duration})
///   - diagnosis, disease
///   - age, gender
class AnalyticsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ────────────────────────────────────────────────────────────────
  // CORE DATA FETCH
  // Fetches all patients for the current doctor within a date range.
  // Optionally filtered by clinicId ('all' or a specific ID).
  // ────────────────────────────────────────────────────────────────

  /// Fetches patient records for the current doctor in [start, end).
  /// [clinicId] = null means all clinics for this doctor.
  static Future<List<Map<String, dynamic>>> _fetchPatients({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final doctorId = DoctorService.currentDoctorId;
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('patients')
          .where('doctorId', isEqualTo: doctorId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end));

      if (clinicId != null && clinicId.isNotEmpty) {
        query = query.where('clinicId', isEqualTo: clinicId);
      }

      final snapshot = await query.get();
      final results = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['_docId'] = doc.id;
        results.add(data);
      }
      return results;
    } catch (e) {
      debugPrint('AnalyticsService._fetchPatients error: $e');
      if (e is FirebaseException && e.code == 'failed-precondition') {
        debugPrint('Firestore index building or missing. Falling back to in-memory date filter...');
        try {
          Query<Map<String, dynamic>> fallbackQuery = _firestore
              .collection('patients')
              .where('doctorId', isEqualTo: doctorId);

          if (clinicId != null && clinicId.isNotEmpty) {
            fallbackQuery = fallbackQuery.where('clinicId', isEqualTo: clinicId);
          }

          final snapshot = await fallbackQuery.get();
          final results = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            data['_docId'] = doc.id;
            final dt = _toDateTime(data['createdAt']);
            if (dt != null) {
              if (dt.isBefore(start) || !dt.isBefore(end)) continue;
            }
            results.add(data);
          }
          return results;
        } catch (fallbackError) {
          debugPrint('Analytics fallback error: $fallbackError');
          final snapshot = await _firestore.collection('patients').get();
          final results = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            if (data['doctorId'] != doctorId) continue;
            if (clinicId != null && clinicId.isNotEmpty && data['clinicId'] != clinicId) continue;
            data['_docId'] = doc.id;
            final dt = _toDateTime(data['createdAt']);
            if (dt != null) {
              if (dt.isBefore(start) || !dt.isBefore(end)) continue;
            }
            results.add(data);
          }
          return results;
        }
      }
      rethrow;
    }
  }


  // ────────────────────────────────────────────────────────────────
  // MAIN SUMMARY
  // ────────────────────────────────────────────────────────────────

  static Future<AnalyticsSummary> fetchSummary({
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    String? clinicId,
  }) async {
    final current = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final previous = await _fetchPatients(start: prevStart, end: prevEnd, clinicId: clinicId);

    // Security: ensure all returned patients belong to the current doctor
    bool isAuthorized(Map<String, dynamic> p) {
      final pDocId = p['doctorId']?.toString() ?? '';
      return pDocId == DoctorService.currentDoctorId;
    }

    final safePatients = current.where(isAuthorized).toList();
    final safePrevious = previous.where(isAuthorized).toList();

    double sumBilled(List<Map<String, dynamic>> list) =>
        list.fold(0.0, (s, p) => s + ((p['totalBilled'] as num?)?.toDouble() ?? 0));
    double sumPending(List<Map<String, dynamic>> list) =>
        list.fold(0.0, (s, p) => s + ((p['pendingAmount'] as num?)?.toDouble() ?? 0));
    double sumConsultation(List<Map<String, dynamic>> list) =>
        list.fold(0.0, (s, p) => s + ((p['consultationFee'] as num?)?.toDouble() ?? 0));
    double sumMedicine(List<Map<String, dynamic>> list) =>
        list.fold(0.0, (s, p) => s + ((p['medicineFee'] as num?)?.toDouble() ?? 0));

    final totalBilled = sumBilled(safePatients);
    final totalPending = sumPending(safePatients);
    final totalCollected = totalBilled - totalPending;

    // Payment method counts
    final paymentMethodCounts = <String, int>{};
    for (final p in safePatients) {
      final method = p['paymentMethod']?.toString() ?? 'UPI';
      paymentMethodCounts[method] = (paymentMethodCounts[method] ?? 0) + 1;
    }

    // Gender counts
    final genderCounts = <String, int>{};
    for (final p in safePatients) {
      final g = p['gender']?.toString() ?? 'Other';
      genderCounts[g] = (genderCounts[g] ?? 0) + 1;
    }

    // Age group counts
    final ageGroupCounts = <String, int>{};
    for (final p in safePatients) {
      final age = (p['age'] as num?)?.toInt() ?? 0;
      String group;
      if (age < 13) {
        group = '0–12';
      } else if (age < 18) {
        group = '13–17';
      } else if (age < 30) {
        group = '18–29';
      } else if (age < 45) {
        group = '30–44';
      } else if (age < 60) {
        group = '45–59';
      } else {
        group = '60+';
      }
      ageGroupCounts[group] = (ageGroupCounts[group] ?? 0) + 1;
    }

    // Bill status counts
    int paidCount = 0, pendingCount = 0, partialCount = 0;
    for (final p in safePatients) {
      final status = p['billStatus']?.toString() ?? 'Pending';
      if (status == 'Paid') {
        paidCount++;
      } else if (status == 'Partial') {
        partialCount++;
      } else {
        pendingCount++;
      }
    }

    return AnalyticsSummary(
      patientsRegistered: safePatients.length,
      patientsRegisteredPrev: safePrevious.length,
      totalBilled: totalBilled,
      totalBilledPrev: sumBilled(safePrevious),
      totalCollected: totalCollected.clamp(0, double.infinity),
      totalCollectedPrev: (sumBilled(safePrevious) - sumPending(safePrevious)).clamp(0, double.infinity),
      pendingAmount: totalPending,
      consultationRevenue: sumConsultation(safePatients),
      medicineRevenue: sumMedicine(safePatients),
      paidCount: paidCount,
      pendingCount: pendingCount,
      partialCount: partialCount,
      paymentMethodCounts: paymentMethodCounts,
      genderCounts: genderCounts,
      ageGroupCounts: ageGroupCounts,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // TREND DATA (Registrations over time)
  // ────────────────────────────────────────────────────────────────

  static Future<List<TrendPoint>> fetchRegistrationTrend({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final durationDays = end.difference(start).inDays;

    // Group by day, week, or month depending on range
    if (durationDays <= 1) {
      // Today: group by hour
      final hourMap = <int, int>{};
      for (final p in patients) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) hourMap[ts.hour] = (hourMap[ts.hour] ?? 0) + 1;
      }
      return List.generate(24, (h) {
        return TrendPoint(
          date: DateTime(start.year, start.month, start.day, h),
          value: (hourMap[h] ?? 0).toDouble(),
          label: '${h.toString().padLeft(2, '0')}:00',
        );
      });
    } else if (durationDays <= 90) {
      // Group by day
      final dayMap = <String, int>{};
      for (final p in patients) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) {
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
          dayMap[key] = (dayMap[key] ?? 0) + 1;
        }
      }
      final points = <TrendPoint>[];
      for (int i = 0; i < durationDays; i++) {
        final d = start.add(Duration(days: i));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        points.add(TrendPoint(
          date: d,
          value: (dayMap[key] ?? 0).toDouble(),
          label: '${d.day} ${months[d.month - 1]}',
        ));
      }
      return points;
    } else {
      // Group by month
      final monthMap = <String, int>{};
      for (final p in patients) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) {
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
          monthMap[key] = (monthMap[key] ?? 0) + 1;
        }
      }
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final points = <TrendPoint>[];
      DateTime cursor = DateTime(start.year, start.month, 1);
      while (cursor.isBefore(end)) {
        final key = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
        points.add(TrendPoint(
          date: cursor,
          value: (monthMap[key] ?? 0).toDouble(),
          label: '${months[cursor.month - 1]} ${cursor.year}',
        ));
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
      return points;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // REVENUE TREND
  // ────────────────────────────────────────────────────────────────

  static Future<List<TrendPoint>> fetchRevenueTrend({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final durationDays = end.difference(start).inDays;

    if (durationDays <= 90) {
      final dayMap = <String, double>{};
      for (final p in patients) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) {
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
          final billed = (p['totalBilled'] as num?)?.toDouble() ?? 0;
          dayMap[key] = (dayMap[key] ?? 0) + billed;
        }
      }
      final points = <TrendPoint>[];
      for (int i = 0; i < durationDays; i++) {
        final d = start.add(Duration(days: i));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        points.add(TrendPoint(
          date: d,
          value: dayMap[key] ?? 0,
          label: '${d.day} ${months[d.month - 1]}',
        ));
      }
      return points;
    } else {
      final monthMap = <String, double>{};
      for (final p in patients) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) {
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
          final billed = (p['totalBilled'] as num?)?.toDouble() ?? 0;
          monthMap[key] = (monthMap[key] ?? 0) + billed;
        }
      }
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final points = <TrendPoint>[];
      DateTime cursor = DateTime(start.year, start.month, 1);
      while (cursor.isBefore(end)) {
        final key = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
        points.add(TrendPoint(
          date: cursor,
          value: monthMap[key] ?? 0,
          label: '${months[cursor.month - 1]} ${cursor.year}',
        ));
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
      return points;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // MEDICINE DEMAND (from patient prescriptions)
  // ────────────────────────────────────────────────────────────────

  static Future<List<MedicineDemand>> fetchMedicineDemand({
    required DateTime start,
    required DateTime end,
    String? clinicId,
    int limit = 20,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);

    // Count medicine prescriptions across all patient records
    final nameCount = <String, int>{}; // medicine name -> prescription count
    final nameType = <String, String>{}; // medicine name -> type
    final namePatients = <String, Set<String>>{}; // medicine name -> set of patient docIds

    for (final patient in patients) {
      final rawMeds = patient['medicines'];
      if (rawMeds is! List) continue;
      final patientId = patient['_docId']?.toString() ?? '';

      for (final item in rawMeds) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final type = item['type']?.toString() ?? 'Tablet';

        nameCount[name] = (nameCount[name] ?? 0) + 1;
        nameType[name] = type;
        namePatients.putIfAbsent(name, () => {}).add(patientId);
      }
    }

    final demands = nameCount.entries.map((e) {
      return MedicineDemand(
        name: e.key,
        type: nameType[e.key] ?? 'Tablet',
        prescriptionCount: e.value,
        totalPatients: namePatients[e.key]?.length ?? 0,
      );
    }).toList();

    demands.sort((a, b) => b.prescriptionCount.compareTo(a.prescriptionCount));
    return demands.take(limit).toList();
  }

  // ────────────────────────────────────────────────────────────────
  // MEDICINE CATEGORY DEMAND
  // ────────────────────────────────────────────────────────────────

  static Future<List<MedicineCategoryDemand>> fetchMedicineCategoryDemand({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);

    final categoryCount = <String, int>{};
    final categoryNames = <String, Set<String>>{};

    for (final patient in patients) {
      final rawMeds = patient['medicines'];
      if (rawMeds is! List) continue;
      for (final item in rawMeds) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final type = item['type']?.toString() ?? 'Tablet';
        categoryCount[type] = (categoryCount[type] ?? 0) + 1;
        categoryNames.putIfAbsent(type, () => {}).add(name);
      }
    }

    final demands = categoryCount.entries.map((e) {
      return MedicineCategoryDemand(
        category: e.key,
        count: e.value,
        distinctMedicines: categoryNames[e.key]?.length ?? 0,
      );
    }).toList();

    demands.sort((a, b) => b.count.compareTo(a.count));
    return demands;
  }

  // ────────────────────────────────────────────────────────────────
  // CLINIC COMPARISON
  // ────────────────────────────────────────────────────────────────

  static Future<List<ClinicSummary>> fetchClinicComparison({
    required DateTime start,
    required DateTime end,
  }) async {
    final doctorClinics = await ClinicService.getDoctorClinics();
    final summaries = <ClinicSummary>[];

    for (final clinic in doctorClinics) {
      final cId = clinic['docId']?.toString() ?? '';
      final cName = clinic['name']?.toString() ?? 'Unknown Clinic';
      if (cId.isEmpty) continue;

      final patients = await _fetchPatients(start: start, end: end, clinicId: cId);

      double billed = 0, pending = 0, consult = 0, meds = 0;
      for (final p in patients) {
        billed += (p['totalBilled'] as num?)?.toDouble() ?? 0;
        pending += (p['pendingAmount'] as num?)?.toDouble() ?? 0;
        consult += (p['consultationFee'] as num?)?.toDouble() ?? 0;
        meds += (p['medicineFee'] as num?)?.toDouble() ?? 0;
      }

      summaries.add(ClinicSummary(
        clinicId: cId,
        clinicName: cName,
        patientsRegistered: patients.length,
        totalBilled: billed,
        totalCollected: (billed - pending).clamp(0, double.infinity),
        pendingAmount: pending,
        consultationRevenue: consult,
        medicineRevenue: meds,
      ));
    }

    // Sort by total billed descending
    summaries.sort((a, b) => b.totalBilled.compareTo(a.totalBilled));
    return summaries;
  }

  // ────────────────────────────────────────────────────────────────
  // TOP DIAGNOSES
  // ────────────────────────────────────────────────────────────────

  static Future<List<DiagnosisCount>> fetchTopDiagnoses({
    required DateTime start,
    required DateTime end,
    String? clinicId,
    int limit = 10,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final counts = <String, int>{};
    for (final p in patients) {
      final diag = p['diagnosis']?.toString().trim() ?? '';
      if (diag.isNotEmpty &&
          diag.toLowerCase() != 'under clinical review' &&
          diag.toLowerCase() != 'under review') {
        counts[diag] = (counts[diag] ?? 0) + 1;
      }
    }
    final list = counts.entries
        .map((e) => DiagnosisCount(diagnosis: e.key, count: e.value))
        .toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list.take(limit).toList();
  }

  // ────────────────────────────────────────────────────────────────
  // FEATURE 1: PATIENT LOCATION ANALYTICS
  // ────────────────────────────────────────────────────────────────

  /// Computes top summary KPIs for patient geographic distribution.
  static Future<LocationSummary> fetchLocationSummary({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final total = patients.length;

    int withLocation = 0;
    final areaCounts = <String, int>{};
    final cityCounts = <String, int>{};
    final pinCounts = <String, int>{};

    for (final p in patients) {
      final loc = _extractLocation(p);
      final area = loc.$1;
      final city = loc.$2;
      final pin = loc.$3;

      if (area != 'Location Not Available' && area.isNotEmpty) {
        withLocation++;
        areaCounts[area] = (areaCounts[area] ?? 0) + 1;
      }
      if (city != 'Unknown' && city.isNotEmpty) {
        cityCounts[city] = (cityCounts[city] ?? 0) + 1;
      }
      if (pin.isNotEmpty) {
        pinCounts[pin] = (pinCounts[pin] ?? 0) + 1;
      }
    }

    String topArea = 'None';
    if (areaCounts.isNotEmpty) {
      topArea = areaCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    String topCity = 'None';
    if (cityCounts.isNotEmpty) {
      topCity = cityCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    String topPin = 'None';
    if (pinCounts.isNotEmpty) {
      topPin = pinCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    final coverage = total > 0 ? (withLocation / total) * 100 : 0.0;

    return LocationSummary(
      totalWithLocation: withLocation,
      totalPatients: total,
      locationCoveragePct: coverage,
      topArea: topArea,
      topCity: topCity,
      topPinCode: topPin,
      areasCovered: areaCounts.length,
    );
  }

  /// Fetches top area/locality distribution with distinct patient counts and shares.
  static Future<List<AreaDistribution>> fetchAreaDistribution({
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    String? clinicId,
    int limit = 10,
  }) async {
    final current = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final previous = await _fetchPatients(start: prevStart, end: prevEnd, clinicId: clinicId);

    // Current period counts
    final areaPatientMap = <String, Set<String>>{};
    final areaCityMap = <String, String>{};
    final areaPinMap = <String, String>{};

    for (final p in current) {
      final pid = p['_docId']?.toString() ?? '';
      final loc = _extractLocation(p);
      final area = loc.$1;
      if (area == 'Location Not Available') continue;

      areaPatientMap.putIfAbsent(area, () => {}).add(pid);
      areaCityMap.putIfAbsent(area, () => loc.$2);
      if (loc.$3.isNotEmpty) areaPinMap[area] = loc.$3;
    }

    // Previous period counts for trend
    final prevAreaCount = <String, int>{};
    for (final p in previous) {
      final loc = _extractLocation(p);
      final area = loc.$1;
      if (area == 'Location Not Available') continue;
      prevAreaCount[area] = (prevAreaCount[area] ?? 0) + 1;
    }

    final totalWithLoc = areaPatientMap.values.fold<int>(0, (s, set) => s + set.length);

    final list = areaPatientMap.entries.map((e) {
      final count = e.value.length;
      final prevCount = prevAreaCount[e.key] ?? 0;
      final change = percentChange(count.toDouble(), prevCount.toDouble());
      final share = totalWithLoc > 0 ? (count / totalWithLoc) * 100 : 0.0;

      return AreaDistribution(
        area: e.key,
        city: areaCityMap[e.key] ?? 'Ahmedabad',
        pinCode: areaPinMap[e.key] ?? '—',
        patientCount: count,
        percentageShare: share,
        changePercent: change,
      );
    }).toList();

    list.sort((a, b) => b.patientCount.compareTo(a.patientCount));
    return list.take(limit).toList();
  }

  /// Fetches city-wise patient distribution.
  static Future<List<CityDistribution>> fetchCityDistribution({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);

    final cityPatients = <String, Set<String>>{};
    final cityAreas = <String, Map<String, int>>{};

    for (final p in patients) {
      final pid = p['_docId']?.toString() ?? '';
      final loc = _extractLocation(p);
      final city = loc.$2;
      final area = loc.$1;

      cityPatients.putIfAbsent(city, () => {}).add(pid);
      if (area != 'Location Not Available') {
        cityAreas.putIfAbsent(city, () => {});
        cityAreas[city]![area] = (cityAreas[city]![area] ?? 0) + 1;
      }
    }

    final total = cityPatients.values.fold<int>(0, (s, set) => s + set.length);

    final list = cityPatients.entries.map((e) {
      final count = e.value.length;
      final share = total > 0 ? (count / total) * 100 : 0.0;

      // Top represented areas for this city
      final areasMap = cityAreas[e.key] ?? {};
      final sortedAreas = areasMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final topAreas = sortedAreas.take(3).map((a) => a.key).toList();

      return CityDistribution(
        city: e.key,
        patientCount: count,
        percentageShare: share,
        topAreas: topAreas,
      );
    }).toList();

    list.sort((a, b) => b.patientCount.compareTo(a.patientCount));
    return list;
  }

  /// Fetches valid 6-digit Indian PIN codes and patient distribution.
  static Future<List<PinCodeDistribution>> fetchPinCodeDistribution({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);

    final pinPatients = <String, Set<String>>{};
    final pinArea = <String, String>{};

    for (final p in patients) {
      final pid = p['_docId']?.toString() ?? '';
      final loc = _extractLocation(p);
      final pin = loc.$3;
      final area = loc.$1;

      if (pin.isNotEmpty) {
        pinPatients.putIfAbsent(pin, () => {}).add(pid);
        if (area != 'Location Not Available') {
          pinArea.putIfAbsent(pin, () => area);
        }
      }
    }

    final totalWithPin = pinPatients.values.fold<int>(0, (s, set) => s + set.length);

    final list = pinPatients.entries.map((e) {
      final count = e.value.length;
      final share = totalWithPin > 0 ? (count / totalWithPin) * 100 : 0.0;
      return PinCodeDistribution(
        pinCode: e.key,
        patientCount: count,
        percentageShare: share,
        area: pinArea[e.key] ?? 'Local Area',
      );
    }).toList();

    list.sort((a, b) => b.patientCount.compareTo(a.patientCount));
    return list;
  }

  /// Multi-clinic comparison for patient geographic origins.
  static Future<List<ClinicLocationComparison>> fetchClinicLocationComparison({
    required DateTime start,
    required DateTime end,
  }) async {
    final doctorClinics = await ClinicService.getDoctorClinics();
    final list = <ClinicLocationComparison>[];

    for (final c in doctorClinics) {
      final cId = c['docId']?.toString() ?? '';
      final cName = c['name']?.toString() ?? 'Clinic';
      if (cId.isEmpty) continue;

      final patients = await _fetchPatients(start: start, end: end, clinicId: cId);
      final total = patients.length;

      int withLoc = 0;
      final areaCounts = <String, int>{};
      final cityCounts = <String, int>{};

      for (final p in patients) {
        final loc = _extractLocation(p);
        final area = loc.$1;
        final city = loc.$2;

        if (area != 'Location Not Available' && area.isNotEmpty) {
          withLoc++;
          areaCounts[area] = (areaCounts[area] ?? 0) + 1;
        }
        if (city != 'Unknown' && city.isNotEmpty) {
          cityCounts[city] = (cityCounts[city] ?? 0) + 1;
        }
      }

      String topArea = 'None';
      if (areaCounts.isNotEmpty) {
        topArea = areaCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      String topCity = 'None';
      if (cityCounts.isNotEmpty) {
        topCity = cityCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }

      final cov = total > 0 ? (withLoc / total) * 100 : 0.0;

      list.add(ClinicLocationComparison(
        clinicId: cId,
        clinicName: cName,
        patientsWithLocation: withLoc,
        totalPatients: total,
        topArea: topArea,
        topCity: topCity,
        areasCovered: areaCounts.length,
        coveragePct: cov,
      ));
    }

    list.sort((a, b) => b.patientsWithLocation.compareTo(a.patientsWithLocation));
    return list;
  }

  // ────────────────────────────────────────────────────────────────
  // FEATURE 2: DISEASE & DIAGNOSIS ANALYTICS
  // ────────────────────────────────────────────────────────────────

  /// Computes summary KPIs for Disease & Diagnosis Analytics.
  static Future<DiseaseSummary> fetchDiseaseSummary({
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    String? clinicId,
  }) async {
    final current = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final previous = await _fetchPatients(start: prevStart, end: prevEnd, clinicId: clinicId);

    final total = current.length;
    final diagCounts = <String, int>{};
    final categoryCounts = <String, int>{};
    int withDiag = 0;

    for (final p in current) {
      final extracted = _extractDiagnosis(p);
      final diag = extracted.$1;
      final cat = extracted.$2;

      if (diag != 'General Consultation' && diag != 'Under Clinical Review') {
        withDiag++;
        diagCounts[diag] = (diagCounts[diag] ?? 0) + 1;
      }
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }

    String topDiag = 'General Consultation';
    if (diagCounts.isNotEmpty) {
      topDiag = diagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    String topCat = 'General & Infectious';
    if (categoryCounts.isNotEmpty) {
      topCat = categoryCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    int prevWithDiag = 0;
    for (final p in previous) {
      final diag = _extractDiagnosis(p).$1;
      if (diag != 'General Consultation' && diag != 'Under Clinical Review') {
        prevWithDiag++;
      }
    }

    final change = percentChange(withDiag.toDouble(), prevWithDiag.toDouble());
    final coverage = total > 0 ? (withDiag / total) * 100 : 0.0;

    return DiseaseSummary(
      topDiagnosis: topDiag,
      distinctPatientsWithDiagnosis: withDiag,
      totalPatients: total,
      diagnosisCoveragePct: coverage,
      distinctCategories: categoryCounts.length,
      topCategory: topCat,
      changePercent: change,
    );
  }

  /// Fetches ranked disease/diagnosis list with clinic breakdown and trends.
  static Future<List<DiseaseRecord>> fetchDiseaseRankings({
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    String? clinicId,
    int limit = 10,
  }) async {
    final current = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final previous = await _fetchPatients(start: prevStart, end: prevEnd, clinicId: clinicId);

    final diagPatients = <String, Set<String>>{};
    final diagVisits = <String, int>{};
    final diagCategory = <String, String>{};
    final diagClinics = <String, Map<String, int>>{};

    for (final p in current) {
      final pid = p['_docId']?.toString() ?? '';
      final cName = p['clinic']?.toString() ?? 'Clinic';
      final extracted = _extractDiagnosis(p);
      final diag = extracted.$1;
      final cat = extracted.$2;
      final visits = (p['totalVisits'] as num?)?.toInt() ?? 1;

      diagPatients.putIfAbsent(diag, () => {}).add(pid);
      diagVisits[diag] = (diagVisits[diag] ?? 0) + visits;
      diagCategory.putIfAbsent(diag, () => cat);

      diagClinics.putIfAbsent(diag, () => {});
      diagClinics[diag]![cName] = (diagClinics[diag]![cName] ?? 0) + 1;
    }

    final prevDiagCount = <String, int>{};
    for (final p in previous) {
      final diag = _extractDiagnosis(p).$1;
      prevDiagCount[diag] = (prevDiagCount[diag] ?? 0) + 1;
    }

    final totalDistinct = diagPatients.values.fold<int>(0, (s, set) => s + set.length);

    final list = diagPatients.entries.map((e) {
      final count = e.value.length;
      final prevCount = prevDiagCount[e.key] ?? 0;
      final change = percentChange(count.toDouble(), prevCount.toDouble());
      final share = totalDistinct > 0 ? (count / totalDistinct) * 100 : 0.0;

      return DiseaseRecord(
        diagnosis: e.key,
        category: diagCategory[e.key] ?? 'Other / Uncategorized',
        patientCount: count,
        visitCount: diagVisits[e.key] ?? count,
        percentageShare: share,
        clinicDistribution: diagClinics[e.key] ?? {},
        changePercent: change,
      );
    }).toList();

    list.sort((a, b) => b.patientCount.compareTo(a.patientCount));
    return list.take(limit).toList();
  }

  /// Fetches disease category distribution (Respiratory, Gastrointestinal, etc.).
  static Future<List<DiseaseCategoryDistribution>> fetchDiseaseCategoryDistribution({
    required DateTime start,
    required DateTime end,
    String? clinicId,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);

    final catPatients = <String, Set<String>>{};
    final catDiseases = <String, Set<String>>{};

    for (final p in patients) {
      final pid = p['_docId']?.toString() ?? '';
      final extracted = _extractDiagnosis(p);
      final diag = extracted.$1;
      final cat = extracted.$2;

      catPatients.putIfAbsent(cat, () => {}).add(pid);
      catDiseases.putIfAbsent(cat, () => {}).add(diag);
    }

    final total = catPatients.values.fold<int>(0, (s, set) => s + set.length);

    final list = catPatients.entries.map((e) {
      final count = e.value.length;
      final share = total > 0 ? (count / total) * 100 : 0.0;
      return DiseaseCategoryDistribution(
        category: e.key,
        patientCount: count,
        distinctDiseases: catDiseases[e.key]?.length ?? 0,
        percentageShare: share,
      );
    }).toList();

    list.sort((a, b) => b.patientCount.compareTo(a.patientCount));
    return list;
  }

  /// Fetches disease trends over time grouped by category or top diagnoses.
  static Future<List<TrendPoint>> fetchDiseaseTrend({
    required DateTime start,
    required DateTime end,
    String? clinicId,
    String? targetCategory,
  }) async {
    final patients = await _fetchPatients(start: start, end: end, clinicId: clinicId);
    final durationDays = end.difference(start).inDays;

    final filtered = targetCategory == null
        ? patients
        : patients.where((p) => _extractDiagnosis(p).$2 == targetCategory).toList();

    if (durationDays <= 90) {
      final dayMap = <String, int>{};
      for (final p in filtered) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) {
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
          dayMap[key] = (dayMap[key] ?? 0) + 1;
        }
      }
      final points = <TrendPoint>[];
      for (int i = 0; i < durationDays; i++) {
        final d = start.add(Duration(days: i));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        points.add(TrendPoint(
          date: d,
          value: (dayMap[key] ?? 0).toDouble(),
          label: '${d.day} ${months[d.month - 1]}',
        ));
      }
      return points;
    } else {
      final monthMap = <String, int>{};
      for (final p in filtered) {
        final ts = _toDateTime(p['createdAt']);
        if (ts != null) {
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
          monthMap[key] = (monthMap[key] ?? 0) + 1;
        }
      }
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final points = <TrendPoint>[];
      DateTime cursor = DateTime(start.year, start.month, 1);
      while (cursor.isBefore(end)) {
        final key = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
        points.add(TrendPoint(
          date: cursor,
          value: (monthMap[key] ?? 0).toDouble(),
          label: '${months[cursor.month - 1]} ${cursor.year}',
        ));
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
      return points;
    }
  }

  /// Multi-clinic comparison for clinical diagnoses and categories.
  static Future<List<ClinicDiseaseComparison>> fetchClinicDiseaseComparison({
    required DateTime start,
    required DateTime end,
  }) async {
    final doctorClinics = await ClinicService.getDoctorClinics();
    final list = <ClinicDiseaseComparison>[];

    for (final c in doctorClinics) {
      final cId = c['docId']?.toString() ?? '';
      final cName = c['name']?.toString() ?? 'Clinic';
      if (cId.isEmpty) continue;

      final patients = await _fetchPatients(start: start, end: end, clinicId: cId);
      final diagCounts = <String, int>{};
      final catCounts = <String, int>{};
      int withDiag = 0;

      for (final p in patients) {
        final extracted = _extractDiagnosis(p);
        final diag = extracted.$1;
        final cat = extracted.$2;

        if (diag != 'General Consultation' && diag != 'Under Clinical Review') {
          withDiag++;
          diagCounts[diag] = (diagCounts[diag] ?? 0) + 1;
        }
        catCounts[cat] = (catCounts[cat] ?? 0) + 1;
      }

      String topDiag = 'None';
      if (diagCounts.isNotEmpty) {
        topDiag = diagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      String topCat = 'None';
      if (catCounts.isNotEmpty) {
        topCat = catCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }

      list.add(ClinicDiseaseComparison(
        clinicId: cId,
        clinicName: cName,
        patientsWithDiagnosis: withDiag,
        topDiagnosis: topDiag,
        topCategory: topCat,
        categoryCounts: catCounts,
      ));
    }

    list.sort((a, b) => b.patientsWithDiagnosis.compareTo(a.patientsWithDiagnosis));
    return list;
  }

  // ────────────────────────────────────────────────────────────────
  // NORMALIZATION & EXTRACTION HELPERS
  // ────────────────────────────────────────────────────────────────

  static (String, String, String) _extractLocation(Map<String, dynamic> p) {
    String area = (p['area']?.toString() ?? '').trim();
    String city = (p['city']?.toString() ?? '').trim();
    String pinCode = (p['pinCode']?.toString() ?? '').trim();
    final rawAddress = (p['address']?.toString() ?? '').trim();

    // 1. PIN code extraction/validation (Indian 6-digit regex)
    final pinRegex = RegExp(r'\b[1-9][0-9]{5}\b');
    if (pinCode.isNotEmpty) {
      final match = pinRegex.firstMatch(pinCode);
      pinCode = match != null ? match.group(0)! : '';
    } else if (rawAddress.isNotEmpty) {
      final match = pinRegex.firstMatch(rawAddress);
      if (match != null) pinCode = match.group(0)!;
    }

    // 2. City extraction
    const knownCities = [
      'Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Gandhinagar',
      'Bhavnagar', 'Jamnagar', 'Junagadh', 'Anand', 'Navsari',
      'Morbi', 'Mehsana', 'Bharuch', 'Valsad', 'Patan', 'Palanpur',
      'Porbandar', 'Nadiad', 'Surendranagar', 'Amreli', 'Mumbai', 'Delhi', 'Pune'
    ];
    if (city.isEmpty && rawAddress.isNotEmpty) {
      for (final kc in knownCities) {
        if (RegExp('\\b${RegExp.escape(kc)}\\b', caseSensitive: false).hasMatch(rawAddress)) {
          city = kc;
          break;
        }
      }
    }
    if (city.isEmpty) {
      city = 'Ahmedabad'; // Default clinic base city
    }

    // 3. Area extraction
    if (area.isEmpty && rawAddress.isNotEmpty) {
      final parts = rawAddress.split(RegExp(r'[,–-]')).map((s) => s.trim()).toList();
      const ignoreWords = [
        'gujarat', 'india', 'ahmedabad', 'surat', 'vadodara', 'rajkot', 'road', 'street',
        'flat', 'block', 'plot', 'society', 'apartment', 'heights', 'residency', 'near', 'opp', 'b/h'
      ];
      for (final part in parts) {
        if (part.isEmpty) continue;
        if (pinRegex.hasMatch(part)) continue;
        final lower = part.toLowerCase();
        if (ignoreWords.contains(lower)) continue;
        if (RegExp(r'^[0-9]+').hasMatch(part)) continue;
        if (part.length >= 3 && part.length <= 30) {
          area = part;
          break;
        }
      }
    }
    if (area.isEmpty) {
      area = rawAddress.isNotEmpty ? 'General $city' : 'Location Not Available';
    }

    return (area, city, pinCode);
  }

  static (String, String) _extractDiagnosis(Map<String, dynamic> p) {
    String diagnosis = (p['diagnosis']?.toString() ?? '').trim();
    final disease = (p['disease']?.toString() ?? '').trim();
    String category = (p['diseaseCategory']?.toString() ?? '').trim();

    if (diagnosis.isEmpty ||
        diagnosis.toLowerCase() == 'under clinical review' ||
        diagnosis.toLowerCase() == 'under review') {
      diagnosis = disease.isNotEmpty ? disease : 'General Consultation';
    }

    if (category.isEmpty || category.toLowerCase() == 'other / uncategorized') {
      final combined = '${diagnosis.toLowerCase()} ${disease.toLowerCase()}';
      if (combined.contains('fever') || combined.contains('pyrexia') || combined.contains('malaria') ||
          combined.contains('dengue') || combined.contains('typhoid') || combined.contains('viral') ||
          combined.contains('weakness') || combined.contains('infection')) {
        category = 'General & Infectious';
      } else if (combined.contains('cough') || combined.contains('cold') || combined.contains('asthma') ||
          combined.contains('bronchitis') || combined.contains('pneumonia') || combined.contains('throat') ||
          combined.contains('breath') || combined.contains('sinus') || combined.contains('urti')) {
        category = 'Respiratory';
      } else if (combined.contains('hypertension') || combined.contains('bp') || combined.contains('chest pain') ||
          combined.contains('cardiac') || combined.contains('palpitation') || combined.contains('ischemic')) {
        category = 'Cardiovascular';
      } else if (combined.contains('diabetes') || combined.contains('sugar') || combined.contains('thyroid') ||
          combined.contains('hypothyroidism') || combined.contains('hyperglycemia')) {
        category = 'Endocrine & Metabolic';
      } else if (combined.contains('acidity') || combined.contains('gastritis') || combined.contains('gerd') ||
          combined.contains('stomach') || combined.contains('diarrhea') || combined.contains('vomiting') ||
          combined.contains('abdominal') || combined.contains('constipation') || combined.contains('nausea') ||
          combined.contains('dyspepsia')) {
        category = 'Gastrointestinal & Digestive';
      } else if (combined.contains('joint') || combined.contains('arthritis') || combined.contains('back pain') ||
          combined.contains('cervical') || combined.contains('spondylitis') || combined.contains('knee') ||
          combined.contains('ortho') || combined.contains('sciatica') || combined.contains('myalgia')) {
        category = 'Musculoskeletal & Orthopedic';
      } else if (combined.contains('rash') || combined.contains('skin') || combined.contains('itching') ||
          combined.contains('eczema') || combined.contains('psoriasis') || combined.contains('fungal') ||
          combined.contains('acne') || combined.contains('dermatitis')) {
        category = 'Dermatology & Skin';
      } else if (combined.contains('ear') || combined.contains('eye') || combined.contains('conjunctivitis') ||
          combined.contains('hearing') || combined.contains('vision') || combined.contains('otitis')) {
        category = 'ENT & Ophthalmology';
      } else if (combined.contains('headache') || combined.contains('migraine') || combined.contains('vertigo') ||
          combined.contains('dizziness') || combined.contains('anxiety') || combined.contains('insomnia') ||
          combined.contains('seizure')) {
        category = 'Neurology & Psychiatric';
      } else {
        category = 'Other / Uncategorized';
      }
    }

    return (diagnosis, category);
  }

  // ────────────────────────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────────────────────────

  static DateTime? _toDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Calculates percentage change safely (no div-by-zero).
  static double? percentChange(double current, double previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous) * 100;
  }
}
