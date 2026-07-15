import 'dart:convert';
import 'dart:io';

import 'package:app_flutter/services/cartoon_classifier_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ExecuTorch classifier assets', () {
    test('metadata, labels and model size stay consistent', () {
      final metadata = jsonDecode(
        File('assets/model/resnest50_ethnic_int8_qat.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final labels = File('assets/model/labels.txt')
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList(growable: false);
      final metadataLabels = (metadata['classes'] as List<dynamic>)
          .map((item) => item.toString())
          .toList(growable: false);
      final modelBytes =
          File('assets/model/resnest50_ethnic_int8_qat.pte').lengthSync();

      expect(labels, hasLength(56));
      expect(metadataLabels, labels);
      final inputMetadata = metadata['input'] as Map<String, dynamic>;
      expect(inputMetadata['shape'], [1, 3, 224, 224]);
      expect(metadata['bytes'], modelBytes);
      expect(modelBytes, 26163296);
    });

    test('preprocessing produces normalized NCHW channels', () {
      final source = img.Image(width: 320, height: 480);
      img.fill(source, color: img.ColorRgb8(255, 0, 0));

      final input =
          CartoonClassifierService.instance.preprocessForTesting(source);
      const plane = 224 * 224;

      expect(input, hasLength(3 * plane));
      expect(input[0], closeTo((1 - 0.485) / 0.229, 0.0001));
      expect(input[plane], closeTo((0 - 0.456) / 0.224, 0.0001));
      expect(input[2 * plane], closeTo((0 - 0.406) / 0.225, 0.0001));
    });

    test('1600x1200 preprocessing remains within a coarse CPU budget', () {
      final source = img.Image(width: 1600, height: 1200);
      img.fill(source, color: img.ColorRgb8(80, 120, 180));
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 3; i += 1) {
        CartoonClassifierService.instance.preprocessForTesting(source);
      }
      stopwatch.stop();
      // Intentionally broad: catches accidental quadratic work without being
      // flaky across CI and developer machines. The measured time is printed
      // during the verification run for a useful baseline.
      // ignore: avoid_print
      print('classifier_preprocess_3x_ms=${stopwatch.elapsedMilliseconds}');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
