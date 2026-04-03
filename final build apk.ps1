param(
    [string]$DestinationDir = "D:\code-files\flask-proj\Sir_Amol\main_flask_app_v2.1.9\app\static\downloads\android",
    [string]$OutputBaseName = "flask_call_app"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-PubspecValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $pattern = "^\s*$Key\s*:\s*(.+)$"
    $line = Get-Content -Path $Path | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if (-not $line) {
        throw "Could not find '$Key' in $Path"
    }

    if ($line -match $pattern) {
        $value = $Matches[1].Trim()
        $value = $value.Trim("'")
        $value = $value.Trim('"')
        return $value
    }

    throw "Could not parse '$Key' from $Path"
}

function ConvertTo-SafeFilePart {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '[<>:"/\\|?*\s]+', '-')
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Final Build APK (Release + Copy)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $scriptDir

if (-not (Test-CommandAvailable -Name "flutter")) {
    throw "Flutter not found in PATH. Please install Flutter or add it to PATH."
}

$pubspecPath = Join-Path $scriptDir "pubspec.yaml"
if (-not (Test-Path -Path $pubspecPath)) {
    throw "pubspec.yaml not found in project root."
}

$rawVersion = Get-PubspecValue -Path $pubspecPath -Key "version"

$versionName = $rawVersion
if ($rawVersion -match '^([^+]+)\+(\d+)$') {
    $versionName = $Matches[1]
}

$buildNumberSuffix = ""
if ($rawVersion -match '^([^+]+)\+(\d+)$') {
    $buildNumberSuffix = "_build$($Matches[2])"
}

$safeAppName = ConvertTo-SafeFilePart -Value $OutputBaseName
$safeVersion = ConvertTo-SafeFilePart -Value $versionName

$targetFileName = "${safeAppName}_${safeVersion}${buildNumberSuffix}.apk"

Write-Host "Output base name: $OutputBaseName" -ForegroundColor Green
Write-Host "Version: $rawVersion" -ForegroundColor Green
Write-Host "Target file: $targetFileName" -ForegroundColor Green
Write-Host "Destination: $DestinationDir" -ForegroundColor Green
Write-Host ""

Write-Host "Running Flutter release build..." -ForegroundColor Yellow
flutter clean
flutter pub get
flutter build apk --release

$sourceApkPath = Join-Path $scriptDir "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -Path $sourceApkPath)) {
    throw "Release APK not found at expected path: $sourceApkPath"
}

if (-not (Test-Path -Path $DestinationDir)) {
    New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
}

$destinationApkPath = Join-Path $DestinationDir $targetFileName
Copy-Item -Path $sourceApkPath -Destination $destinationApkPath -Force

$apkSizeMB = [Math]::Round((Get-Item -Path $destinationApkPath).Length / 1MB, 2)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build and transfer complete" -ForegroundColor Green
Write-Host "Saved APK: $destinationApkPath" -ForegroundColor Green
Write-Host "Size: $apkSizeMB MB" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan