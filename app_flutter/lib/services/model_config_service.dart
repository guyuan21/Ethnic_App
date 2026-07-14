import 'package:shared_preferences/shared_preferences.dart';

class ModelRuntimeConfig {
  static const String packagedQwenBaseUrl = String.fromEnvironment(
    'QWEN_BASE_URL',
    defaultValue: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  );
  static const String packagedQwenChatModel = String.fromEnvironment(
    'QWEN_CHAT_MODEL',
    defaultValue: 'qwen-turbo',
  );

  final String qwenBaseUrl;
  final String qwenApiKey;
  final String qwenChatModel;
  final String tencentAppId;
  final String tencentSecretId;
  final String tencentSecretKey;
  final String tencentToken;
  final String tencentVoiceType;

  const ModelRuntimeConfig({
    required this.qwenBaseUrl,
    required this.qwenApiKey,
    required this.qwenChatModel,
    required this.tencentAppId,
    required this.tencentSecretId,
    required this.tencentSecretKey,
    required this.tencentToken,
    required this.tencentVoiceType,
  });

  factory ModelRuntimeConfig.packagedDefaults() {
    return const ModelRuntimeConfig(
      qwenBaseUrl: packagedQwenBaseUrl,
      // Credentials are entered after installation and are not packaged.
      qwenApiKey: '',
      qwenChatModel: packagedQwenChatModel,
      tencentAppId: '',
      tencentSecretId: '',
      tencentSecretKey: '',
      tencentToken: '',
      tencentVoiceType: '1001',
    );
  }
}

class ModelConfigService {
  static const _qwenBaseUrl = 'model_config.qwen_base_url';
  static const _qwenApiKey = 'model_config.qwen_api_key';
  static const _qwenChatModel = 'model_config.qwen_chat_model';
  static const _tencentAppId = 'model_config.tencent_tts_app_id';
  static const _tencentSecretId = 'model_config.tencent_tts_secret_id';
  static const _tencentSecretKey = 'model_config.tencent_tts_secret_key';
  static const _tencentToken = 'model_config.tencent_tts_token';
  static const _tencentVoiceType = 'model_config.tencent_tts_voice_type';

  static Future<ModelRuntimeConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = ModelRuntimeConfig.packagedDefaults();

    String read(String key, String fallback, {bool allowEmpty = false}) {
      final value = prefs.getString(key);
      if (value == null) return fallback;
      if (value.trim().isEmpty && !allowEmpty) return fallback;
      return value.trim();
    }

    return ModelRuntimeConfig(
      qwenBaseUrl: read(_qwenBaseUrl, defaults.qwenBaseUrl),
      qwenApiKey: read(_qwenApiKey, defaults.qwenApiKey, allowEmpty: true),
      qwenChatModel: read(_qwenChatModel, defaults.qwenChatModel),
      tencentAppId: read(
        _tencentAppId,
        defaults.tencentAppId,
        allowEmpty: true,
      ),
      tencentSecretId: read(
        _tencentSecretId,
        defaults.tencentSecretId,
        allowEmpty: true,
      ),
      tencentSecretKey: read(
        _tencentSecretKey,
        defaults.tencentSecretKey,
        allowEmpty: true,
      ),
      tencentToken: read(
        _tencentToken,
        defaults.tencentToken,
        allowEmpty: true,
      ),
      tencentVoiceType: read(
        _tencentVoiceType,
        defaults.tencentVoiceType,
      ),
    );
  }

  static Future<void> save(ModelRuntimeConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_qwenBaseUrl, config.qwenBaseUrl.trim()),
      prefs.setString(_qwenApiKey, config.qwenApiKey.trim()),
      prefs.setString(_qwenChatModel, config.qwenChatModel.trim()),
      prefs.setString(_tencentAppId, config.tencentAppId.trim()),
      prefs.setString(_tencentSecretId, config.tencentSecretId.trim()),
      prefs.setString(_tencentSecretKey, config.tencentSecretKey.trim()),
      prefs.setString(_tencentToken, config.tencentToken.trim()),
      prefs.setString(_tencentVoiceType, config.tencentVoiceType.trim()),
    ]);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_qwenBaseUrl),
      prefs.remove(_qwenApiKey),
      prefs.remove(_qwenChatModel),
      prefs.remove(_tencentAppId),
      prefs.remove(_tencentSecretId),
      prefs.remove(_tencentSecretKey),
      prefs.remove(_tencentToken),
      prefs.remove(_tencentVoiceType),
    ]);
  }
}
