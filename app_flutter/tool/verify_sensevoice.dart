import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr
        .writeln('Usage: dart run tool/verify_sensevoice.dart <16k-mono.wav>');
    exitCode = 64;
    return;
  }

  final appRoot = p.dirname(p.dirname(Platform.script.toFilePath()));
  final modelDir = p.join(appRoot, 'assets', 'asr', 'sensevoice');
  final modelPath = p.join(modelDir, 'model.int8.onnx');
  final tokensPath = p.join(modelDir, 'tokens.txt');
  final audioPath = p.absolute(arguments.single);
  for (final filePath in [modelPath, tokensPath, audioPath]) {
    if (!File(filePath).existsSync()) {
      stderr.writeln('Missing file: $filePath');
      exitCode = 66;
      return;
    }
  }

  // Some Windows development machines have an older onnxruntime.dll in
  // System32. Load the DLL bundled by sherpa_onnx first so verification uses
  // the same runtime version as the plugin instead of the system-wide copy.
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final bundledRuntime = p.join(
        localAppData,
        'Pub',
        'Cache',
        'hosted',
        'pub.dev',
        'sherpa_onnx_windows-1.13.4',
        'windows',
        'onnxruntime.dll',
      );
      if (File(bundledRuntime).existsSync()) {
        DynamicLibrary.open(bundledRuntime);
      }
    }
  }
  sherpa_onnx.initBindings();
  final recognizer = sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
          model: modelPath,
          language: 'zh',
          useInverseTextNormalization: true,
        ),
        tokens: tokensPath,
        numThreads: 4,
        provider: 'cpu',
      ),
    ),
  );

  final stream = recognizer.createStream();
  try {
    final wave = sherpa_onnx.readWave(audioPath);
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    stdout.writeln('language: ${result.lang}');
    stdout.writeln('text: ${result.text}');
  } finally {
    stream.free();
    recognizer.free();
  }
}
