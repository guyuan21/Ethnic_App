# Ethnic Culture Cartoon Recognition App

This project is now a Flutter app with local TFLite image recognition.

Current behavior:

- Recognizes ethnic-costume cartoon character images only; rejects totems, standalone patterns, buildings, artifacts, and real-person photos.
- Uses `app_flutter/assets/model/ethnic_model.tflite`.
- Uses `app_flutter/assets/model/labels.txt` for the 56 output classes.
- Uses local OCR/TFLite only; results below 70% show a retry prompt.
- Does not use a FastAPI backend.
- Chat uses the configured Qwen API. Online TTS fallback uses Tencent Cloud's Android SDK.
- Speech-to-text runs fully offline with sherpa-onnx and the SenseVoice multilingual INT8 model; recordings and transcripts are not sent to an ASR server.
- The hidden config page is still available from the home header with 5 taps and password `123456`.

Model details:

- Input: `[1, 224, 224, 3]`
- Input type: `float32`
- Preprocess: center crop, resize to `224x224`, RGB normalized to `0..1`
- Output: `[1, 56]`

Run:

```bash
cd app_flutter
flutter pub get
powershell -ExecutionPolicy Bypass -File .\tool\download_sensevoice_model.ps1
flutter run
```

Release build:

```bash
cd app_flutter
powershell -ExecutionPolicy Bypass -File .\tool\download_sensevoice_model.ps1
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

Optional dart defines for packaged defaults:

```bash
flutter build apk --release ^
  --dart-define=QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 ^
  --dart-define=QWEN_CHAT_MODEL=qwen-turbo
```

API keys are never accepted from `dart-define` or packaged into the APK. Enter the chat key and basic Tencent Cloud TTS credentials manually in the hidden device-local configuration page after installation. Offline ASR needs no key.

The SenseVoice INT8 ONNX model is about 228 MiB. It is ignored by Git because it exceeds GitHub's normal per-file limit, but the download script verifies the official model's size and SHA-256 before a local build. The resulting APK includes the model and can recognize speech without a network connection.

Verify:

```bash
cd app_flutter
flutter analyze
```

If replacing the model, update both source and packaged copies:

```text
model/ethnic_model.tflite
model/labels.txt
app_flutter/assets/model/ethnic_model.tflite
app_flutter/assets/model/labels.txt
```
