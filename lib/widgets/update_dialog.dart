import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_update_config.dart';
import '../models/app_version.dart';
import '../services/apk_update_service.dart';
import '../theme/app_colors.dart';
import 'app_logo.dart';

/// Modal dialog presented when an optional update is available.
class OptionalUpdateDialog extends StatefulWidget {
  final AppVersion currentVersion;
  final AppUpdateConfig config;

  const OptionalUpdateDialog({
    super.key,
    required this.currentVersion,
    required this.config,
  });

  /// Static helper to display the dialog safely.
  static Future<void> show(
    BuildContext context, {
    required AppVersion currentVersion,
    required AppUpdateConfig config,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OptionalUpdateDialog(
        currentVersion: currentVersion,
        config: config,
      ),
    );
  }

  @override
  State<OptionalUpdateDialog> createState() => _OptionalUpdateDialogState();
}

class _OptionalUpdateDialogState extends State<OptionalUpdateDialog> {
  bool _isDownloading = false;
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
      _statusMessage = 'Connecting to release server...';
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
        _statusMessage = 'Download complete! Launching package installer...';
      });

      await ApkUpdateService.installApk(file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download failed: $e. You can also view and download directly from GitHub.';
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

  @override
  Widget build(BuildContext context) {
    final latestVerStr = widget.config.latestVersion.rawVersion.isNotEmpty
        ? widget.config.latestVersion.rawVersion
        : '${widget.config.latestVersion.major}.${widget.config.latestVersion.minor}.${widget.config.latestVersion.patch}';
    final currentVerStr = widget.currentVersion.rawVersion.isNotEmpty
        ? widget.currentVersion.rawVersion
        : '${widget.currentVersion.major}.${widget.currentVersion.minor}.${widget.currentVersion.patch}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      elevation: 16,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row with Logo, Titles, and Close Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.6)),
                      ),
                      child: const AppLogo(size: 46),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'New Version Available',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              // Target New Version Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.mintBadgeBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.primaryBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'v$latestVerStr',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    if (widget.config.latestVersion.buildNumber > 0) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '(build ${widget.config.latestVersion.buildNumber})',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Installed Version Text
                              Text(
                                'Installed: v$currentVerStr',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!_isDownloading)
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Dismiss',
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // "What's New" Section
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    const Text(
                      "What's New in this update",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.6)),
                  ),
                  child: widget.config.releaseNotes.isEmpty
                      ? const Text(
                          'Performance improvements, clinical billing enhancements, and security fixes.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                        )
                      : Scrollbar(
                          thumbVisibility: widget.config.releaseNotes.length > 3,
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
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.35),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                ),

                // Download Progress Indicator
                if (_isDownloading) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      backgroundColor: AppColors.primaryBorder.withValues(alpha: 0.4),
                      color: AppColors.primary,
                      minHeight: 8,
                    ),
                  ),
                ],

                // Status Message Banner
                if (_statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _statusMessage!.contains('failed')
                          ? AppColors.errorLight
                          : AppColors.mintBadgeBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _statusMessage!.contains('failed')
                            ? AppColors.error
                            : AppColors.primaryBorder,
                      ),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _statusMessage!.contains('failed')
                            ? AppColors.error
                            : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action Buttons Row
                Row(
                  children: [
                    TextButton(
                      onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      ),
                      child: const Text('Later', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                    if (widget.config.releasePageUrl.isNotEmpty)
                      IconButton(
                        tooltip: 'View on GitHub',
                        onPressed: _openReleasePage,
                        icon: const Icon(Icons.open_in_browser_rounded, size: 22, color: AppColors.primary),
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isDownloading
                          ? null
                          : (_downloadedFile != null
                              ? () => ApkUpdateService.installApk(_downloadedFile!)
                              : _startDownloadAndInstall),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: _isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _downloadedFile != null
                                      ? Icons.install_mobile_rounded
                                      : Icons.download_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _downloadedFile != null ? 'Install Now' : 'Update Now',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
