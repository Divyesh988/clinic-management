import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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
      return AppVersion.parse(info.version, build);
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
      // 1. If exact version strings match or installed build >= remote build, app is UP TO DATE.
      final bool isExactStringMatch = config.latestVersion.rawVersion.isNotEmpty &&
          currentVersion.rawVersion.isNotEmpty &&
          config.latestVersion.rawVersion.trim() == currentVersion.rawVersion.trim();

      final bool isUpdateAvailable;
      if (isExactStringMatch) {
        isUpdateAvailable = false;
      } else if (config.latestVersion.buildNumber > 0 && currentVersion.buildNumber > 0) {
        // Android versionCode is the authoritative upgrade metric
        isUpdateAvailable = config.latestVersion.buildNumber > currentVersion.buildNumber;
      } else {
        // Fall back to SemVer comparison
        isUpdateAvailable = currentVersion < config.latestVersion;
      }

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
      await _loadLocalPrefs();
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

  /// Guard to prevent duplicate stacked dialogs.
  static bool _isDialogOpen = false;
  static bool get isDialogOpen => _isDialogOpen;
  static void setDialogOpen(bool open) => _isDialogOpen = open;

  // Local storage for snooze and install tracking
  static const String _prefsFileName = 'cliniqcare_update_prefs.json';
  static Map<String, dynamic>? _localPrefsCache;

  static Future<File?> _getPrefsFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_prefsFileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _loadLocalPrefs() async {
    if (_localPrefsCache != null) return;
    try {
      final file = await _getPrefsFile();
      if (file != null && await file.exists()) {
        final text = await file.readAsString();
        _localPrefsCache = jsonDecode(text) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to load local update prefs: $e');
    }
    _localPrefsCache ??= {};
  }

  static Future<void> _saveLocalPrefs() async {
    try {
      final file = await _getPrefsFile();
      if (file != null && _localPrefsCache != null) {
        await file.writeAsString(jsonEncode(_localPrefsCache));
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to save local update prefs: $e');
    }
  }

  /// Snoozes the current update for 24 hours when the user clicks 'Later'.
  static Future<void> dismissUpdate(String version, int buildNumber) async {
    await _loadLocalPrefs();
    _localPrefsCache!['dismissedVersion'] = version;
    _localPrefsCache!['dismissedBuild'] = buildNumber;
    _localPrefsCache!['dismissedTimestamp'] = DateTime.now().millisecondsSinceEpoch;
    await _saveLocalPrefs();
    _hasPromptedOptionalDialog = true;
  }

  /// Checks if the user dismissed this version within the last 24 hours.
  static bool isUpdateDismissed(String version, int buildNumber) {
    if (_localPrefsCache == null) return false;
    final dismissedVer = _localPrefsCache!['dismissedVersion'] as String?;
    final dismissedBuild = _localPrefsCache!['dismissedBuild'] as int?;
    final timestamp = _localPrefsCache!['dismissedTimestamp'] as int?;

    if (dismissedVer == version && dismissedBuild == buildNumber && timestamp != null) {
      final dismissedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(dismissedTime).inHours < 24) {
        return true;
      }
    }
    return false;
  }

  /// Marks that installation was initiated for a given version.
  static Future<void> markInstallInitiated(String version, int buildNumber) async {
    await _loadLocalPrefs();
    _localPrefsCache!['installedVersion'] = version;
    _localPrefsCache!['installedBuild'] = buildNumber;
    _localPrefsCache!['installedTimestamp'] = DateTime.now().millisecondsSinceEpoch;
    await _saveLocalPrefs();
    _hasPromptedOptionalDialog = true;
  }

  /// Checks if installation was initiated recently (within 1 hour).
  static bool isInstallPending(String version, int buildNumber) {
    if (_localPrefsCache == null) return false;
    final installedVer = _localPrefsCache!['installedVersion'] as String?;
    final installedBuild = _localPrefsCache!['installedBuild'] as int?;
    final timestamp = _localPrefsCache!['installedTimestamp'] as int?;

    if (installedVer == version && installedBuild == buildNumber && timestamp != null) {
      final installTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(installTime).inHours < 1) {
        return true;
      }
    }
    return false;
  }

  /// Resets the prompted state for manual checks (e.g. from Profile or Settings).
  static void resetPromptedState() {
    _hasPromptedOptionalDialog = false;
  }

  /// Presents the optional update dialog if an update is available, not snoozed,
  /// and not already displaying on screen.
  static void showOptionalDialogIfAvailable(BuildContext? context) {
    if (_hasPromptedOptionalDialog || _isDialogOpen) return;
    final result = updateResultNotifier.value;
    if (result == null ||
        result.status != AppUpdateStatus.optionalUpdateAvailable ||
        result.config == null) {
      return;
    }

    if (context == null || !context.mounted) return;

    final versionKey = result.config!.latestVersion.toString();
    final buildNumber = result.config!.latestVersion.buildNumber;

    // Check if snoozed by user in last 24h
    if (isUpdateDismissed(versionKey, buildNumber)) {
      debugPrint('[AppUpdateService] Update $versionKey is snoozed');
      return;
    }

    // Check if user already launched installer within last hour
    if (isInstallPending(versionKey, buildNumber)) {
      debugPrint('[AppUpdateService] Installation was recently initiated for $versionKey');
      return;
    }

    _hasPromptedOptionalDialog = true;
    _isDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        OptionalUpdateDialog.show(
          context,
          currentVersion: result.currentVersion,
          config: result.config!,
        ).whenComplete(() {
          _isDialogOpen = false;
        });
      } else {
        _isDialogOpen = false;
      }
    });
  }

  /// Clears cache for manual retry.
  static void clearCache() {
    _cachedResult = null;
    _lastFetchTime = null;
  }
}
