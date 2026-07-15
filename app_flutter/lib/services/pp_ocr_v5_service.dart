import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PpOcrV5Service {
  static const MethodChannel _channel =
      MethodChannel('ethnic_culture_app/pp_ocr_v5');

  static Future<String?> recognizeTitle(String imagePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'recognizeTitle',
        {'imagePath': imagePath},
      );
      final text = response?['text']?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
