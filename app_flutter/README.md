# 民族文化识别助手 - Flutter App

当前版本只识别民族服饰卡通人物图片，不识别图腾、独立纹样、建筑、器物或真人照片。识别固定使用本地服饰参考图库、中文 OCR 与 TFLite，最高置信度低于 70% 时提示重新拍摄，不调用视觉模型 API；聊天和系统 TTS 失败后的联网朗读使用千问 API，语音转文字使用 Fish S2 Pro Zero Gradio 服务器。

## 运行

```bash
flutter pub get
flutter run
```

## 关键文件

```text
lib/services/cartoon_classifier_service.dart  # TFLite 加载、图片预处理、推理
lib/services/api_service.dart                 # OCR、Gradio语音转文字、结果组装和问答
lib/services/local_reference_matcher_service.dart # 本地服饰卡通参考图库匹配
lib/services/online_tts_service.dart          # 系统TTS失败后的千问联网朗读
lib/services/model_config_service.dart        # 千问聊天/ASR/TTS配置
assets/model/ethnic_model.tflite              # 本地模型
assets/model/labels.txt                       # 56 类标签
assets/culture_info.json                      # 文化资料
```

模型输入为 `[1, 224, 224, 3]` float32。App 会将图片中心裁剪、缩放到 `224x224`，并按 RGB `0..1` 归一化。

隐藏配置页可配置 Fish S2 Pro Zero 语音识别服务器地址，以及 `qwen3-tts-flash` 朗读模型和密钥；朗读密钥留空时复用聊天密钥。

API 密钥不会通过 `dart-define` 打包进 APK，必须安装后在隐藏配置页手动填写。
