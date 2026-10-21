import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_update_config.dart';
import '../models/app_version.dart';
import '../widgets/update_dialog.dart';

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
  static AppVersion? _cachedInstalledVersion;

  /// Synchronously returns cached installed version if already retrieved.
  static AppVersion? get currentInstalledVersion => _cachedInstalledVersion;

  /// Global notifier of the latest update check result.
  static final ValueNotifier<AppUpdateCheckResult?> updateResultNotifier =
      ValueNotifier<AppUpdateCheckResult?>(null);

  /// Retrieves the installed app version via PackageInfo.
  static Future<AppVersion> getInstalledVersion() async {
    if (installedVersionOverride != null) {
      return installedVersionOverride!;
    }
    if (_cachedInstalledVersion != null) {
      return _cachedInstalledVersion!;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      final version = AppVersion.parse(info.version, build);
      _cachedInstalledVersion = version;
      return version;
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

      // Version evaluation logic:
      // An update is available if:
      // 1. Android build number / versionCode is newer: config.latestVersion.buildNumber > currentVersion.buildNumber
      // 2. OR Semantic version is newer: currentVersion < config.latestVersion
      final bool hasNewerBuild = config.latestVersion.buildNumber > currentVersion.buildNumber;
      final bool hasNewerSemver = currentVersion < config.latestVersion;
      final bool isUpdateAvailable = hasNewerBuild || hasNewerSemver;

      final bool isBelowMinBuild = config.minimumSupportedVersion.buildNumber > 0 &&
          currentVersion.buildNumber < config.minimumSupportedVersion.buildNumber;
      final bool isBelowMinSemver = currentVersion < config.minimumSupportedVersion;
      final bool isMandatory = (isBelowMinBuild || isBelowMinSemver) ||
          (config.forceUpdate && isUpdateAvailable);

      final AppUpdateStatus status;
      if (!isUpdateAvailable) {
        status = AppUpdateStatus.upToDate;
      } else if (isMandatory) {
        status = AppUpdateStatus.mandatoryUpdateRequired;
      } else {
        status = AppUpdateStatus.optionalUpdateAvailable;
      }

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

  /// Session guard to ensure we prompt the doctor at most once per session.
  static bool _hasPromptedOptionalDialog = false;

  /// Resets the prompted state for manual checks (e.g. from Profile or Settings).
  static void resetPromptedState() {
    _hasPromptedOptionalDialog = false;
  }

  /// Presents the optional update dialog if an update is available and hasn't yet
  /// been prompted in this session.
  static void showOptionalDialogIfAvailable(BuildContext? context) {
    if (_hasPromptedOptionalDialog) return;
    final result = updateResultNotifier.value;
    if (result == null ||
        result.status != AppUpdateStatus.optionalUpdateAvailable ||
        result.config == null) {
      return;
    }

    if (context == null || !context.mounted) return;

    _hasPromptedOptionalDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        OptionalUpdateDialog.show(
          context,
          currentVersion: result.currentVersion,
          config: result.config!,
        );
      }
    });
  }

  /// Clears cache for manual retry.
  static void clearCache() {
    _cachedResult = null;
    _lastFetchTime = null;
  }
}
