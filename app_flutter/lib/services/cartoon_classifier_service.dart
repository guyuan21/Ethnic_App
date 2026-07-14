import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class CartoonPrediction {
  final String label;
  final double confidence;

  const CartoonPrediction({
    required this.label,
    required this.confidence,
  });
}

class CartoonClassifierService {
  static const String _modelAsset = 'assets/model/ethnic_model.tflite';
  static const String _labelsAsset = 'assets/model/labels.txt';
  static const int _inputSize = 224;

  static final CartoonClassifierService instance = CartoonClassifierService._();

  CartoonClassifierService._();

  Interpreter? _interpreter;
  List<String>? _labels;
  Future<void>? _loadFuture;

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<List<CartoonPrediction>> classify(Uint8List bytes) async {
    await load();
    final interpreter = _interpreter;
    final labels = _labels;
    if (interpreter == null || labels == null || labels.isEmpty) {
      throw Exception('Local cartoon classifier is not loaded.');
    }

    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Unable to decode this image. Please use a JPG or PNG.');
    }

    final input = _preprocess(image);
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    // Write the tensor as contiguous float32 bytes. Passing a four-level Dart
    // List makes tflite_flutter recursively infer and convert every element;
    // on some Android devices that path can produce platform-dependent input.
    // Direct tensor I/O keeps the exact same RGB values and model math on all
    // devices, so this is a runtime fix rather than a class-specific rule.
    inputTensor.data = Uint8List.view(
      input.buffer,
      input.offsetInBytes,
      input.lengthInBytes,
    );
    interpreter.invoke();

    final outputBytes = outputTensor.data;
    final outputValues = Float32List.view(
      outputBytes.buffer,
      outputBytes.offsetInBytes,
      labels.length,
    );
    final output = List<double>.generate(
      labels.length,
      (index) => outputValues[index],
      growable: false,
    );

    final scores = _toProbabilities(output);
    final indexed = <CartoonPrediction>[];
    for (var i = 0; i < math.min(labels.length, scores.length); i += 1) {
      indexed.add(
        CartoonPrediction(label: labels[i], confidence: scores[i]),
      );
    }
    indexed.sort((a, b) => b.confidence.compareTo(a.confidence));
    return indexed.take(5).toList(growable: false);
  }

  Future<void> _load() async {
    final interpreter = await Interpreter.fromAsset(_modelAsset);
    final rawLabels = await rootBundle.loadString(_labelsAsset);
    final labels = rawLabels
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList(growable: false);

    final outputShape = interpreter.getOutputTensor(0).shape;
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    if (inputTensor.type != TensorType.float32 ||
        inputShape.length != 4 ||
        inputShape[0] != 1 ||
        inputShape[1] != _inputSize ||
        inputShape[2] != _inputSize ||
        inputShape[3] != 3) {
      interpreter.close();
      throw Exception(
        'Unsupported model input: ${inputTensor.type} $inputShape. '
        'Expected float32 [1, $_inputSize, $_inputSize, 3].',
      );
    }
    if (outputTensor.type != TensorType.float32) {
      interpreter.close();
      throw Exception(
        'Unsupported model output: ${outputTensor.type}. Expected float32.',
      );
    }
    if (outputShape.length != 2 || outputShape.last != labels.length) {
      interpreter.close();
      throw Exception(
        'Model output classes (${outputShape.isEmpty ? 0 : outputShape.last}) '
        'do not match label count (${labels.length}).',
      );
    }

    _interpreter = interpreter;
    _labels = labels;
  }

  Float32List _preprocess(img.Image source) {
    final oriented = img.bakeOrientation(source);
    final resized = img.copyResize(
      oriented,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = Float32List(_inputSize * _inputSize * 3);
    var offset = 0;
    for (var y = 0; y < _inputSize; y += 1) {
      for (var x = 0; x < _inputSize; x += 1) {
        final pixel = resized.getPixel(x, y);
        final alpha = (pixel.a / 255.0).clamp(0.0, 1.0).toDouble();
        input[offset++] = (pixel.r * alpha) + (255 * (1 - alpha));
        input[offset++] = (pixel.g * alpha) + (255 * (1 - alpha));
        input[offset++] = (pixel.b * alpha) + (255 * (1 - alpha));
      }
    }
    return input;
  }

  List<double> _toProbabilities(List<double> values) {
    final sum = values.fold<double>(0, (total, value) => total + value);
    final alreadyProbabilities =
        values.every((value) => value >= 0) && (sum - 1.0).abs() < 0.05;
    if (alreadyProbabilities) return values;

    final maxValue = values.fold<double>(
      double.negativeInfinity,
      (current, value) => math.max(current, value),
    );
    final expValues =
        values.map((value) => math.exp(value - maxValue)).toList();
    final expSum = expValues.fold<double>(0, (total, value) => total + value);
    if (expSum == 0 || expSum.isNaN) {
      return List<double>.filled(values.length, 0);
    }
    return expValues.map((value) => value / expSum).toList(growable: false);
  }
}
