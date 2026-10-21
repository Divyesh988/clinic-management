import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Service managing Shorebird Code Push Dart-only over-the-air (OTA) patches.
class ShorebirdUpdateService {
  static final ShorebirdUpdater _updater = ShorebirdUpdater();

  /// Whether Shorebird Code Push is supported and available in the current runtime.
  static bool get isAvailable => _updater.isAvailable;

  /// Checks if a compatible OTA patch is available for the current baseline release.
  static Future<bool> checkForPatch() async {
    if (!isAvailable) {
      debugPrint('[ShorebirdUpdateService] Shorebird is not available in this build.');
      return false;
    }

    try {
      final status = await _updater.checkForUpdate();
      return status == UpdateStatus.outdated;
    } catch (e) {
      debugPrint('[ShorebirdUpdateService] Failed to check for patch: $e');
      return false;
    }
  }

  /// Downloads the available OTA patch in the background.
  /// After downloading, the patch takes effect upon next app restart.
  static Future<bool> downloadPatch() async {
    if (!isAvailable) return false;

    try {
      await _updater.update();
      debugPrint('[ShorebirdUpdateService] Patch downloaded successfully. Will activate on restart.');
      return true;
    } on UpdateException catch (e) {
      debugPrint('[ShorebirdUpdateService] Shorebird update exception: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[ShorebirdUpdateService] Unexpected error downloading patch: $e');
      return false;
    }
  }

  /// Retrieves the currently active patch number, or null if running base release.
  static Future<int?> getCurrentPatchNumber() async {
    if (!isAvailable) return null;
    try {
      final patch = await _updater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('[ShorebirdUpdateService] Error reading current patch: $e');
      return null;
    }
  }
}
