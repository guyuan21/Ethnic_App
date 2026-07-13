# 民族文化识别助手 - Flutter App

当前版本固定使用本地 OCR 与 TFLite 识别卡通民族文化元素。最高置信度低于 70% 时提示重新拍摄，不调用视觉模型 API；聊天、语音识别和系统 TTS 失败后的联网朗读使用千问 API。

## 运行

```bash
flutter pub get
flutter run
```

## 关键文件

```text
lib/services/cartoon_classifier_service.dart  # TFLite 加载、图片预处理、推理
lib/services/api_service.dart                 # 识别结果组装和本地资料问答
lib/services/online_tts_service.dart          # 系统TTS失败后的千问联网朗读
lib/services/model_config_service.dart        # 千问聊天/ASR/TTS配置
assets/model/ethnic_model.tflite              # 本地模型
assets/model/labels.txt                       # 56 类标签
assets/culture_info.json                      # 文化资料
```

模型输入为 `[1, 224, 224, 3]` float32。App 会将图片中心裁剪、缩放到 `224x224`，并按 RGB `0..1` 归一化。

隐藏配置页可配置 `qwen3-asr-flash`、`qwen3-tts-flash` 及各自密钥；专项密钥留空时复用聊天密钥。

API 密钥不会通过 `dart-define` 打包进 APK，必须安装后在隐藏配置页手动填写。
