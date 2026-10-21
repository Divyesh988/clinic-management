import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_update_config.dart';
import '../models/app_version.dart';

/// Enumeration of all possible app update check states.
enum AppUpdateStatus {
  upToDate,
  optionalUpdateAvailable,
  mandatoryUpdateRequired,
  updatesDisabled,
  configurationError,
  networkError,
}

/// Result object describing the outcome of an update check.
class AppUpdateCheckResult {
  final AppUpdateStatus status;
  final AppVersion currentVersion;
  final AppUpdateConfig? config;
  final String? errorMessage;

  const AppUpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.config,
    this.errorMessage,
  });

  bool get hasUpdate =>
      status == AppUpdateStatus.optionalUpdateAvailable ||
      status == AppUpdateStatus.mandatoryUpdateRequired;

  bool get isMandatory => status == AppUpdateStatus.mandatoryUpdateRequired;

  @override
  String toString() =>
      'AppUpdateCheckResult(status: $status, currentVersion: $currentVersion, latest: ${config?.latestVersion})';
}

/// Service managing remote update metadata from Firestore and determining
/// whether the installed CliniqCare app requires an update.
class AppUpdateService {
  static const String documentPath = 'app_config/updates_android_production';
  static const Duration cacheValidity = Duration(minutes: 10);
  static const Duration requestTimeout = Duration(seconds: 10);

  static AppUpdateCheckResult? _cachedResult;
  static DateTime? _lastFetchTime;
  static bool _isChecking = false;

  /// Optional override for tests.
  @visibleForTesting
  static FirebaseFirestore? firestoreOverride;

  @visibleForTesting
  static AppVersion? installedVersionOverride;

  /// Global notifier of the latest update check result.
  static final ValueNotifier<AppUpdateCheckResult?> updateResultNotifier =
      ValueNotifier<AppUpdateCheckResult?>(null);

  /// Retrieves the installed app version via PackageInfo.
  static Future<AppVersion> getInstalledVersion() async {
    if (installedVersionOverride != null) {
      return installedVersionOverride!;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      final ver = AppVersion.parse(info.version, build);
      debugPrint('[AppUpdateService] Running app detected as: $ver (versionName: ${info.version}, versionCode: ${info.buildNumber})');
      return ver;
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to retrieve PackageInfo: $e');
      return const AppVersion(major: 1, minor: 0, patch: 0, buildNumber: 1, rawVersion: '1.0.0+1');
    }
  }

  /// Checks for available updates from Firestore.
  /// Throttled by default to avoid repeated network reads, unless [forceRefresh] is true.
  static Future<AppUpdateCheckResult> checkForUpdates({
    bool forceRefresh = false,
  }) async {
    // Return cached result if fresh
    if (!forceRefresh &&
        _cachedResult != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheValidity) {
      return _cachedResult!;
    }

    if (_isChecking && _cachedResult != null) {
      return _cachedResult!;
    }

    _isChecking = true;
    final currentVersion = await getInstalledVersion();

    try {
      final firestore = firestoreOverride ?? FirebaseFirestore.instance;
      final docRef = firestore.doc(documentPath);

      final snapshot = await docRef.get().timeout(requestTimeout);

      if (!snapshot.exists || snapshot.data() == null) {
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.configurationError,
          currentVersion: currentVersion,
          errorMessage: 'Update metadata document does not exist in Firestore at $documentPath',
        );
        _updateCache(result);
        return result;
      }

      final data = snapshot.data()!;
      final config = AppUpdateConfig.fromMap(data);

      if (!config.enabled) {
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.updatesDisabled,
          currentVersion: currentVersion,
          config: config,
        );
        _updateCache(result);
        return result;
      }

      if (!config.isValid) {
        final result = AppUpdateCheckResult(
          status: AppUpdateStatus.configurationError,
          currentVersion: currentVersion,
          config: config,
          errorMessage: 'Update configuration contains invalid or insecure URLs',
        );
        _updateCache(result);
        return result;
      }

      // Version evaluation logic
      final AppUpdateStatus status;
      if (currentVersion < config.minimumSupportedVersion ||
          (config.forceUpdate && currentVersion < config.latestVersion)) {
        status = AppUpdateStatus.mandatoryUpdateRequired;
      } else if (currentVersion < config.latestVersion) {
        status = AppUpdateStatus.optionalUpdateAvailable;
      } else {
        status = AppUpdateStatus.upToDate;
      }

      debugPrint('[AppUpdateService] Version check evaluated: current=$currentVersion, latest=${config.latestVersion}, min=${config.minimumSupportedVersion}, forceUpdate=${config.forceUpdate} => status=$status');

      final result = AppUpdateCheckResult(
        status: status,
        currentVersion: currentVersion,
        config: config,
      );

      _updateCache(result);
      return result;
    } on TimeoutException {
      debugPrint('[AppUpdateService] Request timed out while fetching update configuration');
      final result = AppUpdateCheckResult(
        status: AppUpdateStatus.networkError,
        currentVersion: currentVersion,
        errorMessage: 'Connection timed out. Please check your internet connection.',
      );
      // Do not cache network errors for long
      return result;
    } on FirebaseException catch (e) {
      debugPrint('[AppUpdateService] Firestore error: ${e.code} - ${e.message}');
      final isNetwork = e.code == 'unavailable' || e.code == 'deadline-exceeded';
      final result = AppUpdateCheckResult(
        status: isNetwork ? AppUpdateStatus.networkError : AppUpdateStatus.configurationError,
        currentVersion: currentVersion,
        errorMessage: e.message ?? e.code,
      );
      return result;
    } catch (e) {
      debugPrint('[AppUpdateService] Unexpected error: $e');
      final result = AppUpdateCheckResult(
        status: AppUpdateStatus.networkError,
        currentVersion: currentVersion,
        errorMessage: e.toString(),
      );
      return result;
    } finally {
      _isChecking = false;
    }
  }

  static void _updateCache(AppUpdateCheckResult result) {
    _cachedResult = result;
    _lastFetchTime = DateTime.now();
    updateResultNotifier.value = result;
  }

  /// Clears cache for manual retry.
  static void clearCache() {
    _cachedResult = null;
    _lastFetchTime = null;
  }
}
