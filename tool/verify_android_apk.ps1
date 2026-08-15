param(
    [string]$ApkPath = "build/app/outputs/flutter-apk/app-release.apk",
    [string[]]$ExpectedAbis = @("armeabi-v7a", "arm64-v8a", "x86_64"),
    [string[]]$RequiredCoreLibraries = @("libapp.so", "libflutter.so")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK file does not exist: $ApkPath"
}

$normalizedExpectedAbis = @(
    $ExpectedAbis |
        ForEach-Object { $_ -split "," } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }
)

$normalizedRequiredCoreLibraries = @(
    $RequiredCoreLibraries |
        ForEach-Object { $_ -split "," } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }
)

if ($normalizedExpectedAbis.Count -eq 0) {
    throw "Expected ABI list is empty."
}

if ($normalizedRequiredCoreLibraries.Count -eq 0) {
    throw "Required core library list is empty."
}

$resolvedApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
$zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedApkPath)

try {
    $libraryEntries = @(
        $zip.Entries |
            Where-Object {
                $_.FullName.StartsWith("lib/") -and
                $_.FullName.EndsWith(".so")
            }
    )

    if ($libraryEntries.Count -eq 0) {
        throw "No native libraries were found under lib/*/*.so in: $resolvedApkPath"
    }

    $abisInApk = @(
        $libraryEntries |
            ForEach-Object { ($_.FullName -split "/")[1] } |
            Sort-Object -Unique
    )

    $entryLookup = @{}
    foreach ($entry in $libraryEntries) {
        $entryLookup[$entry.FullName] = $true
    }

    $failures = New-Object System.Collections.Generic.List[string]

    foreach ($expectedAbi in $normalizedExpectedAbis) {
        if (-not ($abisInApk -contains $expectedAbi)) {
            $failures.Add("Expected ABI '$expectedAbi' was not packaged in the APK.")
        }
    }

    foreach ($abi in $abisInApk) {
        foreach ($requiredLibrary in $normalizedRequiredCoreLibraries) {
            $requiredPath = "lib/$abi/$requiredLibrary"
            if (-not $entryLookup.ContainsKey($requiredPath)) {
                $failures.Add("ABI '$abi' is missing required runtime library '$requiredLibrary'.")
            }
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host "APK validation failed for: $resolvedApkPath" -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host "- $failure" -ForegroundColor Red
        }
        exit 1
    }

    Write-Host "APK validation passed for: $resolvedApkPath" -ForegroundColor Green
    Write-Host "Packaged ABIs: $($abisInApk -join ", ")" -ForegroundColor Green
}
finally {
    $zip.Dispose()
}
