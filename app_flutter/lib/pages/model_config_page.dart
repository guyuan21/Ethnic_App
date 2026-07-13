import 'package:flutter/material.dart';

import '../services/model_config_service.dart';

class ModelConfigPage extends StatefulWidget {
  const ModelConfigPage({super.key});

  @override
  State<ModelConfigPage> createState() => _ModelConfigPageState();
}

class _ModelConfigPageState extends State<ModelConfigPage> {
  final _qwenBaseUrlController = TextEditingController();
  final _qwenApiKeyController = TextEditingController();
  final _qwenAsrApiKeyController = TextEditingController();
  final _qwenTtsUrlController = TextEditingController();
  final _qwenTtsApiKeyController = TextEditingController();
  final _qwenChatModelController = TextEditingController();
  final _qwenAsrModelController = TextEditingController();
  final _qwenTtsModelController = TextEditingController();
  final _qwenTtsVoiceController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _showKeys = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qwenBaseUrlController.dispose();
    _qwenApiKeyController.dispose();
    _qwenAsrApiKeyController.dispose();
    _qwenTtsUrlController.dispose();
    _qwenTtsApiKeyController.dispose();
    _qwenChatModelController.dispose();
    _qwenAsrModelController.dispose();
    _qwenTtsModelController.dispose();
    _qwenTtsVoiceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ModelConfigService.load();
    if (!mounted) return;
    _apply(config);
    setState(() {
      _loading = false;
    });
  }

  void _apply(ModelRuntimeConfig config) {
    _qwenBaseUrlController.text = config.qwenBaseUrl;
    _qwenApiKeyController.text = config.qwenApiKey;
    _qwenAsrApiKeyController.text = config.qwenAsrApiKey;
    _qwenTtsUrlController.text = config.qwenTtsUrl;
    _qwenTtsApiKeyController.text = config.qwenTtsApiKey;
    _qwenChatModelController.text = config.qwenChatModel;
    _qwenAsrModelController.text = config.qwenAsrModel;
    _qwenTtsModelController.text = config.qwenTtsModel;
    _qwenTtsVoiceController.text = config.qwenTtsVoice;
  }

  ModelRuntimeConfig _readConfig() {
    return ModelRuntimeConfig(
      qwenBaseUrl: _qwenBaseUrlController.text,
      qwenApiKey: _qwenApiKeyController.text,
      qwenAsrApiKey: _qwenAsrApiKeyController.text,
      qwenTtsUrl: _qwenTtsUrlController.text,
      qwenTtsApiKey: _qwenTtsApiKeyController.text,
      qwenChatModel: _qwenChatModelController.text,
      qwenAsrModel: _qwenAsrModelController.text,
      qwenTtsModel: _qwenTtsModelController.text,
      qwenTtsVoice: _qwenTtsVoiceController.text,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      await ModelConfigService.save(_readConfig());
      if (!mounted) return;
      _showMessage('已保存，聊天、语音识别和联网朗读将使用这组配置。');
    } catch (e) {
      if (!mounted) return;
      _showMessage('保存失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _restoreDefaults() async {
    setState(() {
      _saving = true;
    });
    try {
      await ModelConfigService.clear();
      final defaults = ModelRuntimeConfig.packagedDefaults();
      if (!mounted) return;
      setState(() {
        _apply(defaults);
      });
      _showMessage('已恢复为打包默认配置。');
    } catch (e) {
      if (!mounted) return;
      _showMessage('恢复失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型接口配置')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                    children: [
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('千问模型接口'),
                        subtitle: Text(
                          '图片固定使用本地OCR和TFLite，低于70%时提示重新拍摄。系统朗读不可用时使用联网TTS。各专项密钥留空时使用聊天密钥。',
                        ),
                      ),
                      SwitchListTile.adaptive(
                        value: _showKeys,
                        onChanged: (value) {
                          setState(() {
                            _showKeys = value;
                          });
                        },
                        title: const Text('显示接口密钥'),
                      ),
                      _Field(
                        controller: _qwenBaseUrlController,
                        label: '接口地址',
                        hint:
                            'https://dashscope.aliyuncs.com/compatible-mode/v1',
                        keyboardType: TextInputType.url,
                      ),
                      _Field(
                        controller: _qwenApiKeyController,
                        label: '聊天接口密钥',
                        obscureText: !_showKeys,
                      ),
                      _Field(
                        controller: _qwenAsrApiKeyController,
                        label: '语音识别接口密钥（可选，留空则使用聊天密钥）',
                        obscureText: !_showKeys,
                      ),
                      _Field(
                        controller: _qwenTtsApiKeyController,
                        label: '联网朗读接口密钥（可选，留空则使用聊天密钥）',
                        obscureText: !_showKeys,
                      ),
                      _Field(
                        controller: _qwenChatModelController,
                        label: '聊天模型',
                        hint: 'qwen-turbo',
                      ),
                      _Field(
                        controller: _qwenAsrModelController,
                        label: '语音识别模型',
                        hint: 'qwen3-asr-flash',
                      ),
                      _Field(
                        controller: _qwenTtsUrlController,
                        label: '联网朗读接口地址',
                        hint:
                            'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
                        keyboardType: TextInputType.url,
                      ),
                      _Field(
                        controller: _qwenTtsModelController,
                        label: '联网朗读模型',
                        hint: 'qwen3-tts-flash',
                      ),
                      _Field(
                        controller: _qwenTtsVoiceController,
                        label: '联网朗读音色',
                        hint: 'Cherry',
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('保存'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _restoreDefaults,
                            icon: const Icon(Icons.restore_outlined),
                            label: const Text('恢复默认'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        enableSuggestions: !obscureText,
        autocorrect: false,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
      ),
    );
  }
}
