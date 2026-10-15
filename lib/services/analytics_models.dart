/// Analytics data models for the Clinic Management System.
/// These models are computed from real Firestore data — patients/{patientId}.

/// Available date range presets for analytics filtering.
enum DateRangePreset {
  today,
  yesterday,
  last7Days,
  last30Days,
  last90Days,
  thisMonth,
  previousMonth,
  thisYear,
  custom,
}

extension DateRangePresetExt on DateRangePreset {
  String get label {
    switch (this) {
      case DateRangePreset.today:
        return 'Today';
      case DateRangePreset.yesterday:
        return 'Yesterday';
      case DateRangePreset.last7Days:
        return 'Last 7 Days';
      case DateRangePreset.last30Days:
        return 'Last 30 Days';
      case DateRangePreset.last90Days:
        return 'Last 90 Days';
      case DateRangePreset.thisMonth:
        return 'This Month';
      case DateRangePreset.previousMonth:
        return 'Previous Month';
      case DateRangePreset.thisYear:
        return 'This Year';
      case DateRangePreset.custom:
        return 'Custom Range';
    }
  }

  /// Returns [start, end] DateTime for the preset (local time, end is inclusive).
  List<DateTime> toDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case DateRangePreset.today:
        return [today, today.add(const Duration(days: 1))];
      case DateRangePreset.yesterday:
        final yest = today.subtract(const Duration(days: 1));
        return [yest, today];
      case DateRangePreset.last7Days:
        return [today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))];
      case DateRangePreset.last30Days:
        return [today.subtract(const Duration(days: 29)), today.add(const Duration(days: 1))];
      case DateRangePreset.last90Days:
        return [today.subtract(const Duration(days: 89)), today.add(const Duration(days: 1))];
      case DateRangePreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return [start, end];
      case DateRangePreset.previousMonth:
        final prevStart = DateTime(now.year, now.month - 1, 1);
        final prevEnd = DateTime(now.year, now.month, 1);
        return [prevStart, prevEnd];
      case DateRangePreset.thisYear:
        return [DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1)];
      case DateRangePreset.custom:
        return [today, today.add(const Duration(days: 1))];
    }
  }

  /// Returns the equivalent previous period range for comparison.
  List<DateTime> toPreviousPeriodRange() {
    final current = toDateRange();
    final duration = current[1].difference(current[0]);
    return [current[0].subtract(duration), current[0]];
  }
}

/// KPI data for a single metric card.
class KpiData {
  final String label;
  final String value;
  final String? subtitle;
  final double? changePercent; // null = no comparison available
  final bool isPositiveChange; // true = green up, false = red down
  final String? tooltip;

  const KpiData({
    required this.label,
    required this.value,
    this.subtitle,
    this.changePercent,
    this.isPositiveChange = true,
    this.tooltip,
  });
}

/// Top-level analytics summary calculated from patients collection.
class AnalyticsSummary {
  final int patientsRegistered;       // Patients created in period
  final int patientsRegisteredPrev;   // Same for previous period (comparison)
  final double totalBilled;
  final double totalBilledPrev;
  final double totalCollected;        // billed - pending for Paid patients
  final double totalCollectedPrev;
  final double pendingAmount;
  final double consultationRevenue;
  final double medicineRevenue;
  final int paidCount;
  final int pendingCount;
  final int partialCount;
  final Map<String, int> paymentMethodCounts; // UPI, Cash, Card, etc.

  // Gender breakdown
  final Map<String, int> genderCounts;

  // Age group breakdown
  final Map<String, int> ageGroupCounts;

  const AnalyticsSummary({
    required this.patientsRegistered,
    required this.patientsRegisteredPrev,
    required this.totalBilled,
    required this.totalBilledPrev,
    required this.totalCollected,
    required this.totalCollectedPrev,
    required this.pendingAmount,
    required this.consultationRevenue,
    required this.medicineRevenue,
    required this.paidCount,
    required this.pendingCount,
    required this.partialCount,
    required this.paymentMethodCounts,
    required this.genderCounts,
    required this.ageGroupCounts,
  });
}

/// A data point for a time-series chart (visits/revenue over time).
class TrendPoint {
  final DateTime date;
  final double value;
  final String label;

  const TrendPoint({required this.date, required this.value, required this.label});
}

/// Data about a medicine's prescription demand.
class MedicineDemand {
  final String name;
  final String type;
  final String? brandName;
  final int prescriptionCount;   // How many patient records contain this medicine
  final int totalPatients;       // Distinct patients who were prescribed it

  const MedicineDemand({
    required this.name,
    required this.type,
    this.brandName,
    required this.prescriptionCount,
    required this.totalPatients,
  });
}

/// Per-category demand for medicines (Tablet, Capsule, Syrup, etc.)
class MedicineCategoryDemand {
  final String category;
  final int count;
  final int distinctMedicines;

  const MedicineCategoryDemand({
    required this.category,
    required this.count,
    required this.distinctMedicines,
  });
}

/// Clinic-level summary for multi-clinic comparison.
class ClinicSummary {
  final String clinicId;
  final String clinicName;
  final int patientsRegistered;
  final double totalBilled;
  final double totalCollected;
  final double pendingAmount;
  final double consultationRevenue;
  final double medicineRevenue;

  const ClinicSummary({
    required this.clinicId,
    required this.clinicName,
    required this.patientsRegistered,
    required this.totalBilled,
    required this.totalCollected,
    required this.pendingAmount,
    required this.consultationRevenue,
    required this.medicineRevenue,
  });
}

/// Diagnoses distribution for patient analytics.
class DiagnosisCount {
  final String diagnosis;
  final int count;

  const DiagnosisCount({required this.diagnosis, required this.count});
}

// ────────────────────────────────────────────────────────────────
// FEATURE 1: PATIENT LOCATION ANALYTICS MODELS
// ────────────────────────────────────────────────────────────────

/// High-level summary of patient geographic distribution.
class LocationSummary {
  final int totalWithLocation;
  final int totalPatients;
  final double locationCoveragePct;
  final String topArea;
  final String topCity;
  final String topPinCode;
  final int areasCovered;

  const LocationSummary({
    required this.totalWithLocation,
    required this.totalPatients,
    required this.locationCoveragePct,
    required this.topArea,
    required this.topCity,
    required this.topPinCode,
    required this.areasCovered,
  });
}

/// Area / locality distribution entry.
class AreaDistribution {
  final String area;
  final String city;
  final String pinCode;
  final int patientCount;
  final double percentageShare;
  final double? changePercent;

  const AreaDistribution({
    required this.area,
    required this.city,
    required this.pinCode,
    required this.patientCount,
    required this.percentageShare,
    this.changePercent,
  });
}

/// City distribution entry.
class CityDistribution {
  final String city;
  final int patientCount;
  final double percentageShare;
  final List<String> topAreas;

  const CityDistribution({
    required this.city,
    required this.patientCount,
    required this.percentageShare,
    required this.topAreas,
  });
}

/// Indian 6-digit PIN code distribution entry.
class PinCodeDistribution {
  final String pinCode;
  final int patientCount;
  final double percentageShare;
  final String area;

  const PinCodeDistribution({
    required this.pinCode,
    required this.patientCount,
    required this.percentageShare,
    required this.area,
  });
}

/// Multi-clinic location comparison.
class ClinicLocationComparison {
  final String clinicId;
  final String clinicName;
  final int patientsWithLocation;
  final int totalPatients;
  final String topArea;
  final String topCity;
  final int areasCovered;
  final double coveragePct;

  const ClinicLocationComparison({
    required this.clinicId,
    required this.clinicName,
    required this.patientsWithLocation,
    required this.totalPatients,
    required this.topArea,
    required this.topCity,
    required this.areasCovered,
    required this.coveragePct,
  });
}

// ────────────────────────────────────────────────────────────────
// FEATURE 2: DISEASE & DIAGNOSIS ANALYTICS MODELS
// ────────────────────────────────────────────────────────────────

/// Summary card metrics for Disease & Diagnosis Analytics.
class DiseaseSummary {
  final String topDiagnosis;
  final int distinctPatientsWithDiagnosis;
  final int totalPatients;
  final double diagnosisCoveragePct;
  final int distinctCategories;
  final String topCategory;
  final double? changePercent;

  const DiseaseSummary({
    required this.topDiagnosis,
    required this.distinctPatientsWithDiagnosis,
    required this.totalPatients,
    required this.diagnosisCoveragePct,
    required this.distinctCategories,
    required this.topCategory,
    this.changePercent,
  });
}

/// Individual disease/diagnosis record with distinct patient count and clinic breakdown.
class DiseaseRecord {
  final String diagnosis;
  final String category;
  final int patientCount;
  final int visitCount;
  final double percentageShare;
  final Map<String, int> clinicDistribution; // clinicName -> count
  final double? changePercent;

  const DiseaseRecord({
    required this.diagnosis,
    required this.category,
    required this.patientCount,
    required this.visitCount,
    required this.percentageShare,
    required this.clinicDistribution,
    this.changePercent,
  });
}

/// Disease category distribution entry (Respiratory, Cardiovascular, etc.).
class DiseaseCategoryDistribution {
  final String category;
  final int patientCount;
  final int distinctDiseases;
  final double percentageShare;

  const DiseaseCategoryDistribution({
    required this.category,
    required this.patientCount,
    required this.distinctDiseases,
    required this.percentageShare,
  });
}

/// Multi-clinic comparison for diseases and clinical categories.
class ClinicDiseaseComparison {
  final String clinicId;
  final String clinicName;
  final int patientsWithDiagnosis;
  final String topDiagnosis;
  final String topCategory;
  final Map<String, int> categoryCounts;

  const ClinicDiseaseComparison({
    required this.clinicId,
    required this.clinicName,
    required this.patientsWithDiagnosis,
    required this.topDiagnosis,
    required this.topCategory,
    required this.categoryCounts,
  });
}
