import 'package:clinic_mangement/models/app_update_config.dart';
import 'package:clinic_mangement/models/app_version.dart';
import 'package:clinic_mangement/services/app_update_service.dart';
import 'package:clinic_mangement/widgets/mandatory_update_screen.dart';
import 'package:clinic_mangement/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion Model & Semantic Comparison Tests', () {
    test('Correctly parses basic semantic version and build number', () {
      final v1 = AppVersion.parse('1.0.0', 1);
      expect(v1.major, 1);
      expect(v1.minor, 0);
      expect(v1.patch, 0);
      expect(v1.buildNumber, 1);
      expect(v1.displayString, '1.0.0 (build 1)');

      final v2 = AppVersion.parse('v2.4.12+55');
      expect(v2.major, 2);
      expect(v2.minor, 4);
      expect(v2.patch, 12);
      expect(v2.buildNumber, 55);
    });

    test('Same installed and published versions evaluate to equal', () {
      final installed = AppVersion.parse('1.0.0', 1);
      final published = AppVersion.parse('1.0.0', 1);
      expect(installed == published, isTrue);
      expect(installed >= published, isTrue);
      expect(installed <= published, isTrue);
    });

    test('Newer published version detected correctly', () {
      final installed = AppVersion.parse('1.0.0', 1);
      final published = AppVersion.parse('1.1.0', 2);
      expect(installed < published, isTrue);
      expect(published > installed, isTrue);
    });

    test('Same semantic version with higher build number triggers update', () {
      final installed = AppVersion.parse('1.0.0', 1);
      final published = AppVersion.parse('1.0.0', 2);
      expect(installed < published, isTrue);
      expect(published > installed, isTrue);
    });

    test('Installed version newer than published version never suggests downgrade', () {
      final installed = AppVersion.parse('1.2.0', 5);
      final published = AppVersion.parse('1.1.0', 2);
      expect(installed > published, isTrue);
      expect(installed < published, isFalse);
    });

    test('Handles malformed or partial version strings safely with fallbacks', () {
      final v = AppVersion.parse('invalid-version');
      expect(v.major, 0);
      expect(v.minor, 0);
      expect(v.patch, 0);
      expect(v.buildNumber, 0);
    });
  });

  group('AppUpdateConfig & Security Validation Tests', () {
    test('Parses complete Firestore map correctly', () {
      final map = {
        'platform': 'android',
        'environment': 'production',
        'enabled': true,
        'latestVersion': '1.1.0',
        'latestBuildNumber': 2,
        'minimumSupportedVersion': '1.0.0',
        'minimumSupportedBuildNumber': 1,
        'releaseNotes': ['Critical security patch', 'Performance improvements'],
        'apkDownloadUrl':
            'https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk',
        'releasePageUrl':
            'https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0',
        'forceUpdate': false,
      };

      final config = AppUpdateConfig.fromMap(map);
      expect(config.platform, 'android');
      expect(config.environment, 'production');
      expect(config.enabled, isTrue);
      expect(config.latestVersion, AppVersion.parse('1.1.0', 2));
      expect(config.minimumSupportedVersion, AppVersion.parse('1.0.0', 1));
      expect(config.releaseNotes.length, 2);
      expect(config.isValid, isTrue);
    });

    test('URL allowlist accepts official GitHub repository releases only', () {
      expect(
        AppUpdateConfig.isSafeUrl(
          'https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk',
        ),
        isTrue,
      );
      expect(
        AppUpdateConfig.isSafeUrl(
          'https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0',
        ),
        isTrue,
      );

      // Insecure HTTP
      expect(
        AppUpdateConfig.isSafeUrl(
          'http://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk',
        ),
        isFalse,
      );

      // Foreign malicious domain
      expect(
        AppUpdateConfig.isSafeUrl('https://evil-phishing-site.com/cliniqcare.apk'),
        isFalse,
      );

      // Other repository on GitHub
      expect(
        AppUpdateConfig.isSafeUrl('https://github.com/random_user/other_repo/releases/download/v1/app.apk'),
        isFalse,
      );
    });

    test('Invalidates config when enabled with missing or insecure URLs', () {
      final insecureMap = {
        'platform': 'android',
        'environment': 'production',
        'enabled': true,
        'latestVersion': '1.1.0',
        'latestBuildNumber': 2,
        'minimumSupportedVersion': '1.0.0',
        'minimumSupportedBuildNumber': 1,
        'releaseNotes': [],
        'apkDownloadUrl': 'https://insecure-domain.com/bad.apk',
        'releasePageUrl': '',
        'forceUpdate': false,
      };

      final config = AppUpdateConfig.fromMap(insecureMap);
      expect(config.isValid, isFalse);
    });
  });

  group('Update Policy Evaluation Tests', () {
    final validConfig = AppUpdateConfig(
      platform: 'android',
      environment: 'production',
      enabled: true,
      latestVersion: AppVersion.parse('1.1.0', 2),
      minimumSupportedVersion: AppVersion.parse('1.0.0', 1),
      releaseNotes: ['New feature'],
      apkDownloadUrl:
          'https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk',
      releasePageUrl:
          'https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0',
      forceUpdate: false,
    );

    test('Identifies optional update when installed version is supported but older than latest', () {
      final current = AppVersion.parse('1.0.0', 1);
      final isMandatory = current < validConfig.minimumSupportedVersion ||
          (validConfig.forceUpdate && current < validConfig.latestVersion);
      final isOptional = !isMandatory && current < validConfig.latestVersion;

      expect(isMandatory, isFalse);
      expect(isOptional, isTrue);
    });

    test('Identifies mandatory update when installed version is below minimumSupportedVersion', () {
      final strictConfig = AppUpdateConfig(
        platform: 'android',
        environment: 'production',
        enabled: true,
        latestVersion: AppVersion.parse('2.0.0', 10),
        minimumSupportedVersion: AppVersion.parse('1.5.0', 5),
        releaseNotes: ['Breaking migration'],
        apkDownloadUrl:
            'https://github.com/Divyesh988/clinic-management/releases/download/v2.0.0/app-release.apk',
        releasePageUrl:
            'https://github.com/Divyesh988/clinic-management/releases/tag/v2.0.0',
        forceUpdate: false,
      );

      final current = AppVersion.parse('1.0.0', 1);
      final isMandatory = current < strictConfig.minimumSupportedVersion;

      expect(isMandatory, isTrue);
    });

    test('Identifies mandatory update when forceUpdate flag is true', () {
      final forceConfig = AppUpdateConfig(
        platform: 'android',
        environment: 'production',
        enabled: true,
        latestVersion: AppVersion.parse('1.1.0', 2),
        minimumSupportedVersion: AppVersion.parse('1.0.0', 1),
        releaseNotes: ['Urgent patch'],
        apkDownloadUrl:
            'https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk',
        releasePageUrl:
            'https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0',
        forceUpdate: true,
      );

      final current = AppVersion.parse('1.0.0', 1);
      final isMandatory = current < forceConfig.minimumSupportedVersion ||
          (forceConfig.forceUpdate && current < forceConfig.latestVersion);

      expect(isMandatory, isTrue);
    });

    test('AppUpdateCheckResult exposes hasUpdate and isMandatory helpers', () {
      const result = AppUpdateCheckResult(
        status: AppUpdateStatus.mandatoryUpdateRequired,
        currentVersion: AppVersion(major: 1, minor: 0, patch: 0, buildNumber: 1, rawVersion: '1.0.0+1'),
      );
      expect(result.hasUpdate, isTrue);
      expect(result.isMandatory, isTrue);
    });
  });

  group('Update UI Widget Tests', () {
    testWidgets('OptionalUpdateDialog renders version details and release notes', (tester) async {
      final config = AppUpdateConfig(
        platform: 'android',
        environment: 'production',
        enabled: true,
        latestVersion: AppVersion.parse('1.1.0', 2),
        minimumSupportedVersion: AppVersion.parse('1.0.0', 1),
        releaseNotes: ['Feature A', 'Feature B'],
        apkDownloadUrl:
            'https://github.com/Divyesh988/clinic-management/releases/download/v1.1.0/app-release.apk',
        releasePageUrl:
            'https://github.com/Divyesh988/clinic-management/releases/tag/v1.1.0',
        forceUpdate: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionalUpdateDialog(
              currentVersion: AppVersion.parse('1.0.0', 1),
              config: config,
            ),
          ),
        ),
      );

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Feature A'), findsOneWidget);
      expect(find.text('Feature B'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('MandatoryUpdateScreen renders non-dismissible critical shield', (tester) async {
      final config = AppUpdateConfig(
        platform: 'android',
        environment: 'production',
        enabled: true,
        latestVersion: AppVersion.parse('2.0.0', 10),
        minimumSupportedVersion: AppVersion.parse('1.5.0', 5),
        releaseNotes: ['Important database migration'],
        apkDownloadUrl:
            'https://github.com/Divyesh988/clinic-management/releases/download/v2.0.0/app-release.apk',
        releasePageUrl:
            'https://github.com/Divyesh988/clinic-management/releases/tag/v2.0.0',
        forceUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MandatoryUpdateScreen(
            currentVersion: AppVersion.parse('1.0.0', 1),
            config: config,
          ),
        ),
      );

      expect(find.text('UPDATE REQUIRED'), findsOneWidget);
      expect(find.text('Application Update Required'), findsOneWidget);
      expect(find.text('Important database migration'), findsOneWidget);
      expect(find.text('Download & Install Update'), findsOneWidget);
      expect(find.text('Download via Browser'), findsOneWidget);
    });
  });
}
