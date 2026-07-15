import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class CartoonPrediction {
  final String label;
  final double confidence;

  const CartoonPrediction({
    required this.label,
    required this.confidence,
  });
}

class CartoonClassifierService {
  static const MethodChannel _channel = MethodChannel(
    'ethnic_culture_app/executorch_classifier',
  );
  static const String _modelAsset =
      'assets/model/resnest50_ethnic_int8_qat.pte';
  static const String _labelsAsset = 'assets/model/labels.txt';
  static const String _modelVersion = 'resnest50_qat_79360767';
  // Must match the export metadata. The model is 24.95 MiB, so a rounded
  // 25 MiB lower bound would incorrectly reject the valid bundled file.
  static const int _expectedModelBytes = 26163296;
  static const int _resizeSize = 256;
  static const int _inputSize = 224;
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std = [0.229, 0.224, 0.225];

  static final CartoonClassifierService instance = CartoonClassifierService._();

  CartoonClassifierService._();

  List<String>? _labels;
  Future<void>? _loadFuture;

  Future<void> load() async {
    final existing = _loadFuture;
    if (existing != null) return existing;

    final current = _load();
    _loadFuture = current;
    try {
      await current;
    } catch (_) {
      // A failed home-page prewarm must not permanently poison recognition.
      // The next real request gets one clean retry after a transient failure.
      if (identical(_loadFuture, current)) _loadFuture = null;
      rethrow;
    }
  }

  Future<List<CartoonPrediction>> classify(Uint8List bytes) async {
    await load();
    final labels = _labels;
    if (labels == null || labels.isEmpty) {
      throw Exception('ExecuTorch cartoon classifier is not loaded.');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Unable to decode this image. Please use a JPG or PNG.');
    }
    final input = _preprocess(decoded);
    final rawOutput = await _channel.invokeMethod<Object?>(
      'classify',
      <String, Object>{'input': input},
    );
    final output = _asDoubleList(rawOutput);
    if (output.length != labels.length) {
      throw Exception(
        'ExecuTorch output classes (${output.length}) do not match '
        'label count (${labels.length}).',
      );
    }

    final probabilities = _softmax(output);
    final predictions = List<CartoonPrediction>.generate(
      labels.length,
      (index) => CartoonPrediction(
        label: labels[index],
        confidence: probabilities[index],
      ),
      growable: false,
    )..sort((a, b) => b.confidence.compareTo(a.confidence));
    return predictions.take(5).toList(growable: false);
  }

  Future<void> _load() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'The ExecuTorch classifier is currently available on Android only.',
      );
    }
    final rawLabels = await rootBundle.loadString(_labelsAsset);
    final labels = rawLabels
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList(growable: false);
    if (labels.length != 56) {
      throw Exception('Expected 56 labels, found ${labels.length}.');
    }
    await _channel.invokeMethod<void>(
      'loadModel',
      <String, Object>{
        'version': _modelVersion,
        'modelAsset': _modelAsset,
        'expectedModelBytes': _expectedModelBytes,
      },
    );
    _labels = labels;
  }

  Float32List _preprocess(img.Image source) {
    final oriented = img.bakeOrientation(source);
    final img.Image resized;
    if (oriented.width <= oriented.height) {
      resized = img.copyResize(
        oriented,
        width: _resizeSize,
        interpolation: img.Interpolation.linear,
      );
    } else {
      resized = img.copyResize(
        oriented,
        height: _resizeSize,
        interpolation: img.Interpolation.linear,
      );
    }
    final cropX = math.max(0, (resized.width - _inputSize) ~/ 2);
    final cropY = math.max(0, (resized.height - _inputSize) ~/ 2);
    final cropped = img.copyCrop(
      resized,
      x: cropX,
      y: cropY,
      width: _inputSize,
      height: _inputSize,
    );

    // ExecuTorch model input is float32 NCHW with ImageNet normalization.
    const planeSize = _inputSize * _inputSize;
    final input = Float32List(3 * planeSize);
    for (var y = 0; y < _inputSize; y += 1) {
      for (var x = 0; x < _inputSize; x += 1) {
        final pixel = cropped.getPixel(x, y);
        final alpha = (pixel.a / 255.0).clamp(0.0, 1.0).toDouble();
        final red = ((pixel.r * alpha) + (255 * (1 - alpha))) / 255.0;
        final green = ((pixel.g * alpha) + (255 * (1 - alpha))) / 255.0;
        final blue = ((pixel.b * alpha) + (255 * (1 - alpha))) / 255.0;
        final index = y * _inputSize + x;
        input[index] = (red - _mean[0]) / _std[0];
        input[planeSize + index] = (green - _mean[1]) / _std[1];
        input[2 * planeSize + index] = (blue - _mean[2]) / _std[2];
      }
    }
    return input;
  }

  @visibleForTesting
  Float32List preprocessForTesting(img.Image source) => _preprocess(source);

  List<double> _asDoubleList(Object? value) {
    if (value is Float32List) {
      return value.map((item) => item.toDouble()).toList(growable: false);
    }
    if (value is Float64List) {
      return value.toList(growable: false);
    }
    if (value is List) {
      return value
          .whereType<num>()
          .map((item) => item.toDouble())
          .toList(growable: false);
    }
    throw Exception('ExecuTorch returned an unsupported output value.');
  }

  List<double> _softmax(List<double> logits) {
    final maxValue = logits.fold<double>(
      double.negativeInfinity,
      math.max,
    );
    final exponentials = logits
        .map((value) => math.exp(value - maxValue))
        .toList(growable: false);
    final sum = exponentials.fold<double>(0, (total, value) => total + value);
    if (sum == 0 || !sum.isFinite) {
      return List<double>.filled(logits.length, 0, growable: false);
    }
    return exponentials.map((value) => value / sum).toList(growable: false);
  }
}
