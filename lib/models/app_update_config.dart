import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_version.dart';

/// Configuration model representing update metadata stored in Firestore at
/// `app_config/updates_android_production`.
class AppUpdateConfig {
  final String platform;
  final String environment;
  final bool enabled;
  final AppVersion latestVersion;
  final AppVersion minimumSupportedVersion;
  final List<String> releaseNotes;
  final String apkDownloadUrl;
  final String releasePageUrl;
  final bool forceUpdate;
  final DateTime? publishedAt;
  final DateTime? updatedAt;

  const AppUpdateConfig({
    required this.platform,
    required this.environment,
    required this.enabled,
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.releasePageUrl,
    required this.forceUpdate,
    this.publishedAt,
    this.updatedAt,
  });

  /// Factory constructor to parse and validate Firestore document snapshot or map.
  factory AppUpdateConfig.fromMap(Map<String, dynamic> data) {
    final platform = (data['platform'] as String?)?.toLowerCase().trim() ?? 'android';
    final environment = (data['environment'] as String?)?.toLowerCase().trim() ?? 'production';
    final enabled = data['enabled'] == true;

    final latestVersionStr = data['latestVersion'] as String? ?? '1.0.0';
    final latestBuild = data['latestBuildNumber'] is int
        ? data['latestBuildNumber'] as int
        : int.tryParse(data['latestBuildNumber']?.toString() ?? '0') ?? 0;
    final latestVersion = AppVersion.parse(latestVersionStr, latestBuild);

    final minVersionStr = data['minimumSupportedVersion'] as String? ?? '1.0.0';
    final minBuild = data['minimumSupportedBuildNumber'] is int
        ? data['minimumSupportedBuildNumber'] as int
        : int.tryParse(data['minimumSupportedBuildNumber']?.toString() ?? '0') ?? 0;
    final minimumSupportedVersion = AppVersion.parse(minVersionStr, minBuild);

    final rawNotes = data['releaseNotes'];
    final List<String> notes = [];
    if (rawNotes is List) {
      for (final item in rawNotes) {
        if (item != null && item.toString().trim().isNotEmpty) {
          notes.add(item.toString().trim());
        }
      }
    } else if (rawNotes is String && rawNotes.trim().isNotEmpty) {
      notes.add(rawNotes.trim());
    }

    final apkDownloadUrl = (data['apkDownloadUrl'] as String?)?.trim() ?? '';
    final releasePageUrl = (data['releasePageUrl'] as String?)?.trim() ?? '';
    final forceUpdate = data['forceUpdate'] == true;

    DateTime? publishedAt;
    if (data['publishedAt'] is Timestamp) {
      publishedAt = (data['publishedAt'] as Timestamp).toDate();
    } else if (data['publishedAt'] is String) {
      publishedAt = DateTime.tryParse(data['publishedAt']);
    }

    DateTime? updatedAt;
    if (data['updatedAt'] is Timestamp) {
      updatedAt = (data['updatedAt'] as Timestamp).toDate();
    } else if (data['updatedAt'] is String) {
      updatedAt = DateTime.tryParse(data['updatedAt']);
    }

    return AppUpdateConfig(
      platform: platform,
      environment: environment,
      enabled: enabled,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
      releaseNotes: notes,
      apkDownloadUrl: apkDownloadUrl,
      releasePageUrl: releasePageUrl,
      forceUpdate: forceUpdate,
      publishedAt: publishedAt,
      updatedAt: updatedAt,
    );
  }

  /// Converts model back to map for administration publishing tools or tests.
  Map<String, dynamic> toMap() {
    return {
      'platform': platform,
      'environment': environment,
      'enabled': enabled,
      'latestVersion': '${latestVersion.major}.${latestVersion.minor}.${latestVersion.patch}',
      'latestBuildNumber': latestVersion.buildNumber,
      'minimumSupportedVersion':
          '${minimumSupportedVersion.major}.${minimumSupportedVersion.minor}.${minimumSupportedVersion.patch}',
      'minimumSupportedBuildNumber': minimumSupportedVersion.buildNumber,
      'releaseNotes': releaseNotes,
      'apkDownloadUrl': apkDownloadUrl,
      'releasePageUrl': releasePageUrl,
      'forceUpdate': forceUpdate,
      'publishedAt': publishedAt != null ? Timestamp.fromDate(publishedAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Validates URL safety against allowed domains and the official repository.
  /// Protects against open-redirect or malicious phishing links from compromised metadata.
  static bool isSafeUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    // Allow GitHub official release pages and assets
    if (host == 'github.com' || host == 'objects.githubusercontent.com') {
      // Must target the official repository
      if (uri.path.contains('Divyesh988/clinic-management')) {
        return true;
      }
    }
    return false;
  }

  /// Verifies that the configuration has all mandatory fields and valid URLs when enabled.
  bool get isValid {
    if (!enabled) return true; // Disabled updates are safe to ignore
    if (apkDownloadUrl.isEmpty && releasePageUrl.isEmpty) return false;
    if (apkDownloadUrl.isNotEmpty && !isSafeUrl(apkDownloadUrl)) return false;
    if (releasePageUrl.isNotEmpty && !isSafeUrl(releasePageUrl)) return false;
    return true;
  }
}
