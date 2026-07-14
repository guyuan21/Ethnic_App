import 'package:app_flutter/services/offline_asr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineAsrService transcript normalization', () {
    test('removes SenseVoice tags and normalizes punctuation', () {
      final result = OfflineAsrService.normalizeTranscriptForTest(
        '<|zh|><|NEUTRAL|><|Speech|>你好,,世界!!',
      );

      expect(result, '你好，世界！');
    });

    test('corrects common ethnic group homophones', () {
      final result = OfflineAsrService.normalizeTranscriptForTest(
        '这是木老族和洛巴族的服饰',
      );

      expect(result, '这是仫佬族和珞巴族的服饰');
    });

    test('corrects group suffix only for known ethnic names', () {
      final result = OfflineAsrService.normalizeTranscriptForTest(
        '介绍塔吉克组、塔塔尔组和学习小组',
      );

      expect(result, '介绍塔吉克族、塔塔尔族和学习小组');
    });
  });
}
