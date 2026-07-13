import 'package:shared_preferences/shared_preferences.dart';

class ModelRuntimeConfig {
  static const String packagedQwenBaseUrl = String.fromEnvironment(
    'QWEN_BASE_URL',
    defaultValue: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  );
  static const String packagedQwenTtsUrl = String.fromEnvironment(
    'QWEN_TTS_URL',
    defaultValue:
        'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
  );
  static const String packagedQwenChatModel = String.fromEnvironment(
    'QWEN_CHAT_MODEL',
    defaultValue: 'qwen-turbo',
  );
  static const String packagedAsrServerUrl = String.fromEnvironment(
    'ASR_SERVER_URL',
    defaultValue: 'https://artificialguybr-fish-s2-pro-zero.hf.space',
  );
  static const String packagedQwenTtsModel = String.fromEnvironment(
    'QWEN_TTS_MODEL',
    defaultValue: 'qwen3-tts-flash',
  );
  static const String packagedQwenTtsVoice = String.fromEnvironment(
    'QWEN_TTS_VOICE',
    defaultValue: 'Cherry',
  );

  final String qwenBaseUrl;
  final String qwenApiKey;
  final String asrServerUrl;
  final String qwenTtsUrl;
  final String qwenTtsApiKey;
  final String qwenChatModel;
  final String qwenTtsModel;
  final String qwenTtsVoice;

  const ModelRuntimeConfig({
    required this.qwenBaseUrl,
    required this.qwenApiKey,
    required this.asrServerUrl,
    required this.qwenTtsUrl,
    required this.qwenTtsApiKey,
    required this.qwenChatModel,
    required this.qwenTtsModel,
    required this.qwenTtsVoice,
  });

  factory ModelRuntimeConfig.packagedDefaults() {
    return const ModelRuntimeConfig(
      qwenBaseUrl: packagedQwenBaseUrl,
      // API keys are deliberately never accepted from dart-define. Users must
      // enter them after installation in the hidden local configuration page.
      qwenApiKey: '',
      asrServerUrl: packagedAsrServerUrl,
      qwenTtsUrl: packagedQwenTtsUrl,
      qwenTtsApiKey: '',
      qwenChatModel: packagedQwenChatModel,
      qwenTtsModel: packagedQwenTtsModel,
      qwenTtsVoice: packagedQwenTtsVoice,
    );
  }

  String keyFor(String specificKey) {
    final key = specificKey.trim().isNotEmpty ? specificKey : qwenApiKey;
    return key.trim();
  }
}

class ModelConfigService {
  static const _qwenBaseUrl = 'model_config.qwen_base_url';
  static const _qwenApiKey = 'model_config.qwen_api_key';
  static const _asrServerUrl = 'model_config.asr_server_url';
  static const _legacyQwenAsrApiKey = 'model_config.qwen_asr_api_key';
  static const _qwenTtsUrl = 'model_config.qwen_tts_url';
  static const _qwenTtsApiKey = 'model_config.qwen_tts_api_key';
  static const _qwenChatModel = 'model_config.qwen_chat_model';
  static const _legacyQwenAsrModel = 'model_config.qwen_asr_model';
  static const _qwenTtsModel = 'model_config.qwen_tts_model';
  static const _qwenTtsVoice = 'model_config.qwen_tts_voice';

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
      asrServerUrl: read(_asrServerUrl, defaults.asrServerUrl),
      qwenTtsUrl: read(_qwenTtsUrl, defaults.qwenTtsUrl),
      qwenTtsApiKey:
          read(_qwenTtsApiKey, defaults.qwenTtsApiKey, allowEmpty: true),
      qwenChatModel: read(_qwenChatModel, defaults.qwenChatModel),
      qwenTtsModel: read(_qwenTtsModel, defaults.qwenTtsModel),
      qwenTtsVoice: read(_qwenTtsVoice, defaults.qwenTtsVoice),
    );
  }

  static Future<void> save(ModelRuntimeConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_qwenBaseUrl, config.qwenBaseUrl.trim()),
      prefs.setString(_qwenApiKey, config.qwenApiKey.trim()),
      prefs.setString(_asrServerUrl, config.asrServerUrl.trim()),
      prefs.setString(_qwenTtsUrl, config.qwenTtsUrl.trim()),
      prefs.setString(_qwenTtsApiKey, config.qwenTtsApiKey.trim()),
      prefs.setString(_qwenChatModel, config.qwenChatModel.trim()),
      prefs.remove(_legacyQwenAsrApiKey),
      prefs.remove(_legacyQwenAsrModel),
      prefs.setString(_qwenTtsModel, config.qwenTtsModel.trim()),
      prefs.setString(_qwenTtsVoice, config.qwenTtsVoice.trim()),
    ]);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_qwenBaseUrl),
      prefs.remove(_qwenApiKey),
      prefs.remove(_asrServerUrl),
      prefs.remove(_legacyQwenAsrApiKey),
      prefs.remove(_qwenTtsUrl),
      prefs.remove(_qwenTtsApiKey),
      prefs.remove(_qwenChatModel),
      prefs.remove(_legacyQwenAsrModel),
      prefs.remove(_qwenTtsModel),
      prefs.remove(_qwenTtsVoice),
    ]);
  }
}
