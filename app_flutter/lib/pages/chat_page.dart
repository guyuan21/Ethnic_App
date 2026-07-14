import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import '../services/online_tts_service.dart';

class ChatPage extends StatefulWidget {
  final Map<String, dynamic>? initialContext;

  const ChatPage({super.key, this.initialContext});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class ChatMessage {
  final String role;
  final String text;

  ChatMessage({required this.role, required this.text});
}

class _RecordingTarget {
  final String path;
  final String formatName;

  const _RecordingTarget({required this.path, required this.formatName});
}

class _ChatPageState extends State<ChatPage> {
  static const Map<String, dynamic> _emptyChatContext = {
    'results': <dynamic>[],
  };
  static const String _pendingAnswerText = '正在结合文化资料整理回答，马上就好...';
  static const Duration _maxRecordingDuration = Duration(seconds: 20);
  static const Duration _minAutoRecordingDuration =
      Duration(milliseconds: 1200);
  static const Duration _minManualRecordingDuration =
      Duration(milliseconds: 700);
  // 1.6 seconds was too aggressive for natural Chinese pauses on TV/tablet
  // microphones. Keep a longer pause while still auto-submitting promptly.
  static const Duration _silenceAutoStopDuration = Duration(milliseconds: 2200);
  static const Duration _noiseCalibrationDuration = Duration(milliseconds: 450);
  static const Duration _amplitudePollInterval = Duration(milliseconds: 180);
  static const int _recordingSampleRate = 16000;
  static const int _recordingBitRate = 32000;

  final TextEditingController _controller = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  bool _loading = false;
  bool _recording = false;
  bool _transcribing = false;
  bool _ttsReady = false;
  String _ttsLanguage = 'zh-CN';
  String _speechStatus = '可以文字提问，也可以录音提问';
  Timer? _recordingTimer;
  Timer? _silenceWatchdog;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  bool _stoppingRecording = false;
  bool _submittingRecording = false;
  bool _autoReadEnabled = true;
  bool _hasHeardVoice = false;
  String? _activeRecordingPath;
  String _activeRecordingFormat = '';
  DateTime? _recordingStartedAt;
  DateTime? _lastVoiceAt;
  double _noiseFloorDb = -65.0;
  double _adaptiveVoiceThresholdDb = -52.0;
  int _noiseCalibrationSamples = 0;
  int _consecutiveVoiceFrames = 0;
  String? _lastSpeechText;
  bool _onlineTtsFallbackActive = false;
  Completer<void>? _ttsStartCompleter;

  bool get _hasRecognizedContext {
    final results = widget.initialContext?['results'];
    return results is List && results.isNotEmpty && results.first is Map;
  }

  Map<String, dynamic> get _chatContext {
    if (_hasRecognizedContext) return widget.initialContext!;
    return _emptyChatContext;
  }

  String get _currentCultureName {
    final results = widget.initialContext?['results'];
    if (results is List && results.isNotEmpty && results.first is Map) {
      return (results.first['name'] ?? '当前文化元素').toString();
    }
    return '民族文化';
  }

  String get _headerText {
    if (_hasRecognizedContext) {
      return '围绕「$_currentCultureName」继续提问';
    }
    return '直接向文化讲解助手提问';
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      ApiService.prewarmOfflineAsr().catchError((Object _) {
        // The first real transcription retries and displays a useful error.
        // Loading only after entering chat avoids reserving hundreds of MB
        // while the user is using image recognition on low-memory devices.
      }),
    );
    _tts.setStartHandler(() {
      final completer = _ttsStartCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
      if (!mounted) return;
      setState(() {
        _speechStatus = '正在朗读回答';
      });
    });
    _tts.setCompletionHandler(() {
      _lastSpeechText = null;
      if (!mounted) return;
      setState(() {
        _speechStatus = '朗读完成，可继续录音或文字追问';
      });
    });
    _tts.setErrorHandler((message) {
      final startCompleter = _ttsStartCompleter;
      if (startCompleter != null && !startCompleter.isCompleted) {
        startCompleter.completeError(Exception(message));
        return;
      }
      _ttsReady = false;
      final fallbackText = _lastSpeechText;
      if (fallbackText != null &&
          fallbackText.isNotEmpty &&
          _autoReadEnabled &&
          !_onlineTtsFallbackActive) {
        unawaited(_speakOnline(fallbackText));
      }
    });
    _configureTts();
    _messages.add(
      ChatMessage(
        role: 'assistant',
        text: _hasRecognizedContext
            ? '我已经带上「$_currentCultureName」的识别结果了，可以继续问。'
            : '你好，可以直接问我民族文化相关问题。',
      ),
    );
  }

  Future<void> _configureTts() async {
    try {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final engines = await _tts.getEngines;
          if (engines is List) {
            if (engines.isNotEmpty) {
              final engineNames = engines.map((engine) => engine.toString());
              final preferred = engineNames.firstWhere(
                (engine) {
                  final lower = engine.toLowerCase();
                  return lower.contains('google') ||
                      lower.contains('iflytek') ||
                      lower.contains('huawei') ||
                      lower.contains('samsung') ||
                      lower.contains('baidu');
                },
                orElse: () => engineNames.first,
              );
              await _tts.setEngine(preferred);
            }
          }
        } catch (_) {
          // Some Android panels expose no selectable engine even when TTS works.
        }

        try {
          await _tts.setQueueMode(0);
        } catch (_) {
          // Queue mode is Android-only and may be unavailable on some builds.
        }
      }

      final zhCnAvailable = await _tts.isLanguageAvailable('zh-CN');
      if (zhCnAvailable == true || zhCnAvailable.toString() == 'true') {
        await _tts.setLanguage('zh-CN');
        _ttsLanguage = 'zh-CN';
      } else {
        await _tts.setLanguage('zh');
        _ttsLanguage = 'zh';
      }
      _ttsReady = true;
    } catch (e) {
      _ttsReady = false;
      if (!mounted) return;
      setState(() {
        _speechStatus = '当前设备没有可用中文朗读引擎，请在系统设置中安装或启用文字转语音引擎。';
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _speak(String text) async {
    _lastSpeechText = text;
    var systemTtsSpoke = false;
    try {
      if (!_ttsReady) {
        await _configureTts();
      }
      if (_ttsReady) {
        await OnlineTtsService.instance.stop();
        await _tts.stop();
        try {
          await _tts.setLanguage(_ttsLanguage);
        } catch (_) {
          await _tts.setLanguage('zh');
        }
        await _tts.setVolume(1.0);
        await _tts.setSpeechRate(0.45);
        await _tts.setPitch(1.0);
        _ttsStartCompleter = Completer<void>();
        final result = await _tts.speak(text);
        if (result == 0 || result.toString() == '0') {
          throw Exception('系统 TTS 拒绝了朗读请求');
        }
        await _ttsStartCompleter!.future.timeout(
          const Duration(milliseconds: 2500),
        );
        _ttsStartCompleter = null;
        systemTtsSpoke = true;
        if (!mounted) return;
        setState(() {
          _speechStatus = '正在使用系统 TTS 朗读回答';
        });
      }
    } catch (_) {
      _ttsStartCompleter = null;
      _ttsReady = false;
    }

    if (systemTtsSpoke) return;
    await _speakOnline(text);
  }

  Future<void> _speakOnline(String text) async {
    if (_onlineTtsFallbackActive) return;
    _onlineTtsFallbackActive = true;
    try {
      await _tts.stop();
      if (!mounted) return;
      setState(() {
        _speechStatus = '系统 TTS 不可用，正在连接大模型 TTS';
      });
      await OnlineTtsService.instance.speak(text);
      if (!mounted) return;
      setState(() {
        _speechStatus = '正在使用大模型 TTS 朗读回答';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speechStatus = '系统与大模型 TTS 均不可用：$error';
      });
    } finally {
      _onlineTtsFallbackActive = false;
    }
  }

  Future<void> _sendQuestion(String question, {bool fromVoice = false}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty ||
        _loading ||
        _recording ||
        (_transcribing && !fromVoice)) {
      return;
    }

    final pendingIndex = _messages.length + 1;
    setState(() {
      _messages.add(ChatMessage(role: 'user', text: trimmed));
      _messages.add(ChatMessage(role: 'assistant', text: _pendingAnswerText));
      _loading = true;
      _controller.clear();
      _speechStatus = '正在整理回答';
    });
    _scrollToBottom();

    try {
      final answer = await ApiService.askQuestion(
        trimmed,
        context: _chatContext,
      );

      if (!mounted) return;
      setState(() {
        if (pendingIndex < _messages.length) {
          _messages[pendingIndex] =
              ChatMessage(role: 'assistant', text: answer);
        } else {
          _messages.add(ChatMessage(role: 'assistant', text: answer));
        }
        _speechStatus = '回答已生成，可继续录音或文字追问';
      });
      _scrollToBottom();
      if (_autoReadEnabled) {
        unawaited(_speak(answer));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechStatus = '回答失败，请检查网络后重试';
        final errorText =
            '暂时无法回答：$e\n\n请检查网络、聊天接口密钥和聊天模型。语音识别使用本地离线模型；图片识别使用本地TFLite，OCR仅辅助读取文字。';
        if (pendingIndex < _messages.length) {
          _messages[pendingIndex] =
              ChatMessage(role: 'assistant', text: errorText);
        } else {
          _messages.add(ChatMessage(role: 'assistant', text: errorText));
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startVoiceInput() async {
    if (_loading || _transcribing || _recording) return;

    if (kIsWeb) {
      setState(() {
        _speechStatus = '网页端暂不支持录音上传，请直接输入文字';
      });
      return;
    }

    try {
      await _tts.stop();
      _lastSpeechText = null;
      await OnlineTtsService.instance.stop();
      _recordingTimer?.cancel();
      _silenceWatchdog?.cancel();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _submittingRecording = false;
      _stoppingRecording = false;
      _hasHeardVoice = false;
      _activeRecordingPath = null;
      _activeRecordingFormat = '';
      _recordingStartedAt = null;
      _lastVoiceAt = null;
      _resetVadState();

      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _speechStatus = '麦克风权限未开启。请在系统设置中允许本应用使用麦克风。';
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final recordingTarget = await _startRecorder(tempDir.path);
      _activeRecordingPath = recordingTarget.path;
      _activeRecordingFormat = recordingTarget.formatName;
      _recordingStartedAt = DateTime.now();

      if (!mounted) return;
      setState(() {
        _recording = true;
        _transcribing = false;
        _controller.clear();
        _speechStatus = '正在录音，说完停顿一下会自动识别';
      });

      if (mounted) {
        setState(() {
          _speechStatus = '正在录音，说完停顿一下会自动识别';
        });
      }

      _startSilenceAutoStopWatch();

      _recordingTimer = Timer(_maxRecordingDuration, () {
        if (mounted && _recording && !_transcribing) {
          unawaited(_stopVoiceInput(auto: true));
        }
      });
    } catch (e) {
      try {
        await _audioRecorder.cancel();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _recording = false;
        _transcribing = false;
        _stoppingRecording = false;
        _submittingRecording = false;
        _hasHeardVoice = false;
        _speechStatus = '录音启动失败：$e';
      });
    }
  }

  Future<void> _stopVoiceInput(
      {bool auto = false, bool silence = false}) async {
    if ((!_recording && !_stoppingRecording) ||
        _transcribing ||
        _submittingRecording) {
      return;
    }

    _stoppingRecording = true;
    _recordingTimer?.cancel();
    _silenceWatchdog?.cancel();
    if (mounted) {
      setState(() {
        _speechStatus = silence
            ? '检测到说话结束，正在识别语音'
            : auto
                ? '录音已到最长时间，正在识别语音'
                : '正在结束录音并识别';
      });
    }

    await _submitRecordedVoice(auto: auto, stoppedBySilence: silence);
  }

  Future<_RecordingTarget> _startRecorder(String tempDirPath) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (!await _audioRecorder.isEncoderSupported(AudioEncoder.wav)) {
      throw StateError('当前设备无法录制离线识别所需的音频。');
    }
    final path = '$tempDirPath/culture_voice_$timestamp.wav';
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: _recordingBitRate,
        sampleRate: _recordingSampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    return _RecordingTarget(path: path, formatName: 'WAV');
  }

  void _startSilenceAutoStopWatch() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(_amplitudePollInterval)
        .listen(_handleRecordingAmplitude, onError: (_) {});
    _silenceWatchdog?.cancel();
    _silenceWatchdog = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _checkForSpeechEnd(),
    );
  }

  void _handleRecordingAmplitude(Amplitude amplitude) {
    if (!_recording || _transcribing || _stoppingRecording) return;
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return;

    final db = amplitude.current;
    if (!db.isFinite) return;
    final now = DateTime.now();
    final elapsed = now.difference(startedAt);

    if (elapsed < _noiseCalibrationDuration) {
      _noiseCalibrationSamples += 1;
      _noiseFloorDb = _noiseCalibrationSamples == 1
          ? db
          : (_noiseFloorDb * 0.78) + (db * 0.22);
      _adaptiveVoiceThresholdDb =
          (_noiseFloorDb + 9.0).clamp(-55.0, -32.0).toDouble();
      return;
    }

    final isVoice = db >= _adaptiveVoiceThresholdDb;
    if (isVoice) {
      _consecutiveVoiceFrames += 1;
      if (_consecutiveVoiceFrames < 2) return;
      final firstVoice = !_hasHeardVoice;
      _hasHeardVoice = true;
      _lastVoiceAt = now;
      if (firstVoice && mounted) {
        setState(() {
          _speechStatus = '正在录音，已听到说话，停顿后自动识别';
        });
      }
      return;
    }
    _consecutiveVoiceFrames = 0;

    // Follow slowly changing room noise without allowing speech peaks to push
    // the threshold upward. This adapts to microphones with different gain.
    if (!_hasHeardVoice || db < _adaptiveVoiceThresholdDb - 3.0) {
      _noiseFloorDb = (_noiseFloorDb * 0.94) + (db * 0.06);
      _adaptiveVoiceThresholdDb =
          (_noiseFloorDb + 9.0).clamp(-55.0, -32.0).toDouble();
    }
  }

  void _checkForSpeechEnd() {
    if (!_recording || _transcribing || _stoppingRecording) return;
    final startedAt = _recordingStartedAt;
    final lastVoiceAt = _lastVoiceAt;
    if (!_hasHeardVoice || startedAt == null || lastVoiceAt == null) return;
    final now = DateTime.now();
    if (now.difference(startedAt) < _minAutoRecordingDuration) return;
    if (now.difference(lastVoiceAt) >= _silenceAutoStopDuration) {
      unawaited(_stopVoiceInput(auto: true, silence: true));
    }
  }

  void _resetVadState() {
    _noiseFloorDb = -65.0;
    _adaptiveVoiceThresholdDb = -52.0;
    _noiseCalibrationSamples = 0;
    _consecutiveVoiceFrames = 0;
  }

  Future<void> _submitRecordedVoice({
    required bool auto,
    bool stoppedBySilence = false,
  }) async {
    if (_submittingRecording || _transcribing) return;

    _submittingRecording = true;
    _stoppingRecording = true;
    _recordingTimer?.cancel();
    _silenceWatchdog?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    if (mounted) {
      setState(() {
        _recording = false;
        _transcribing = true;
        _speechStatus = stoppedBySilence
            ? '检测到停顿，正在识别语音'
            : auto
                ? '录音结束，正在识别语音'
                : '正在识别整段录音';
      });
    }

    if (mounted) {
      setState(() {
        _speechStatus = stoppedBySilence ? '检测到停顿，正在上传识别语音' : '正在结束录音并上传识别';
      });
    }

    try {
      String? path;
      try {
        if (await _audioRecorder.isRecording()) {
          path = await _audioRecorder.stop();
        }
      } catch (_) {}
      path ??= _activeRecordingPath;

      if (path == null || !await File(path).exists()) {
        throw Exception('没有生成可识别的录音文件，请再试一次。');
      }

      final recordingDuration = _currentRecordingDuration();
      final minDuration =
          auto ? _minAutoRecordingDuration : _minManualRecordingDuration;
      if (recordingDuration < minDuration) {
        if (!mounted) return;
        setState(() {
          _speechStatus = '录音太短或只听到很短的声音，请按住麦克风说完整问题。';
        });
        return;
      }

      final fileLength = await File(path).length();
      if (fileLength < 512) {
        throw Exception('录音太短，请靠近麦克风再说一次。');
      }

      final words = (await ApiService.transcribeAudio(path)).trim();
      if (!mounted) return;

      if (words.isEmpty || _isLikelyAccidentalSpeech(words)) {
        setState(() {
          _speechStatus = '没有听到完整问题，可以再试一次或直接输入文字';
        });
        return;
      }

      setState(() {
        _controller.text = words;
        _controller.selection = TextSelection.collapsed(offset: words.length);
        _speechStatus = '已识别，正在发送';
        _transcribing = false;
      });
      await _sendQuestion(words, fromVoice: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechStatus = '录音识别失败：$e';
      });
    } finally {
      _activeRecordingPath = null;
      _activeRecordingFormat = '';
      _recordingStartedAt = null;
      _lastVoiceAt = null;
      _hasHeardVoice = false;
      _resetVadState();
      if (mounted) {
        setState(() {
          _recording = false;
          _stoppingRecording = false;
          _submittingRecording = false;
          if (!_loading) {
            _transcribing = false;
          }
        });
      }
    }
  }

  Duration _currentRecordingDuration() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  void _setAutoReadEnabled(bool enabled) {
    setState(() {
      _autoReadEnabled = enabled;
      _speechStatus = enabled ? '自动朗读已开启' : '自动朗读已关闭';
    });
    if (!enabled) {
      _lastSpeechText = null;
      _tts.stop();
      unawaited(OnlineTtsService.instance.stop());
    }
  }

  bool _isLikelyAccidentalSpeech(String text) {
    final normalized = text
        .replaceAll(RegExp(r'''[\s，。！？、,.!?;；:："“”‘’'「」『』（）()]'''), '')
        .trim();
    if (normalized.isEmpty) return true;
    const fillers = {
      '嗯',
      '恩',
      '啊',
      '呃',
      '额',
      '哦',
      '喂',
      '唉',
      '诶',
    };
    return fillers.contains(normalized);
  }

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.role == 'user';
    final isPending = msg.text == _pendingAnswerText;
    final bubbleColor =
        isUser ? const Color(0xFFFFD4C5) : const Color(0xFFF1F3F2);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bubbleMaxWidth = (screenWidth * (isUser ? 0.76 : 0.86))
        .clamp(220.0, isUser ? 360.0 : 460.0)
        .toDouble();

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isPending
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _pendingAnswerText,
                      style: TextStyle(height: 1.45),
                    ),
                  ),
                ],
              )
            : SelectableText(
                msg.text,
                style: const TextStyle(fontSize: 15.5, height: 1.55),
              ),
      ),
    );
  }

  Widget _buildSuggestion(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: (_loading || _recording || _transcribing)
          ? null
          : () => _sendQuestion(text),
    );
  }

  List<String> get _suggestions {
    if (_hasRecognizedContext) {
      return const [
        '这个文化元素有什么特点？',
        '它和哪些节日有关？',
        '有哪些文化寓意？',
        '用适合小朋友听懂的话介绍一下',
      ];
    }
    return const [
      '介绍一个有代表性的民族节日',
      '民族服饰通常怎么看特点？',
      '讲一个适合小朋友听的文化故事',
      '纹样和器物有什么文化寓意？',
    ];
  }

  Color _speechStatusColor(BuildContext context) {
    if (_speechStatus.contains('失败') ||
        _speechStatus.contains('权限') ||
        _speechStatus.contains('不可用')) {
      return Colors.deepOrange;
    }
    if (_recording) return const Color(0xFF2F6F73);
    if (_transcribing || _loading) return const Color(0xFF6B5B95);
    return Colors.black.withAlpha(150);
  }

  IconData get _speechStatusIcon {
    if (_recording) return Icons.mic;
    if (_transcribing) return Icons.graphic_eq;
    if (_loading) return Icons.hourglass_top;
    if (_speechStatus.contains('失败') || _speechStatus.contains('权限')) {
      return Icons.info_outline;
    }
    return Icons.chat_bubble_outline;
  }

  Widget _buildSpeechStatus() {
    final color = _speechStatusColor(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        children: [
          Icon(_speechStatusIcon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _speechStatus,
              style: TextStyle(color: color, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _silenceWatchdog?.cancel();
    _amplitudeSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _tts.stop();
    unawaited(OnlineTtsService.instance.stop());
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _transcribing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('了解更多'),
        actions: [
          IconButton(
            tooltip: _autoReadEnabled ? '关闭自动朗读' : '开启自动朗读',
            onPressed: () {
              _setAutoReadEnabled(!_autoReadEnabled);
            },
            icon: Icon(
              _autoReadEnabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  _headerText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _suggestions.map(_buildSuggestion).toList(),
                    ),
                    const SizedBox(height: 12),
                    ..._messages.map(_buildMessage),
                    if (_loading) const SizedBox(height: 4),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSpeechStatus(),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            tooltip: _recording ? '停止录音并识别' : '录音提问',
                            onPressed: busy
                                ? null
                                : (_recording
                                    ? () => _stopVoiceInput()
                                    : _startVoiceInput),
                            icon: Icon(_recording ? Icons.stop : Icons.mic),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 3,
                              enabled: !busy && !_recording,
                              textInputAction: TextInputAction.send,
                              decoration: const InputDecoration(
                                hintText: '输入你的问题',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: _sendQuestion,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: '发送',
                            onPressed: (busy || _recording)
                                ? null
                                : () => _sendQuestion(_controller.text),
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
