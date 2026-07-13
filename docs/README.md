# Docs

The app now runs cartoon image recognition locally in Flutter with TFLite.

There is no backend startup step and no cloud vision API call.
Chat answers and ASR still use the configured Qwen/OpenAI-compatible API.

Main files:

```text
app_flutter/lib/services/cartoon_classifier_service.dart
app_flutter/lib/services/api_service.dart
app_flutter/assets/model/ethnic_model.tflite
app_flutter/assets/model/labels.txt
```
