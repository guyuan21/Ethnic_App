import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LegacyTtsCleanupService {
  LegacyTtsCleanupService._();

  static Future<void> removeCopiedOfflineModel() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final legacyDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}offline_tts',
      );
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }
    } catch (_) {
      // Cleanup is best-effort and must never block app startup.
    }
  }
}
