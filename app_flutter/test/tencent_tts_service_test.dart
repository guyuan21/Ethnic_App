import 'package:flutter_test/flutter_test.dart';

import 'package:app_flutter/services/tencent_tts_service.dart';

void main() {
  group('TencentTtsService text splitting', () {
    test('returns no chunks for blank text', () {
      expect(TencentTtsService.splitTextForBasicTts('   \n  '), isEmpty);
    });

    test('prefers sentence boundaries', () {
      final chunks = TencentTtsService.splitTextForBasicTts(
        '这是第一段需要朗读的内容，长度足够用于测试。'
        '这是第二段需要朗读的内容，也应该在句号附近切开。',
        maxCharacters: 32,
      );

      expect(chunks, hasLength(2));
      expect(chunks.first, endsWith('。'));
      expect(chunks.join(), contains('第二段'));
    });

    test('keeps every request below the configured limit', () {
      final text = List.filled(31, '民族服饰识别').join();
      final chunks = TencentTtsService.splitTextForBasicTts(
        text,
        maxCharacters: 40,
      );

      expect(chunks, isNotEmpty);
      expect(chunks.every((chunk) => chunk.length <= 40), isTrue);
      expect(chunks.join(), text);
    });
  });
}
