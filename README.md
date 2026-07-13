# Ethnic Culture Cartoon Recognition App

This project is now a Flutter app with local TFLite image recognition.

Current behavior:

- Recognizes ethnic-costume cartoon character images only; rejects totems, standalone patterns, buildings, artifacts, and real-person photos.
- Uses `app_flutter/assets/model/ethnic_model.tflite`.
- Uses `app_flutter/assets/model/labels.txt` for the 56 output classes.
- Uses local OCR/TFLite only; results below 70% show a retry prompt.
- Does not use a FastAPI backend.
- Chat and online TTS fallback use configured Qwen APIs.
- Speech-to-text uploads recordings to the public Fish S2 Pro Zero Gradio Space.
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
flutter run
```

Release build:

```bash
cd app_flutter
flutter build apk --release
```

Optional dart defines for packaged defaults:

```bash
flutter build apk --release ^
  --dart-define=QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 ^
  --dart-define=QWEN_CHAT_MODEL=qwen-turbo ^
  --dart-define=ASR_SERVER_URL=https://artificialguybr-fish-s2-pro-zero.hf.space ^
  --dart-define=QWEN_TTS_MODEL=qwen3-tts-flash ^
  --dart-define=QWEN_TTS_VOICE=Cherry
```

API keys are never accepted from `dart-define` or packaged into the APK. Enter the chat, ASR, and TTS keys manually in the hidden device-local configuration page after installation.

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
