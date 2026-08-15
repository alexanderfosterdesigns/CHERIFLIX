param(
    [string]$ApkPath = "build/app/outputs/flutter-apk/app-release.apk",
    [string[]]$ExpectedAbis = @("armeabi-v7a", "arm64-v8a", "x86_64"),
    [switch]$SkipBrandingGeneration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PathIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return $null
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "Running: $Executable $($Arguments -join ' ')" -ForegroundColor Cyan
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
    }
}

$flutterFromTooling = Resolve-PathIfExists -Path ".tooling/flutter/bin/flutter.bat"
$flutterExecutable = if ($flutterFromTooling) { $flutterFromTooling } else { "flutter" }

if (-not $SkipBrandingGeneration) {
    Invoke-CheckedCommand -Executable "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "tool/generate_android_tv_branding.ps1"
    )
}

Invoke-CheckedCommand -Executable $flutterExecutable -Arguments @("pub", "get")
Invoke-CheckedCommand -Executable $flutterExecutable -Arguments @(
    "build", "apk",
    "--release",
    "--target-platform", "android-arm,android-arm64,android-x64"
)

$verifyArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "tool/verify_android_apk.ps1",
    "-ApkPath", $ApkPath,
    "-ExpectedAbis", ($ExpectedAbis -join ",")
)
Invoke-CheckedCommand -Executable "powershell" -Arguments $verifyArgs

$aaptCandidates = Get-ChildItem -Path ".android-sdk/build-tools" -Recurse -Filter "aapt.exe" -File -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending
$aaptExecutable = if ($aaptCandidates.Count -gt 0) { $aaptCandidates[0].FullName } else { $null }

if (-not $aaptExecutable) {
    Write-Warning "aapt.exe not found under .android-sdk/build-tools. Skipping badging checks."
} else {
    $resolvedApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
    $badgingOutput = & $aaptExecutable dump badging $resolvedApkPath
    if ($LASTEXITCODE -ne 0) {
        throw "aapt badging check failed."
    }

    $labelLine = $badgingOutput | Where-Object { $_ -match "^application-label:'" } | Select-Object -First 1
    if (-not $labelLine -or $labelLine -notmatch "^application-label:'Cheriflix'$") {
        throw "Unexpected app label in APK badging. Expected 'Cheriflix'."
    }

    $applicationLine = $badgingOutput | Where-Object { $_ -match "^application:" } | Select-Object -First 1
    if (-not $applicationLine -or $applicationLine -notmatch "banner='[^']+'") {
        throw "APK badging did not report a launcher banner."
    }

    Write-Host "aapt badging checks passed (label + banner)." -ForegroundColor Green
}

$finalApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
Write-Host "Android TV release APK ready: $finalApkPath" -ForegroundColor Green
