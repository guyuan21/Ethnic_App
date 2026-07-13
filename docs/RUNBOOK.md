# Runbook

## Start

```bash
cd app_flutter
flutter pub get
flutter run
```

## Recognition Flow

1. Pick or capture an image.
2. Decode locally in Flutter.
3. Center crop and resize to `224x224`.
4. Normalize RGB to `0..1`.
5. Run `ethnic_model.tflite`.
6. Map output index to `labels.txt`.
7. Build the result card from `culture_info.json`.

Chat and ASR still use the configured Qwen/OpenAI-compatible API. The hidden
config page is opened by tapping the home header 5 times and entering `123456`.

## Verify

```bash
cd app_flutter
flutter analyze
```
