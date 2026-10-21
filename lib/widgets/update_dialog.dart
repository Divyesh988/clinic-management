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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download failed: $e. You can download manually from GitHub.';
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row with App Logo and Badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Update Available',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.mintBadgeBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'v${widget.config.latestVersion.displayString}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Text(
                              'Current: v${widget.currentVersion.displayString}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // What's New Section
              const Text(
                "What's New in CliniqCare:",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.5)),
                ),
                child: widget.config.releaseNotes.isEmpty
                    ? const Text(
                        'Bug fixes, clinical workflow optimizations, and security improvements.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                      )
                    : Scrollbar(
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

              // Progress Bar if Downloading
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  backgroundColor: AppColors.surfaceVariant,
                  color: AppColors.primary,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],

              // Status Message
              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _statusMessage!.contains('failed') ? AppColors.error : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 22),

              // Action Buttons
              Row(
                children: [
                  TextButton(
                    onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Later', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  if (widget.config.releasePageUrl.isNotEmpty)
                    IconButton(
                      tooltip: 'View Release on GitHub',
                      onPressed: _openReleasePage,
                      icon: const Icon(Icons.open_in_browser_rounded, size: 20, color: AppColors.primary),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _downloadedFile != null ? 'Install Now' : 'Update Now',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
