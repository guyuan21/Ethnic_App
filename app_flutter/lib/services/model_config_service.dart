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
  static const String packagedQwenAsrModel = String.fromEnvironment(
    'QWEN_ASR_MODEL',
    defaultValue: 'qwen3-asr-flash',
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
  final String qwenAsrApiKey;
  final String qwenTtsUrl;
  final String qwenTtsApiKey;
  final String qwenChatModel;
  final String qwenAsrModel;
  final String qwenTtsModel;
  final String qwenTtsVoice;

  const ModelRuntimeConfig({
    required this.qwenBaseUrl,
    required this.qwenApiKey,
    required this.qwenAsrApiKey,
    required this.qwenTtsUrl,
    required this.qwenTtsApiKey,
    required this.qwenChatModel,
    required this.qwenAsrModel,
    required this.qwenTtsModel,
    required this.qwenTtsVoice,
  });

  factory ModelRuntimeConfig.packagedDefaults() {
    return const ModelRuntimeConfig(
      qwenBaseUrl: packagedQwenBaseUrl,
      // API keys are deliberately never accepted from dart-define. Users must
      // enter them after installation in the hidden local configuration page.
      qwenApiKey: '',
      qwenAsrApiKey: '',
      qwenTtsUrl: packagedQwenTtsUrl,
      qwenTtsApiKey: '',
      qwenChatModel: packagedQwenChatModel,
      qwenAsrModel: packagedQwenAsrModel,
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
  static const _qwenAsrApiKey = 'model_config.qwen_asr_api_key';
  static const _qwenTtsUrl = 'model_config.qwen_tts_url';
  static const _qwenTtsApiKey = 'model_config.qwen_tts_api_key';
  static const _qwenChatModel = 'model_config.qwen_chat_model';
  static const _qwenAsrModel = 'model_config.qwen_asr_model';
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
      qwenAsrApiKey:
          read(_qwenAsrApiKey, defaults.qwenAsrApiKey, allowEmpty: true),
      qwenTtsUrl: read(_qwenTtsUrl, defaults.qwenTtsUrl),
      qwenTtsApiKey:
          read(_qwenTtsApiKey, defaults.qwenTtsApiKey, allowEmpty: true),
      qwenChatModel: read(_qwenChatModel, defaults.qwenChatModel),
      qwenAsrModel: read(_qwenAsrModel, defaults.qwenAsrModel),
      qwenTtsModel: read(_qwenTtsModel, defaults.qwenTtsModel),
      qwenTtsVoice: read(_qwenTtsVoice, defaults.qwenTtsVoice),
    );
  }

  static Future<void> save(ModelRuntimeConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_qwenBaseUrl, config.qwenBaseUrl.trim()),
      prefs.setString(_qwenApiKey, config.qwenApiKey.trim()),
      prefs.setString(_qwenAsrApiKey, config.qwenAsrApiKey.trim()),
      prefs.setString(_qwenTtsUrl, config.qwenTtsUrl.trim()),
      prefs.setString(_qwenTtsApiKey, config.qwenTtsApiKey.trim()),
      prefs.setString(_qwenChatModel, config.qwenChatModel.trim()),
      prefs.setString(_qwenAsrModel, config.qwenAsrModel.trim()),
      prefs.setString(_qwenTtsModel, config.qwenTtsModel.trim()),
      prefs.setString(_qwenTtsVoice, config.qwenTtsVoice.trim()),
    ]);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_qwenBaseUrl),
      prefs.remove(_qwenApiKey),
      prefs.remove(_qwenAsrApiKey),
      prefs.remove(_qwenTtsUrl),
      prefs.remove(_qwenTtsApiKey),
      prefs.remove(_qwenChatModel),
      prefs.remove(_qwenAsrModel),
      prefs.remove(_qwenTtsModel),
      prefs.remove(_qwenTtsVoice),
    ]);
  }
}
