import 'model_config_service.dart';
import 'tencent_tts_service.dart';

/// Tencent Cloud TTS used as the preferred Android reader. The chat page
/// falls back to the device system TTS when this service is unavailable.
class OnlineTtsService {
  OnlineTtsService._();

  static final OnlineTtsService instance = OnlineTtsService._();

  Future<bool> isConfigured() async {
    final config = await ModelConfigService.load();
    return config.tencentSecretId.trim().isNotEmpty &&
        config.tencentSecretKey.trim().isNotEmpty;
  }

  Future<void> speak(String text) async {
    final speechText = _normalizeSpeechText(text);
    if (speechText.isEmpty) throw Exception('没有可朗读的文字。');

    final config = await ModelConfigService.load();
    await TencentTtsService.instance.speak(speechText, config);
  }

  Future<void> stop() => TencentTtsService.instance.stop();

  Future<void> dispose() => stop();

  String _normalizeSpeechText(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[`*_#>\[\]()]'), '')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= 520) return normalized;
    return '${normalized.substring(0, 520)}。后续内容可以继续查看文字回答。';
  }
}
