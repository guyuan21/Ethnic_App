import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Fully offline Mandarin ASR backed by sherpa-onnx + SenseVoice INT8.
///
/// The recognizer lives in a long-running isolate so the 200+ MB model is
/// loaded once and never blocks Flutter's UI thread. Android copies the model
/// out of the APK with a streaming native implementation to avoid holding the
/// entire ONNX file in Dart memory on low-memory TV/tablet devices.
class OfflineAsrService {
  static const _channel = MethodChannel('ethnic_culture_app/offline_asr');
  static const _modelAsset = 'assets/asr/sensevoice/model.int8.onnx';
  static const _tokensAsset = 'assets/asr/sensevoice/tokens.txt';
  static const _modelVersion = 'sensevoice-int8-2024-07-17-v1';

  static Future<_OfflineAsrModelPaths>? _modelPathsFuture;
  static Future<SendPort>? _workerFuture;

  static Future<void> prewarm() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final paths = await _prepareModel();
    await _ensureWorker(paths);
  }

  static Future<String> transcribe(String audioPath) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('离线语音识别当前仅支持 Android。');
    }
    if (!audioPath.toLowerCase().endsWith('.wav')) {
      throw const FormatException('离线语音识别需要 16kHz 单声道 WAV 录音。');
    }

    final audioFile = File(audioPath);
    if (!await audioFile.exists() || await audioFile.length() == 0) {
      throw const FileSystemException('录音文件为空。');
    }

    final paths = await _prepareModel();
    final worker = await _ensureWorker(paths);
    final reply = ReceivePort();
    worker.send(<String, Object>{
      'audioPath': audioPath,
      'replyPort': reply.sendPort,
    });

    try {
      final response = await reply.first.timeout(const Duration(seconds: 75));
      if (response is! Map) {
        throw StateError('离线语音识别返回了无效结果。');
      }
      final error = (response['error'] ?? '').toString().trim();
      if (error.isNotEmpty) throw StateError(error);

      final text = _normalizeTranscript((response['text'] ?? '').toString());
      if (text.isEmpty) {
        throw StateError('没有识别到清晰语音，请靠近设备后重新说一遍。');
      }
      return text;
    } finally {
      reply.close();
    }
  }

  static Future<_OfflineAsrModelPaths> _prepareModel() {
    final existing = _modelPathsFuture;
    if (existing != null) return existing;

    final future = _copyModelAssets();
    _modelPathsFuture = future;
    return future.catchError((Object error) {
      _modelPathsFuture = null;
      throw error;
    });
  }

  static Future<_OfflineAsrModelPaths> _copyModelAssets() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'prepareModel',
      <String, Object>{
        'version': _modelVersion,
        'modelAsset': _modelAsset,
        'tokensAsset': _tokensAsset,
        'minimumModelBytes': 150 * 1024 * 1024,
        'minimumTokensBytes': 100 * 1024,
      },
    );
    if (result == null) {
      throw StateError('无法准备离线语音模型。');
    }

    final modelPath = (result['modelPath'] ?? '').toString();
    final tokensPath = (result['tokensPath'] ?? '').toString();
    if (modelPath.isEmpty || tokensPath.isEmpty) {
      throw StateError('离线语音模型路径无效。');
    }
    return _OfflineAsrModelPaths(model: modelPath, tokens: tokensPath);
  }

  static Future<SendPort> _ensureWorker(_OfflineAsrModelPaths paths) {
    final existing = _workerFuture;
    if (existing != null) return existing;

    final future = _spawnWorker(paths);
    _workerFuture = future;
    return future.catchError((Object error) {
      _workerFuture = null;
      throw error;
    });
  }

  static Future<SendPort> _spawnWorker(_OfflineAsrModelPaths paths) async {
    final ready = ReceivePort();
    await Isolate.spawn<Map<String, Object>>(
      _offlineAsrWorkerMain,
      <String, Object>{
        'readyPort': ready.sendPort,
        'modelPath': paths.model,
        'tokensPath': paths.tokens,
      },
      debugName: 'sensevoice-offline-asr',
    );

    try {
      final response = await ready.first.timeout(const Duration(seconds: 60));
      if (response is SendPort) return response;
      if (response is Map) {
        final error = (response['error'] ?? '').toString();
        throw StateError(error.isEmpty ? '离线语音模型初始化失败。' : error);
      }
      throw StateError('离线语音模型初始化失败。');
    } finally {
      ready.close();
    }
  }

  @visibleForTesting
  static String normalizeTranscriptForTest(String value) =>
      _normalizeTranscript(value);

  static String _normalizeTranscript(String value) {
    var text = value
        .replaceAll(RegExp(r'<\|[^|>]+\|>'), '')
        .replaceAll(RegExp(r'''^\s*[“”"']+|[“”"']+\s*$'''), '')
        .replaceAll(',', '，')
        .replaceAll(';', '；')
        .replaceAll(':', '：')
        .replaceAll('?', '？')
        .replaceAll('!', '！')
        .replaceAll(RegExp(r'\.{2,}'), '。')
        .replaceAllMapped(
          RegExp(r'([，。！？；：])\1+'),
          (match) => match.group(1)!,
        )
        .replaceAll(RegExp(r'(?<=[\u4e00-\u9fa5])\s+(?=[\u4e00-\u9fa5])'), '')
        .trim();

    const directCorrections = <String, String>{
      '木老族': '仫佬族',
      '木佬族': '仫佬族',
      '姆佬族': '仫佬族',
      '穆佬族': '仫佬族',
      '仫老族': '仫佬族',
      '洛巴族': '珞巴族',
      '罗巴族': '珞巴族',
      '赫哲组': '赫哲族',
      '塔吉克组': '塔吉克族',
      '塔塔尔组': '塔塔尔族',
    };
    for (final entry in directCorrections.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    for (final group in _ethnicGroupNames) {
      final mistakenSuffix = '${group.substring(0, group.length - 1)}组';
      text = text.replaceAll(mistakenSuffix, group);
    }
    return text;
  }
}

class _OfflineAsrModelPaths {
  final String model;
  final String tokens;

  const _OfflineAsrModelPaths({required this.model, required this.tokens});
}

const _ethnicGroupNames = <String>[
  '汉族',
  '蒙古族',
  '回族',
  '藏族',
  '维吾尔族',
  '苗族',
  '彝族',
  '壮族',
  '布依族',
  '朝鲜族',
  '满族',
  '侗族',
  '瑶族',
  '白族',
  '土家族',
  '哈尼族',
  '哈萨克族',
  '傣族',
  '黎族',
  '傈僳族',
  '佤族',
  '畲族',
  '高山族',
  '拉祜族',
  '水族',
  '东乡族',
  '纳西族',
  '景颇族',
  '柯尔克孜族',
  '土族',
  '达斡尔族',
  '仫佬族',
  '羌族',
  '布朗族',
  '撒拉族',
  '毛南族',
  '仡佬族',
  '锡伯族',
  '阿昌族',
  '普米族',
  '塔吉克族',
  '怒族',
  '乌孜别克族',
  '俄罗斯族',
  '鄂温克族',
  '德昂族',
  '保安族',
  '裕固族',
  '京族',
  '塔塔尔族',
  '独龙族',
  '鄂伦春族',
  '赫哲族',
  '门巴族',
  '珞巴族',
  '基诺族',
];

@pragma('vm:entry-point')
void _offlineAsrWorkerMain(Map<String, Object> bootstrap) {
  final readyPort = bootstrap['readyPort']! as SendPort;
  try {
    sherpa_onnx.initBindings();
    final modelPath = bootstrap['modelPath']! as String;
    final tokensPath = bootstrap['tokensPath']! as String;
    final processors = Platform.numberOfProcessors;
    final numThreads = processors >= 6
        ? 4
        : processors >= 4
            ? 3
            : processors >= 2
                ? 2
                : 1;

    final senseVoice = sherpa_onnx.OfflineSenseVoiceModelConfig(
      model: modelPath,
      language: 'zh',
      useInverseTextNormalization: true,
    );
    final modelConfig = sherpa_onnx.OfflineModelConfig(
      senseVoice: senseVoice,
      tokens: tokensPath,
      numThreads: numThreads,
      debug: false,
      provider: 'cpu',
    );
    final recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(model: modelConfig),
    );
    final requests = ReceivePort();
    readyPort.send(requests.sendPort);

    requests.listen((dynamic message) {
      if (message is! Map) return;
      final replyPort = message['replyPort'];
      final audioPath = (message['audioPath'] ?? '').toString();
      if (replyPort is! SendPort) return;

      sherpa_onnx.OfflineStream? stream;
      try {
        final wave = sherpa_onnx.readWave(audioPath);
        if (wave.samples.isEmpty) {
          throw StateError('录音中没有可识别的音频数据。');
        }
        stream = recognizer.createStream();
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        replyPort.send(<String, String>{
          'text': result.text,
          'language': result.lang,
        });
      } catch (error) {
        replyPort.send(<String, String>{'error': error.toString()});
      } finally {
        stream?.free();
      }
    });
  } catch (error) {
    readyPort.send(<String, String>{'error': error.toString()});
  }
}
