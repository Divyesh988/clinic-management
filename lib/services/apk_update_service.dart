import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_update_config.dart';

/// Progress callback receiving downloaded bytes and total bytes (or -1 if unknown).
typedef DownloadProgressCallback = void Function(int receivedBytes, int totalBytes);

/// Service responsible for securely downloading and initiating installation of CliniqCare APKs.
class ApkUpdateService {
  static const int minPlausibleApkBytes = 5 * 1024 * 1024; // 5 MB minimum threshold

  /// Opens the GitHub Release Page in the external system browser.
  static Future<bool> openReleasePage(String url) async {
    if (!AppUpdateConfig.isSafeUrl(url)) {
      debugPrint('[ApkUpdateService] Blocked unsafe release page URL: $url');
      return false;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Downloads the APK from [downloadUrl] to the app's cache directory,
  /// streaming download progress to [onProgress].
  /// Returns the downloaded File upon successful completion.
  static Future<File> downloadApk({
    required String downloadUrl,
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!AppUpdateConfig.isSafeUrl(downloadUrl)) {
      throw const FormatException('Unsafe or unauthorized download URL');
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed with HTTP status code ${response.statusCode}',
          uri: Uri.parse(downloadUrl),
        );
      }

      final contentLength = response.contentLength ?? -1;

      final cacheDir = await getTemporaryDirectory();
      final targetFile = File('${cacheDir.path}/cliniqcare_update.apk');

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      final sink = targetFile.openWrite();
      int receivedBytes = 0;

      await response.stream.listen((chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        if (onProgress != null) {
          onProgress(receivedBytes, contentLength);
        }
      }).asFuture().timeout(timeout);

      await sink.flush();
      await sink.close();

      // Verify file integrity
      if (!await targetFile.exists()) {
        throw const FileSystemException('Downloaded APK file does not exist on disk');
      }

      final fileSize = await targetFile.length();
      if (fileSize < minPlausibleApkBytes) {
        await targetFile.delete();
        throw FileSystemException(
          'Downloaded APK size ($fileSize bytes) is below minimum plausible threshold',
        );
      }

      return targetFile;
    } finally {
      client.close();
    }
  }

  /// Initiates the Android package installer for the specified [apkFile].
  static Future<OpenResult> installApk(File apkFile) async {
    if (!await apkFile.exists()) {
      throw const FileSystemException('Cannot install non-existent APK file');
    }

    if (!apkFile.path.toLowerCase().endsWith('.apk')) {
      throw const FormatException('Invalid file type: expected .apk file');
    }

    debugPrint('[ApkUpdateService] Launching package installer for: ${apkFile.path}');

    final result = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );

    debugPrint('[ApkUpdateService] OpenFilex result: ${result.type} - ${result.message}');
    return result;
  }
}
