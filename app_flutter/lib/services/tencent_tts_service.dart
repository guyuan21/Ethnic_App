import 'dart:io';

import 'package:flutter/services.dart';

import 'model_config_service.dart';

class TencentTtsService {
  TencentTtsService._();

  static final TencentTtsService instance = TencentTtsService._();
  static const MethodChannel _channel = MethodChannel(
    'ethnic_culture_app/tencent_tts',
  );

  Future<void> speak(String text, ModelRuntimeConfig config) async {
    if (!Platform.isAndroid) {
      throw Exception('腾讯云原生 TTS 当前仅支持 Android。');
    }
    final secretId = config.tencentSecretId.trim();
    final secretKey = config.tencentSecretKey.trim();
    if (secretId.isEmpty || secretKey.isEmpty) {
      throw Exception('请先在配置页填写腾讯云 SecretId 和 SecretKey。');
    }

    final chunks = splitTextForBasicTts(text);
    if (chunks.isEmpty) throw Exception('没有可朗读的文字。');

    await _channel.invokeMethod<void>('speak', {
      'texts': chunks,
      'appId': int.tryParse(config.tencentAppId.trim()) ?? 0,
      'secretId': secretId,
      'secretKey': secretKey,
      'token': config.tencentToken.trim(),
      'voiceType': int.tryParse(config.tencentVoiceType.trim()) ?? 1001,
      'speed': 0,
      'volume': 0,
      'region': '',
    }).timeout(const Duration(seconds: 40));
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Stopping before the native SDK is initialized is harmless.
    }
  }

  /// Tencent basic online TTS accepts at most 150 Chinese characters per
  /// request. Keep a safety margin and split on sentence punctuation first.
  static List<String> splitTextForBasicTts(
    String text, {
    int maxCharacters = 140,
  }) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) chunks.add(value);
      buffer.clear();
    }

    for (final rune in normalized.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(character);
      final reachedLimit = buffer.length >= maxCharacters;
      final sentenceEnd = '。！？；!?;'.contains(character);
      if (reachedLimit || sentenceEnd) flush();
    }
    flush();

    return chunks;
  }
}
