import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PP-OCRv5 mobile assets', () {
    test('official mobile detector, recognizer and dictionary are complete',
        () {
      final detector = File(
        'assets/ocr/ppocrv5/ppocrv5_mobile_det.onnx',
      );
      final recognizer = File(
        'assets/ocr/ppocrv5/ppocrv5_mobile_rec.onnx',
      );
      final dictionary = File('assets/ocr/ppocrv5/ppocrv5_dict.txt');

      expect(detector.lengthSync(), 4826518);
      expect(recognizer.lengthSync(), 16534782);
      expect(dictionary.readAsLinesSync(), hasLength(18383));
    });

    test('legacy ML Kit is removed and ONNX Runtime ABIs stay aligned', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final androidDependencies =
          File('android/app/build.gradle.kts').readAsStringSync();
      final proguardRules =
          File('android/app/proguard-rules.pro').readAsStringSync();

      expect(pubspec, isNot(contains('google_mlkit_text_recognition')));
      expect(pubspec, contains('sherpa_onnx: 1.13.3'));
      expect(pubspec, contains('sherpa_onnx_android_arm64: 1.13.3'));
      expect(androidDependencies, isNot(contains('text-recognition-chinese')));
      expect(androidDependencies, contains('onnxruntime-android:1.24.3'));
      expect(
        proguardRules,
        contains('-keep class ai.onnxruntime.** { *; }'),
      );
    });

    test('title search uses allow-list and mirrored full-image fallback', () {
      final channel = File(
        'android/app/src/main/kotlin/com/example/app_flutter/PpOcrV5Channel.kt',
      ).readAsStringSync();
      final matcher = File(
        'android/app/src/main/kotlin/com/example/app_flutter/EthnicTitleMatcher.kt',
      ).readAsStringSync();

      expect(channel, contains('top_band'));
      expect(channel, contains('full_image_mirrored'));
      expect(channel, contains('EthnicTitleMatcher.find'));
      expect(matcher, contains('"门巴族"'));
      expect(matcher, contains('"白族"'));
    });
  });
}
