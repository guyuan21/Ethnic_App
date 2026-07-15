# 民族文化识别助手 Flutter App

当前版本面向民族服饰卡通人物图片，使用本地 ExecuTorch + XNNPACK 运行 ResNeSt50 INT8 QAT 模型。PP-OCRv5 移动模型在图片中级联搜索民族标题，OCR 仅作为辅助；本地分类模型最高置信度低于 70% 时不展示民族结果。图片不会上传到视觉模型 API。

聊天使用配置的千问 API；朗读优先使用腾讯云 TTS，失败时回退系统 TTS。语音转文字使用本地 sherpa-onnx + SenseVoice INT8。

## 运行

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File .\tool\download_sensevoice_model.ps1
flutter run
```

## 图片识别链路

```text
相机图片
  -> 修正 EXIF 方向
  -> 保持比例，将短边缩放到 256
  -> 中心裁剪 224 x 224
  -> RGB / 255
  -> ImageNet mean/std 标准化
  -> NCHW float32 [1, 3, 224, 224]
  -> Flutter MethodChannel
  -> Android ExecuTorch 1.3.1 / XNNPACK
  -> 56 类 logits
  -> softmax 与 70% 展示门限
```

应用首次启动时会把约 25 MiB 的 `.pte` 从 Flutter assets 复制到应用私有目录，随后复用该文件。模型完全离线运行。

OCR 使用 PP-OCRv5 mobile detection + recognition ONNX 模型。它依次搜索左上区域、整个上半区和整图；正常图未匹配到56个民族白名单时，再对水平镜像图执行同样的低成本到整图兜底。输入图片最长边先限制为 2048，检测输入最长边为 640，模型直接从 APK 的未压缩 assets 内存映射，避免在应用数据目录重复保存约 21 MiB OCR 模型。

## 关键文件

```text
lib/services/cartoon_classifier_service.dart
    图片预处理、标签、softmax 和 Flutter 原生调用

android/app/src/main/kotlin/com/example/app_flutter/ExecuTorchClassifierChannel.kt
    ExecuTorch 模型复制、加载和 XNNPACK 推理

android/app/src/main/kotlin/com/example/app_flutter/PpOcrV5Channel.kt
    PP-OCRv5 分区检测、文字识别、CTC 解码、民族白名单与镜像回退

lib/services/api_service.dart
    OCR、70% 门限、文化结果组装和问答入口

assets/model/resnest50_ethnic_int8_qat.pte
    56 类 ResNeSt50 INT8 QAT 部署模型

assets/model/resnest50_ethnic_int8_qat.json
    模型输入、类别顺序、大小和 SHA-256 元数据

assets/model/labels.txt
    56 类英文标签，顺序必须与模型输出完全一致
```

模型 SHA-256：

```text
7936076795ab0c6eb1ab6fd2462a02b94d9357baf5095dbdc36749c5826d44c4
```

## Android 依赖

Android 使用 Maven Central 的：

```kotlin
implementation("org.pytorch:executorch-android:1.3.1")
implementation("com.microsoft.onnxruntime:onnxruntime-android:1.23.2")
```

`.pte` 的导出版本和 Android ExecuTorch 运行时版本应保持一致。旧 `ethnic_model.tflite` 仅作为本地回退文件保留在源码目录中，不再由 `pubspec.yaml` 打进安装包，也没有运行时调用。

## 注意事项

- 仅 Android 接入了 ExecuTorch；Windows/Web 不提供本地图片分类。
- API 密钥不会通过 `dart-define` 默认写入 APK，必须安装后在隐藏配置页手动填写。
- SenseVoice 模型体积较大，首次获取源码后仍需按项目脚本准备。
- 真机发布前需要重点测试门巴族/彝族、水族/汉族等历史混淆场景，并记录推理耗时、内存和温升。
