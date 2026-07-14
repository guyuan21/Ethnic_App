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
  final _qwenChatModelController = TextEditingController();
  final _tencentAppIdController = TextEditingController();
  final _tencentSecretIdController = TextEditingController();
  final _tencentSecretKeyController = TextEditingController();
  final _tencentTokenController = TextEditingController();
  final _tencentVoiceTypeController = TextEditingController();

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
    for (final controller in <TextEditingController>[
      _qwenBaseUrlController,
      _qwenApiKeyController,
      _qwenChatModelController,
      _tencentAppIdController,
      _tencentSecretIdController,
      _tencentSecretKeyController,
      _tencentTokenController,
      _tencentVoiceTypeController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ModelConfigService.load();
    if (!mounted) return;
    _apply(config);
    setState(() => _loading = false);
  }

  void _apply(ModelRuntimeConfig config) {
    _qwenBaseUrlController.text = config.qwenBaseUrl;
    _qwenApiKeyController.text = config.qwenApiKey;
    _qwenChatModelController.text = config.qwenChatModel;
    _tencentAppIdController.text = config.tencentAppId;
    _tencentSecretIdController.text = config.tencentSecretId;
    _tencentSecretKeyController.text = config.tencentSecretKey;
    _tencentTokenController.text = config.tencentToken;
    _tencentVoiceTypeController.text = config.tencentVoiceType;
  }

  ModelRuntimeConfig _readConfig() {
    return ModelRuntimeConfig(
      qwenBaseUrl: _qwenBaseUrlController.text,
      qwenApiKey: _qwenApiKeyController.text,
      qwenChatModel: _qwenChatModelController.text,
      tencentAppId: _tencentAppIdController.text,
      tencentSecretId: _tencentSecretIdController.text,
      tencentSecretKey: _tencentSecretKeyController.text,
      tencentToken: _tencentTokenController.text,
      tencentVoiceType: _tencentVoiceTypeController.text,
    );
  }

  String? _validate() {
    final appId = _tencentAppIdController.text.trim();
    if (appId.isNotEmpty && int.tryParse(appId) == null) {
      return '腾讯云 AppID 必须是整数。';
    }

    final secretId = _tencentSecretIdController.text.trim();
    final secretKey = _tencentSecretKeyController.text.trim();
    if (secretId.isEmpty != secretKey.isEmpty) {
      return 'SecretId 和 SecretKey 需要同时填写。';
    }

    final voiceType = int.tryParse(_tencentVoiceTypeController.text.trim());
    if (voiceType == null || voiceType < 0) {
      return 'VoiceType 必须是有效的非负整数。';
    }
    return null;
  }

  Future<void> _save() async {
    final validationError = _validate();
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }

    setState(() => _saving = true);
    try {
      await ModelConfigService.save(_readConfig());
      if (!mounted) return;
      _showMessage('配置已保存。');
    } catch (error) {
      if (!mounted) return;
      _showMessage('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreDefaults() async {
    setState(() => _saving = true);
    try {
      await ModelConfigService.clear();
      if (!mounted) return;
      setState(() => _apply(ModelRuntimeConfig.packagedDefaults()));
      _showMessage('已恢复默认配置并清除密钥。');
    } catch (error) {
      if (!mounted) return;
      _showMessage('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
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
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _showKeys,
                        onChanged: (value) => setState(() => _showKeys = value),
                        title: const Text('显示接口密钥'),
                      ),
                      _Section(
                        title: '聊天模型',
                        subtitle: '用于联网聊天回答。聊天密钥不会用于语音合成。',
                        children: [
                          _Field(
                            controller: _qwenBaseUrlController,
                            label: '聊天接口地址',
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
                            controller: _qwenChatModelController,
                            label: '聊天模型',
                            hint: 'qwen-turbo',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _Section(
                        title: '腾讯云文字朗读',
                        subtitle: '设备系统朗读不可用时启用；不再提供其他 TTS 服务商切换。',
                        children: [
                          _Field(
                            controller: _tencentAppIdController,
                            label: 'AppID（可选）',
                            keyboardType: TextInputType.number,
                          ),
                          _Field(
                            controller: _tencentSecretIdController,
                            label: 'SecretId',
                            obscureText: !_showKeys,
                          ),
                          _Field(
                            controller: _tencentSecretKeyController,
                            label: 'SecretKey',
                            obscureText: !_showKeys,
                          ),
                          _Field(
                            controller: _tencentTokenController,
                            label: 'STS Token（临时凭证时填写）',
                            obscureText: !_showKeys,
                          ),
                          _Field(
                            controller: _tencentVoiceTypeController,
                            label: '音色 VoiceType',
                            hint: '1001',
                            keyboardType: TextInputType.number,
                          ),
                        ],
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

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            ...children,
          ],
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
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}
