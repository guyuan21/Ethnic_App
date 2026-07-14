# SenseVoice INT8 assets

This directory is used by the Android offline ASR implementation.

Run the following command from `app_flutter` before building a fresh checkout:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\download_sensevoice_model.ps1
```

The script downloads the official
`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17-int8` model and verifies
its size and SHA-256. `model.int8.onnx` is intentionally ignored by Git
because the 228 MiB file exceeds GitHub's normal per-file limit. The model is
bundled into locally built Android APKs and ASR does not need a network
connection at runtime.
