param(
    [string]$QwenBaseUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    [string]$QwenTtsUrl = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
    [string]$ChatModel = "qwen-turbo",
    [string]$TtsModel = "qwen3-tts-flash",
    [string]$TtsVoice = "Cherry",
    [ValidateSet("apk", "appbundle")]
    [string]$Target = "apk",
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "release"
)

$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot
try {
    Write-Host "Image recognition uses local OCR/TFLite only; results below 70% show a retry prompt." -ForegroundColor Cyan
    Write-Host "Speech recognition uses bundled sherpa-onnx + SenseVoice INT8 and needs no API key." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "tool\download_sensevoice_model.ps1")
    $logDir = Join-Path $PSScriptRoot "build_logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logPath = Join-Path $logDir ("flutter_build_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

    $flutterArgs = @(
        "build",
        $Target,
        "--$Mode",
        "--dart-define=QWEN_BASE_URL=$QwenBaseUrl",
        "--dart-define=QWEN_TTS_URL=$QwenTtsUrl",
        "--dart-define=QWEN_CHAT_MODEL=$ChatModel",
        "--dart-define=QWEN_TTS_MODEL=$TtsModel",
        "--dart-define=QWEN_TTS_VOICE=$TtsVoice"
    )
    if ($Target -eq "apk") {
        $flutterArgs += @(
            "--target-platform=android-arm,android-arm64",
            "--split-per-abi"
        )
    }

    Write-Host "API keys are not packaged; configure them manually after installation." -ForegroundColor Cyan
    Write-Host "Running: flutter $($flutterArgs -join ' ')" -ForegroundColor DarkGray
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & flutter @flutterArgs 2>&1 | Tee-Object -FilePath $logPath
        $flutterExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($flutterExitCode -ne 0) {
        Write-Host "Build log saved to: $logPath" -ForegroundColor Yellow
        throw "flutter build failed with exit code $flutterExitCode"
    }
    Write-Host "Build log saved to: $logPath" -ForegroundColor DarkGray
} finally {
    Pop-Location
}
