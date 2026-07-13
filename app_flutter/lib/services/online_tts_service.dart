import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'model_config_service.dart';

class OnlineTtsService {
  OnlineTtsService._();

  static final OnlineTtsService instance = OnlineTtsService._();

  final AudioPlayer _player = AudioPlayer();

  Future<void> speak(String text) async {
    final speechText = _normalizeSpeechText(text);
    if (speechText.isEmpty) throw Exception('没有可朗读的文字。');

    final config = await ModelConfigService.load();
    final apiKey = config.keyFor(config.qwenTtsApiKey);
    if (apiKey.isEmpty) {
      throw Exception('缺少联网朗读接口密钥。');
    }

    final uri = Uri.tryParse(config.qwenTtsUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw Exception('联网朗读接口地址无效。');
    }

    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': config.qwenTtsModel,
            'input': {
              'text': speechText,
              'voice': config.qwenTtsVoice,
              'language_type': 'Chinese',
            },
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('联网朗读调用失败（${response.statusCode}）：${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map) throw Exception('联网朗读返回格式不正确。');
    final output = data['output'];
    final audio = output is Map ? output['audio'] : null;
    final rawUrl = audio is Map ? (audio['url'] ?? '').toString().trim() : '';
    if (rawUrl.isEmpty) throw Exception('联网朗读没有返回音频地址。');

    // DashScope may return an HTTP OSS URL. Upgrade it because Android release
    // builds commonly reject clear-text traffic.
    final parsedAudioUrl = Uri.tryParse(rawUrl);
    final audioUrl = parsedAudioUrl?.scheme == 'http'
        ? parsedAudioUrl!.replace(scheme: 'https').toString()
        : rawUrl;

    await stop();
    await _player.play(UrlSource(audioUrl));
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // A stop before native player initialization is harmless.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }

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
