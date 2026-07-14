import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_flutter/pages/model_config_page.dart';
import 'package:app_flutter/services/model_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Tencent TTS defaults do not package credentials', () async {
    SharedPreferences.setMockInitialValues({});

    final config = await ModelConfigService.load();

    expect(config.tencentSecretId, isEmpty);
    expect(config.tencentSecretKey, isEmpty);
    expect(config.tencentVoiceType, '1001');
  });

  test('saves and reloads the basic Tencent TTS configuration', () async {
    SharedPreferences.setMockInitialValues({});
    final defaults = ModelRuntimeConfig.packagedDefaults();

    await ModelConfigService.save(
      ModelRuntimeConfig(
        qwenBaseUrl: defaults.qwenBaseUrl,
        qwenApiKey: '',
        qwenChatModel: defaults.qwenChatModel,
        tencentAppId: '1234567890',
        tencentSecretId: 'test-secret-id',
        tencentSecretKey: 'test-secret-key',
        tencentToken: 'test-token',
        tencentVoiceType: '1001',
      ),
    );

    final config = await ModelConfigService.load();
    expect(config.tencentAppId, '1234567890');
    expect(config.tencentSecretId, 'test-secret-id');
    expect(config.tencentSecretKey, 'test-secret-key');
    expect(config.tencentToken, 'test-token');
    expect(config.tencentVoiceType, '1001');
  });

  testWidgets('configuration page only shows Tencent TTS settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: ModelConfigPage()));
    await tester.pumpAndSettle();

    expect(find.text('腾讯云文字朗读'), findsOneWidget);
    expect(find.text('SecretId'), findsOneWidget);
    expect(find.text('SecretKey'), findsOneWidget);
    expect(find.text('音色 VoiceType'), findsOneWidget);
    expect(find.textContaining('千问 TTS'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}
