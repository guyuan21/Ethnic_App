# 民族文化识别助手 - Flutter App

当前版本面向民族服饰卡通人物图片，使用本地 TFLite 完成分类，中文 OCR 仅辅助读取文字；最高置信度低于 70% 时提示重新拍摄，不调用视觉模型 API。聊天使用千问 API，系统 TTS 失败后的联网朗读使用腾讯云 Android SDK。语音转文字固定使用本地 sherpa-onnx + SenseVoice INT8，录音不上传且不需要密钥。

## 运行

```bash
flutter pub get
powershell -ExecutionPolicy Bypass -File .\tool\download_sensevoice_model.ps1
flutter run
```

## 关键文件

```text
lib/services/cartoon_classifier_service.dart  # TFLite 加载、图片预处理、推理
lib/services/api_service.dart                 # OCR、结果组装、离线ASR入口和问答
lib/services/offline_asr_service.dart         # sherpa-onnx/SenseVoice后台识别与文本规范化
lib/services/online_tts_service.dart          # 系统TTS失败后的腾讯云联网朗读
lib/services/model_config_service.dart        # 千问聊天/腾讯云TTS配置
tool/download_sensevoice_model.ps1            # 下载并校验官方INT8模型
assets/asr/sensevoice/tokens.txt              # SenseVoice词表
assets/model/ethnic_model.tflite              # 本地模型
assets/model/labels.txt                       # 56 类标签
assets/culture_info.json                      # 文化资料
```

模型输入为 `[1, 224, 224, 3]` float32。App 会将图片中心裁剪、缩放到 `224x224`，并按 RGB `0..255` 输入；MobileNetV3 在模型内部完成归一化。

隐藏配置页只保存聊天配置和腾讯云 TTS 基础配置，不提供其他 TTS 服务商切换。语音识别不读取聊天或朗读密钥，也不调用 Fish/Qwen ASR。腾讯云凭证留空时不启用联网朗读；所有密钥在打包默认配置中均为空。

`model.int8.onnx` 约 228 MiB，超过 GitHub 普通仓库单文件限制，因此不提交到 Git；首次拉取源码后必须运行下载脚本。脚本会校验官方文件的大小和 SHA-256，本机生成的 APK 会包含模型，安装后可完全断网识别。

API 密钥不会通过 `dart-define` 打包进 APK，必须安装后在隐藏配置页手动填写。
