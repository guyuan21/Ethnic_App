import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'chat_page.dart';
import 'model_config_page.dart';
import 'result_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _configPassword = '123456';

  final ImagePicker _picker = ImagePicker();
  bool _loading = false;
  String _loadingMessage = '';
  int _configTapCount = 0;
  DateTime? _lastConfigTapAt;

  @override
  void initState() {
    super.initState();
    unawaited(
      ApiService.prewarmLocalCostumeMatcher().catchError((Object _) {
        // Prewarming is optional. Recognition will surface a useful error if
        // the model is genuinely unavailable when the user selects an image.
      }),
    );
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
        requestFullMetadata: false,
      );

      if (pickedFile == null) return;

      setState(() {
        _loading = true;
        _loadingMessage = '正在分析图片';
      });
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final result = await ApiService.recognizeImage(pickedFile);

      if (!mounted) return;
      setState(() {
        _loadingMessage = '识别完成，正在生成文化卡片';
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            imageFile: pickedFile,
            result: result,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  Future<void> _handleConfigTap() async {
    final now = DateTime.now();
    final lastTap = _lastConfigTapAt;
    if (lastTap == null ||
        now.difference(lastTap) > const Duration(seconds: 3)) {
      _configTapCount = 0;
    }
    _lastConfigTapAt = now;
    _configTapCount += 1;

    if (_configTapCount < 5) return;
    _configTapCount = 0;
    final unlocked = await _requestConfigPassword();
    if (!mounted || !unlocked) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ModelConfigPage()),
    );
  }

  Future<bool> _requestConfigPassword() async {
    final controller = TextEditingController();
    var errorText = '';

    try {
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return StatefulBuilder(
                builder: (context, setDialogState) {
                  void submit() {
                    if (controller.text.trim() == _configPassword) {
                      Navigator.of(dialogContext).pop(true);
                      return;
                    }
                    setDialogState(() {
                      errorText = '密码不正确';
                    });
                  }

                  return AlertDialog(
                    title: const Text('配置入口密码'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: '请输入密码',
                        errorText: errorText.isEmpty ? null : errorText,
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: submit,
                        child: const Text('进入'),
                      ),
                    ],
                  );
                },
              );
            },
          ) ??
          false;
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    const cameraLabel = kIsWeb ? '拍照/选择图片' : '拍照识别';

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleConfigTap,
                      child: const _HeroPanel(),
                    ),
                    const SizedBox(height: 18),
                    _ActionTile(
                      icon: Icons.photo_camera_outlined,
                      title: cameraLabel,
                      subtitle: '现场拍摄民族服饰卡通人物',
                      color: const Color(0xFFB84A39),
                      onTap: _loading
                          ? null
                          : () => _pickAndRecognize(ImageSource.camera),
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.photo_library_outlined,
                      title: '上传图片识别',
                      subtitle: '从相册选择民族服饰卡通图片',
                      color: const Color(0xFF2F6F73),
                      onTap: _loading
                          ? null
                          : () => _pickAndRecognize(ImageSource.gallery),
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.forum_outlined,
                      title: '问一问',
                      subtitle: '直接和民族文化讲解助手聊天',
                      color: const Color(0xFF6B5B95),
                      onTap: _loading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ChatPage(
                                    initialContext: {'results': <dynamic>[]},
                                  ),
                                ),
                              );
                            },
                    ),
                    const SizedBox(height: 22),
                    const _SafetyPanel(),
                  ],
                ),
              ),
            ),
            if (_loading)
              ColoredBox(
                color: Colors.black.withAlpha(46),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(
                            '本地模型正在识别民族服饰卡通图片',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _loadingMessage.isEmpty
                                ? '正在进行本地识别...'
                                : _loadingMessage,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '民族文化识别助手',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '拍照识别 · 文化卡片 · 语音问答',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black.withAlpha(140),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '识别民族服饰卡通图片，听懂背后的文化故事',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '仅支持民族服饰卡通人物图片，不识别图腾、纹样、建筑、器物或真人照片。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withAlpha(173),
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withAlpha(31),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black.withAlpha(148),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.black.withAlpha(102),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyPanel extends StatelessWidget {
  const _SafetyPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6E3DA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF2F6F73)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '本应用只识别民族服饰卡通图片，不根据真人外貌判断民族身份。识别结果仅供文化学习参考。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black.withAlpha(173),
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
