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
import 'local_reference_matcher_service.dart';
import 'model_config_service.dart';

class ApiService {
  static const double _minCartoonConfidence = 0.70;
  static const String _notice = '本结果仅识别民族服饰卡通图片，不代表对真人民族身份的判断。';

  static Map<String, Map<String, dynamic>>? _cultureInfoCache;
  static List<Map<String, dynamic>>? _costumeReferenceCache;

  static Future<void> prewarmLocalCostumeMatcher() async {
    await Future.wait([
      CartoonClassifierService.instance.load(),
      LocalReferenceMatcherService.instance.load(),
    ]);
  }

  static String resolveUrl(String pathOrUrl) {
    return pathOrUrl;
  }

  static Future<Map<String, dynamic>> recognizeImage(XFile imageFile) async {
    final cultureInfo = await _cultureInfo();
    final filenameLabel = await _matchLabelFromOcrText(
      imageFile.name.isEmpty ? imageFile.path : imageFile.name,
      cultureInfo,
    );
    final bytes = await imageFile.readAsBytes();
    final referenceCandidate =
        await LocalReferenceMatcherService.instance.bestCandidate(bytes);
    if (referenceCandidate != null &&
        referenceCandidate.isStrongReference &&
        cultureInfo.containsKey(referenceCandidate.label)) {
      return _formatResult(
        results: [
          _toResult(
            referenceCandidate.label,
            referenceCandidate.confidence,
            cultureInfo[referenceCandidate.label]!,
          ),
        ],
        predictions: const [],
        engine: referenceCandidate.engine,
      );
    }

    final ocrMatch = await _tryOcrTitleMatch(imageFile, cultureInfo);
    final supportingLabel = ocrMatch?.label ?? filenameLabel;
    final hasCostumeEvidence = referenceCandidate != null &&
        referenceCandidate.confidence >= 0.30 &&
        referenceCandidate.margin >= 0.04;

    if (hasCostumeEvidence &&
        supportingLabel != null &&
        supportingLabel == referenceCandidate.label &&
        cultureInfo.containsKey(supportingLabel)) {
      return _formatResult(
        results: [
          _toResult(
            supportingLabel,
            ocrMatch?.label == supportingLabel ? 0.99 : 0.96,
            cultureInfo[supportingLabel]!,
          ),
        ],
        predictions: const [],
        engine: ocrMatch?.label == supportingLabel
            ? 'local_title_ocr_match'
            : 'local_filename_match',
        ocrText: ocrMatch?.text,
      );
    }

    final predictions = await CartoonClassifierService.instance.classify(bytes);
    final recognized = predictions
        .where((item) => cultureInfo.containsKey(item.label))
        .toList(growable: false);

    final best = recognized.isEmpty ? null : recognized.first;
    final supportedCostumeResult = best != null &&
        best.confidence >= _minCartoonConfidence &&
        hasCostumeEvidence &&
        referenceCandidate.label == best.label;

    if (!supportedCostumeResult) {
      final warning = !hasCostumeEvidence
          ? '仅支持民族服饰卡通图片。当前图片不像已收录的服饰卡通参考图，请更换服饰人物图片后重试。'
          : best == null || best.confidence < _minCartoonConfidence
              ? '本地服饰模型最高置信度低于70%，暂不展示结果。请保持服饰人物主体清晰、完整并减少反光。'
              : '服饰模型与本地参考图库判断不一致，为避免误识别暂不展示结果，请重新拍摄。';
      return _formatResult(
        results: const [],
        warning: warning,
        predictions: predictions,
        ocrText: ocrMatch?.text,
      );
    }

    return _formatResult(
      results: [
        _toResult(best.label, best.confidence, cultureInfo[best.label]!),
      ],
      predictions: predictions,
      ocrText: ocrMatch?.text,
    );
  }

  static Future<String> transcribeAudio(String audioPath) async {
    if (kIsWeb) {
      throw Exception('网页端暂不支持语音上传，请直接输入文字。');
    }

    final config = await ModelConfigService.load();
    final baseUri = _asrServerUri(config.asrServerUrl);
    final audioFile = File(audioPath);
    if (!await audioFile.exists() || await audioFile.length() == 0) {
      throw Exception('音频文件为空。');
    }

    final uploadRequest = http.MultipartRequest(
      'POST',
      baseUri.resolve('/gradio_api/upload'),
    );
    uploadRequest.files.add(
      await http.MultipartFile.fromPath('files', audioPath),
    );
    final uploadResponse = await uploadRequest.send().timeout(
          const Duration(seconds: 90),
        );
    final uploadBody = await uploadResponse.stream.bytesToString();
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw Exception(
        '语音文件上传失败（${uploadResponse.statusCode}）：$uploadBody',
      );
    }
    final uploadedPath = _extractGradioUploadPath(uploadBody);

    final submitResponse = await http
        .post(
          baseUri.resolve('/gradio_api/call/transcribe_audio'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'data': [
              {
                'path': uploadedPath,
                'orig_name': p.basename(audioPath),
                'size': await audioFile.length(),
                'mime_type': _mimeTypeForName(
                  audioPath,
                  fallback: 'audio/wav',
                ),
                'is_stream': false,
                'meta': {'_type': 'gradio.FileData'},
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (submitResponse.statusCode < 200 || submitResponse.statusCode >= 300) {
      throw Exception(
        '语音识别任务提交失败（${submitResponse.statusCode}）：${submitResponse.body}',
      );
    }
    final submitData = jsonDecode(submitResponse.body);
    final eventId = submitData is Map
        ? (submitData['event_id'] ?? '').toString().trim()
        : '';
    if (eventId.isEmpty) throw Exception('语音识别服务器没有返回任务编号。');

    final resultResponse = await http
        .get(baseUri.resolve('/gradio_api/call/transcribe_audio/$eventId'))
        .timeout(const Duration(minutes: 5));
    if (resultResponse.statusCode < 200 || resultResponse.statusCode >= 300) {
      throw Exception(
        '获取语音识别结果失败（${resultResponse.statusCode}）：${resultResponse.body}',
      );
    }
    final text = _extractGradioSseText(resultResponse.body).trim();
    if (text.isEmpty) throw Exception('语音识别没有返回文字。');
    return _normalizeTranscriptPunctuation(text);
  }

  static Uri _asrServerUri(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      throw Exception('语音识别服务器地址无效，只允许使用 HTTPS 地址。');
    }
    return Uri.parse('$normalized/');
  }

  static String _extractGradioUploadPath(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty) {
      throw Exception('语音识别服务器没有返回上传文件路径。');
    }
    final first = decoded.first;
    final path = first is Map
        ? (first['path'] ?? '').toString().trim()
        : first.toString().trim();
    if (path.isEmpty) throw Exception('语音识别服务器返回了空文件路径。');
    return path;
  }

  static String _extractGradioSseText(String body) {
    String? completedData;
    String? errorData;
    for (final block in body.split(RegExp(r'\r?\n\r?\n'))) {
      String event = '';
      final dataLines = <String>[];
      for (final line in block.split(RegExp(r'\r?\n'))) {
        if (line.startsWith('event:')) {
          event = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring('data:'.length).trim());
        }
      }
      final data = dataLines.join('\n');
      if (event == 'complete') completedData = data;
      if (event == 'error') errorData = data;
    }
    if (errorData != null && errorData.isNotEmpty) {
      throw Exception('语音识别服务器处理失败：$errorData');
    }
    if (completedData == null || completedData.isEmpty) {
      throw Exception('语音识别服务器未返回完成事件，可能正在排队或暂不可用。');
    }
    final decoded = jsonDecode(completedData);
    if (decoded is List && decoded.isNotEmpty) {
      return decoded.first?.toString() ?? '';
    }
    return decoded?.toString() ?? '';
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
      apiKey: _apiKey(config, config.qwenApiKey),
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

  static String _apiKey(ModelRuntimeConfig config, String specificKey) {
    final key = config.keyFor(specificKey);
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

  static String _mimeTypeForName(String name, {required String fallback}) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return fallback;
  }

  static String _normalizeTranscriptPunctuation(String value) {
    var text = value
        .replaceAll(RegExp(r'''^\s*[“”"']+|[“”"']+\s*$'''), '')
        .replaceAll(',', '，')
        .replaceAll(';', '；')
        .replaceAll(':', '：')
        .replaceAll('?', '？')
        .replaceAll('!', '！')
        .replaceAll(RegExp(r'\.{2,}'), '。')
        .replaceAll(RegExp(r'([，。！？；：])\1+'), r'$1')
        .replaceAll(RegExp(r'(?<=[\u4e00-\u9fa5])\s+(?=[\u4e00-\u9fa5])'), '')
        .trim();
    if (text.isEmpty) return text;

    final asksQuestion = RegExp(
      r'^(请问|能不能|可不可以|有没有|是否)|为什么|怎么|怎样|什么|哪里|哪儿|哪个|多少|几种|吗[。！]?$|呢[。！]?$',
    ).hasMatch(text);
    if (asksQuestion) {
      text = text.replaceFirst(RegExp(r'[。！]$'), '？');
      if (!text.endsWith('？')) text = '$text？';
    } else if (!RegExp(r'[。！？]$').hasMatch(text)) {
      text = '$text。';
    }
    return text;
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
