param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$appRoot = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $appRoot "assets\asr\sensevoice"
$repoBase = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"

$files = @(
    @{
        Name = "model.int8.onnx"
        Url = "$repoBase/model.int8.onnx"
        Bytes = 239233841
        Sha256 = "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
    },
    @{
        Name = "tokens.txt"
        Url = "$repoBase/tokens.txt"
        Bytes = 315894
        Sha256 = "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"
    }
)

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

foreach ($item in $files) {
    $target = Join-Path $targetDir $item.Name
    $temporary = "$target.download"

    $isValid = $false
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        $file = Get-Item -LiteralPath $target
        $isValid = $file.Length -eq $item.Bytes
        if ($isValid -and $item.Sha256) {
            $isValid = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $item.Sha256
        }
    }
    if ($isValid) {
        Write-Host "$($item.Name) is already valid."
        continue
    }

    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    Write-Host "Downloading $($item.Name)..."
    & curl.exe -L --fail --retry 4 --retry-delay 3 --output $temporary $item.Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $($item.Name)"
    }

    $download = Get-Item -LiteralPath $temporary
    if ($download.Length -ne $item.Bytes) {
        throw "File size mismatch for $($item.Name): expected $($item.Bytes), got $($download.Length)"
    }
    if ($item.Sha256) {
        $actualHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $item.Sha256) {
            throw "SHA-256 mismatch for $($item.Name)"
        }
    }

    Move-Item -LiteralPath $temporary -Destination $target -Force
    Write-Host "Verified $($item.Name)."
}

Write-Host "SenseVoice INT8 model is ready in $targetDir"
