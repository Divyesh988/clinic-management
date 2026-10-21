import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_update_config.dart';
import '../models/app_version.dart';
import '../services/apk_update_service.dart';
import '../services/app_update_service.dart';
import '../theme/app_colors.dart';
import 'app_logo.dart';

/// Full-screen blocking UI presented when an installed build is below the
/// configured minimum supported version or when an update is marked mandatory.
class MandatoryUpdateScreen extends StatefulWidget {
  final AppVersion currentVersion;
  final AppUpdateConfig config;

  const MandatoryUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.config,
  });

  @override
  State<MandatoryUpdateScreen> createState() => _MandatoryUpdateScreenState();
}

class _MandatoryUpdateScreenState extends State<MandatoryUpdateScreen> {
  bool _isDownloading = false;
  bool _isRetrying = false;
  double _downloadProgress = 0.0;
  String? _statusMessage;
  File? _downloadedFile;

  Future<void> _startDownloadAndInstall() async {
    if (widget.config.apkDownloadUrl.isEmpty) {
      _openReleasePage();
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Connecting to download server...';
    });

    try {
      final file = await ApkUpdateService.downloadApk(
        downloadUrl: widget.config.apkDownloadUrl,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            if (total > 0) {
              _downloadProgress = (received / total).clamp(0.0, 1.0);
              final percent = (_downloadProgress * 100).toInt();
              final mbReceived = (received / (1024 * 1024)).toStringAsFixed(1);
              final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
              _statusMessage = 'Downloading: $mbReceived MB / $mbTotal MB ($percent%)';
            } else {
              final mbReceived = (received / (1024 * 1024)).toStringAsFixed(1);
              _statusMessage = 'Downloading: $mbReceived MB';
            }
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadedFile = file;
        _statusMessage = 'Download complete. Launching package installer...';
      });

      await ApkUpdateService.installApk(file);
      AppUpdateService.clearCache();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _statusMessage = 'In-app download failed: $e. Please tap "Download via Browser".';
      });
    }
  }

  void _openReleasePage() {
    final url = widget.config.releasePageUrl.isNotEmpty
        ? widget.config.releasePageUrl
        : widget.config.apkDownloadUrl;
    if (url.isNotEmpty) {
      ApkUpdateService.openReleasePage(url);
    }
  }

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      final result = await AppUpdateService.checkForUpdates(forceRefresh: true);
      if (!mounted) return;
      if (!result.isMandatory) {
        // App has been updated or requirement relaxed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App version validated! Resuming...')),
        );
      } else {
        setState(() {
          _statusMessage = 'Update is still required to access CliniqCare.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.primaryBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Brand Logo & Critical Alert Badge
                      const AppLogo(size: 64),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.system_update_rounded, size: 14, color: AppColors.error),
                            SizedBox(width: 6),
                            Text(
                              'UPDATE REQUIRED',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.errorText,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      const Text(
                        'Application Update Required',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),

                      Text(
                        'A mandatory update is required to continue using CliniqCare. This release includes vital clinical security patches and database schema updates.',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Version Details Box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  const Text('Installed Version', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  const SizedBox(height: 3),
                                  Text(
                                    'v${widget.currentVersion.displayString}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.errorText),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 30, color: const Color(0xFFCBD5E1)),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text('Required Version', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  const SizedBox(height: 3),
                                  Text(
                                    'v${widget.config.minimumSupportedVersion.displayString}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Release Notes Section
                      if (widget.config.releaseNotes.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "What's in this version:",
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 140),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Scrollbar(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: widget.config.releaseNotes.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                    Expanded(
                                      child: Text(
                                        widget.config.releaseNotes[index],
                                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.35),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Download Progress Bar
                      if (_isDownloading) ...[
                        LinearProgressIndicator(
                          value: _downloadProgress > 0 ? _downloadProgress : null,
                          backgroundColor: AppColors.surfaceVariant,
                          color: AppColors.primary,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Status message
                      if (_statusMessage != null) ...[
                        Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _statusMessage!.contains('failed') ? AppColors.error : AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Primary Action: Download and Install
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isDownloading
                              ? null
                              : (_downloadedFile != null
                                  ? () => ApkUpdateService.installApk(_downloadedFile!)
                                  : _startDownloadAndInstall),
                          icon: _isDownloading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_rounded, size: 20),
                          label: Text(
                            _downloadedFile != null ? 'Install Update Now' : 'Download & Install Update',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Secondary Actions: Browser Fallback & Retry Check
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isDownloading ? null : _openReleasePage,
                              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                              label: const Text('Download via Browser', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.outlined(
                            tooltip: 'Retry Version Check',
                            onPressed: _isRetrying || _isDownloading ? null : _handleRetry,
                            icon: _isRetrying
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
