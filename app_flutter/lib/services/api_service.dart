import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cartoon_classifier_service.dart';
import 'model_config_service.dart';
import 'offline_asr_service.dart';

class ApiService {
  static const double _minCartoonConfidence = 0.70;
  static const String _notice = '本结果仅识别民族服饰卡通图片，不代表对真人民族身份的判断。';

  static Map<String, Map<String, dynamic>>? _cultureInfoCache;
  static List<Map<String, dynamic>>? _costumeReferenceCache;

  static Future<void> prewarmLocalCostumeMatcher() =>
      CartoonClassifierService.instance.load();

  static Future<void> prewarmOfflineAsr() => OfflineAsrService.prewarm();

  static String resolveUrl(String pathOrUrl) {
    return pathOrUrl;
  }

  static Future<Map<String, dynamic>> recognizeImage(XFile imageFile) async {
    final cultureInfo = await _cultureInfo();
    final bytes = await imageFile.readAsBytes();
    final ocrMatch = await _tryOcrTitleMatch(imageFile, cultureInfo);

    final predictions = await CartoonClassifierService.instance.classify(bytes);
    final recognized = predictions
        .where((item) => cultureInfo.containsKey(item.label))
        .toList(growable: false);

    final best = recognized.isEmpty ? null : recognized.first;
    if (best == null || best.confidence < _minCartoonConfidence) {
      return _formatResult(
        results: const [],
        warning: '本地服饰模型最高置信度低于70%，暂不展示结果。请保持服饰人物主体清晰、完整并减少反光。',
        predictions: predictions,
        ocrText: ocrMatch?.text,
      );
    }

    return _formatResult(
      results: [
        _toResult(
          best.label,
          best.confidence,
          cultureInfo[best.label]!,
        ),
      ],
      predictions: predictions,
      ocrText: ocrMatch?.text,
    );
  }

  static Future<String> transcribeAudio(String audioPath) async {
    if (kIsWeb) {
      throw Exception('网页端暂不支持离线语音识别，请直接输入文字。');
    }
    return OfflineAsrService.transcribe(audioPath);
  }

  static Future<String> askQuestion(
    String question, {
    Map<String, dynamic>? context,
  }) async {
    final config = await ModelConfigService.load();
    final contextText = _buildContextText(context);
    final lightQuestion = _isLightQuestion(question);
    final detailedQuestion = _isDetailedQuestion(question);
    final answerLimit = lightQuestion
        ? 'Keep it within 40 Chinese characters.'
        : detailedQuestion
            ? 'Keep it within 220 Chinese characters.'
            : 'Keep it within 80 to 140 Chinese characters.';
    final maxTokens = lightQuestion
        ? 64
        : detailedQuestion
            ? 320
            : 180;
    final prompt = '''
You are a warm Chinese museum guide for ethnic culture learning.
Answer in Chinese.
Use the provided recognition context first.
Only answer the user's current question. Do not repeat every field in the context.
Do not infer or judge a person's ethnic identity from face, skin, or appearance.
If the user only greets you, reply briefly and invite them to ask about the recognized cultural element.
If the user asks for a child-friendly answer, make it vivid and easy for children.
$answerLimit

Recognition context:
$contextText

User question:
$question
''';

    final data = await _postQwen(
      apiKey: _apiKey(config.qwenApiKey),
      config: config,
      payload: {
        'model': config.qwenChatModel,
        'messages': [
          {
            'role': 'system',
            'content':
                'You answer in Chinese as a careful cultural explainer. Stay within cultural element learning and safety boundaries.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.72,
        'top_p': 0.9,
        'max_tokens': maxTokens,
      },
      timeout: const Duration(seconds: 60),
    );

    final answer = _extractQwenContent(data).trim();
    if (answer.isEmpty) throw Exception('聊天模型没有返回内容。');
    return answer;
  }

  static Future<Map<String, Map<String, dynamic>>> _cultureInfo() async {
    final cached = _cultureInfoCache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/culture_info.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final normalized = <String, Map<String, dynamic>>{};
    for (final entry in decoded.entries) {
      if (entry.value is Map) {
        normalized[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }
    _cultureInfoCache = normalized;
    return normalized;
  }

  static Future<List<Map<String, dynamic>>> _costumeReference() async {
    final cached = _costumeReferenceCache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/costume_reference.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final refs = decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _costumeReferenceCache = refs;
    return refs;
  }

  static Map<String, dynamic> _formatResult({
    required List<Map<String, dynamic>> results,
    required List<CartoonPrediction> predictions,
    String warning = '',
    String engine = 'local_cartoon_tflite',
    String? ocrText,
  }) {
    final payload = <String, dynamic>{
      'image_size': {'width': 0, 'height': 0},
      'person_detected': null,
      'engine': engine,
      'results': results,
      'notice': _notice,
      'top_predictions': predictions
          .map(
            (item) => {
              'label': item.label,
              'confidence': item.confidence,
            },
          )
          .toList(growable: false),
    };
    if (warning.isNotEmpty) payload['warning'] = warning;
    if (ocrText != null && ocrText.trim().isNotEmpty) {
      payload['ocr_text'] = ocrText.trim();
    }
    return payload;
  }

  static Future<_OcrMatch?> _tryOcrTitleMatch(
    XFile imageFile,
    Map<String, Map<String, dynamic>> cultureInfo,
  ) async {
    if (kIsWeb) return null;

    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imageFile.path),
      );
      final fullText = recognized.text.trim();
      var label = await _matchLabelFromOcrText(fullText, cultureInfo);
      var combinedText = fullText;

      if (label == null) {
        final croppedText = await _recognizeBottomTitle(
          recognizer,
          imageFile,
        );
        if (croppedText.isNotEmpty) {
          combinedText = [fullText, croppedText]
              .where((value) => value.isNotEmpty)
              .toSet()
              .join('\n');
          label = await _matchLabelFromOcrText(croppedText, cultureInfo);
        }
      }
      if (combinedText.isEmpty) return null;

      return _OcrMatch(
        label: label != null && cultureInfo.containsKey(label) ? label : null,
        confidence: label == null ? 0.0 : 0.99,
        text: combinedText,
      );
    } catch (_) {
      return null;
    } finally {
      await recognizer?.close();
    }
  }

  static Future<String> _recognizeBottomTitle(
    TextRecognizer recognizer,
    XFile imageFile,
  ) async {
    File? tempFile;
    try {
      final decoded = img.decodeImage(await imageFile.readAsBytes());
      if (decoded == null || decoded.height < 80) return '';
      final oriented = img.bakeOrientation(decoded);
      final cropTop = (oriented.height * 0.58).round();
      var titleCrop = img.copyCrop(
        oriented,
        x: 0,
        y: cropTop,
        width: oriented.width,
        height: oriented.height - cropTop,
      );
      if (titleCrop.width < 1200) {
        titleCrop = img.copyResize(
          titleCrop,
          width: 1200,
          interpolation: img.Interpolation.cubic,
        );
      }
      // Totem titles are often white characters on black. Inverting the crop
      // gives ML Kit the conventional dark-text-on-light-background layout.
      titleCrop = img.invert(img.grayscale(titleCrop));

      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        p.join(
          tempDir.path,
          'culture_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await tempFile.writeAsBytes(img.encodePng(titleCrop), flush: true);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(tempFile.path),
      );
      return recognized.text.trim();
    } catch (_) {
      return '';
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  static Future<String?> _matchLabelFromOcrText(
    String text,
    Map<String, Map<String, dynamic>> cultureInfo,
  ) async {
    final normalizedText = _normalizeOcrText(text);
    if (normalizedText.isEmpty) return null;

    for (final entry in cultureInfo.entries) {
      final info = entry.value;
      final group = (info['group'] ?? '').toString();
      final name = (info['name'] ?? '').toString();
      for (final alias in <String>[group, name]) {
        final normalizedAlias = _normalizeOcrText(alias);
        if (normalizedAlias.length >= 2 &&
            normalizedText.contains(normalizedAlias)) {
          return entry.key;
        }
      }
    }

    const commonCorrections = <String, String>{
      '仫老族': 'mulaozu',
      '么佬族': 'mulaozu',
      '仫佬旋': 'mulaozu',
      '仫佬旅': 'mulaozu',
      '仫佬旗': 'mulaozu',
    };
    for (final correction in commonCorrections.entries) {
      if (normalizedText.contains(_normalizeOcrText(correction.key)) &&
          cultureInfo.containsKey(correction.value)) {
        return correction.value;
      }
    }

    // Decorative fonts often cause one wrong character. Allow one substituted
    // character only for ethnic names of at least three characters.
    for (final entry in cultureInfo.entries) {
      final group = _normalizeOcrText((entry.value['group'] ?? '').toString());
      if (group.length >= 3 &&
          _containsWithOneSubstitution(normalizedText, group)) {
        return entry.key;
      }
    }

    final refs = await _costumeReference();
    for (final item in refs) {
      final label = (item['label'] ?? '').toString();
      if (!cultureInfo.containsKey(label)) continue;
      final english = (item['english'] ?? '').toString();
      final normalizedEnglish = _normalizeOcrText(english);
      if (normalizedEnglish.length >= 3 &&
          normalizedText.contains(normalizedEnglish)) {
        return label;
      }
    }

    return null;
  }

  static String _normalizeOcrText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-z0-9]'), '');
  }

  static bool _containsWithOneSubstitution(String text, String expected) {
    if (text.length < expected.length) return false;
    for (var start = 0; start <= text.length - expected.length; start += 1) {
      var differences = 0;
      for (var i = 0; i < expected.length; i += 1) {
        if (text.codeUnitAt(start + i) != expected.codeUnitAt(i)) {
          differences += 1;
          if (differences > 1) break;
        }
      }
      if (differences <= 1) return true;
    }
    return false;
  }

  static Map<String, dynamic> _toResult(
    String label,
    double confidence,
    Map<String, dynamic> info,
  ) {
    return {
      'label': label,
      'group': info['group'] ?? '',
      'name': info['group'] ?? info['name'] ?? '',
      'element_name': info['name'] ?? '',
      'photo_url': info['photo_url'] ?? '',
      'costume_asset': 'assets/costumes/$label.jpg',
      'totem_url': info['totem_url'] ?? '',
      'confidence': confidence,
      'type': 'cartoon cultural element',
      'intro': info['intro'] ?? '',
      'features': info['features'] ?? const [],
      'regions': info['regions'] ?? const [],
      'festivals': info['festivals'] ?? const [],
      'history_intro': info['history_intro'] ?? '',
      'region_group': info['region_group'] ?? '',
      'related_groups': info['related_groups'] ?? const [],
      'interaction_events': info['interaction_events'] ?? const [],
      'doc_source': info['doc_source'] ?? '',
    };
  }

  static String _buildContextText(Map<String, dynamic>? context) {
    final results = context?['results'];
    if (results is! List || results.isEmpty) {
      return '当前没有图片识别结果，请按民族文化学习场景进行通用讲解。';
    }

    final lines = <String>[];
    for (final item in results) {
      if (item is! Map) continue;
      final name = (item['name'] ?? item['group'] ?? '未知元素').toString();
      final confidence = item['confidence'];
      final confidenceText = confidence is num
          ? '${(confidence * 100).toStringAsFixed(0)}%'
          : '未知';
      final intro = (item['intro'] ?? '').toString();
      lines.add('- 识别元素：$name，置信度：$confidenceText');
      if (intro.isNotEmpty) lines.add('  简介：${_shorten(intro, 80)}');

      final features = _toStringList(item['features']);
      final regions = _toStringList(item['regions']);
      final festivals = _toStringList(item['festivals']);
      final historyIntro = (item['history_intro'] ?? '').toString();
      final relatedGroups = _toStringList(item['related_groups']);
      final interactionEvents = _toStringList(item['interaction_events']);

      if (features.isNotEmpty) {
        lines.add('  特征：${features.take(3).join('; ')}');
      }
      if (regions.isNotEmpty) lines.add('  地区：${regions.take(3).join(', ')}');
      if (festivals.isNotEmpty) {
        lines.add('  节日：${festivals.take(2).join(', ')}');
      }
      if (historyIntro.isNotEmpty) {
        lines.add('  历史资料：${_shorten(historyIntro, 180)}');
      }
      if (relatedGroups.isNotEmpty) {
        lines.add('  相关民族：${relatedGroups.take(4).join(', ')}');
      }
      if (interactionEvents.isNotEmpty) {
        lines.add(
          '  交往资料：${interactionEvents.take(2).join(' | ')}',
        );
      }
    }
    return lines.isEmpty ? '当前没有图片识别结果。' : lines.join('\n');
  }

  static Uri _qwenUri(ModelRuntimeConfig config) {
    final normalizedBase =
        config.qwenBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(normalizedBase);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
        baseUri.host.isEmpty) {
      throw Exception('模型接口地址无效：${config.qwenBaseUrl}');
    }
    return Uri.parse('$normalizedBase/chat/completions');
  }

  static String _apiKey(String specificKey) {
    final key = specificKey.trim();
    if (key.isEmpty) {
      throw Exception('缺少接口密钥，请打开隐藏配置页填写。');
    }
    return key;
  }

  static Future<Map<String, dynamic>> _postQwen({
    required String apiKey,
    required ModelRuntimeConfig config,
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    final response = await http
        .post(
          _qwenUri(config),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('模型接口调用失败（${response.statusCode}）：${response.body}');
  }

  static String _extractQwenContent(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return content.map((item) {
        if (item is Map) return (item['text'] ?? item['content'] ?? '');
        return item ?? '';
      }).join();
    }
    return (content ?? '').toString();
  }

  static String _shorten(String value, int maxLength) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }

  static bool _isLightQuestion(String question) {
    final normalized =
        question.trim().toLowerCase().replaceAll(RegExp(r'[\s，。！？,.!?]'), '');
    const greetings = {'你好', '您好', 'hi', 'hello', '在吗', '嗨'};
    return normalized.length <= 4 || greetings.contains(normalized);
  }

  static bool _isDetailedQuestion(String question) {
    return RegExp('详细|具体|历史|来源|来历|故事|交往|迁徙|介绍一下|多讲|展开|为什么').hasMatch(question);
  }

  static List<String> _toStringList(Object? value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return const [];
  }
}

class _OcrMatch {
  final String? label;
  final double confidence;
  final String text;

  const _OcrMatch({
    required this.label,
    required this.confidence,
    required this.text,
  });
}
