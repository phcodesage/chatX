param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [int]$BuildNumber,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-VersionFromPubspec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PubspecContent
    )

    $match = [regex]::Match($PubspecContent, "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$")
    if (-not $match.Success) {
        throw "Could not find a valid version line in pubspec.yaml. Expected format: version: x.y.z+n"
    }

    $versionName = $match.Groups[1].Value
    $versionCode = if ($match.Groups[2].Success) { [int]$match.Groups[2].Value } else { 0 }

    return @{
        VersionName = $versionName
        VersionCode = $versionCode
    }
}

function Parse-RequestedVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedVersion
    )

    $match = [regex]::Match($RequestedVersion, "^([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?$")
    if (-not $match.Success) {
        throw "Invalid -Version value '$RequestedVersion'. Use x.y.z or x.y.z+n"
    }

    $versionName = $match.Groups[1].Value
    $inlineBuild = if ($match.Groups[2].Success) { [int]$match.Groups[2].Value } else { $null }

    return @{
        VersionName = $versionName
        InlineBuild = $inlineBuild
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$pubspecPath = Join-Path $PSScriptRoot "pubspec.yaml"
$localPropertiesPath = Join-Path $PSScriptRoot "android\local.properties"

if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at: $pubspecPath"
}

$pubspecContent = Get-Content -Path $pubspecPath -Raw
$currentVersion = Get-VersionFromPubspec -PubspecContent $pubspecContent
$requested = Parse-RequestedVersion -RequestedVersion $Version

if ($PSBoundParameters.ContainsKey("BuildNumber") -and $requested.InlineBuild -ne $null -and $BuildNumber -ne $requested.InlineBuild) {
    throw "Conflicting build numbers: -Version includes +$($requested.InlineBuild) but -BuildNumber is $BuildNumber"
}

$targetBuildNumber = if ($PSBoundParameters.ContainsKey("BuildNumber")) {
    $BuildNumber
}
elseif ($requested.InlineBuild -ne $null) {
    $requested.InlineBuild
}
else {
    [Math]::Max($currentVersion.VersionCode + 1, 1)
}

if ($targetBuildNumber -lt 1) {
    throw "Build number must be >= 1"
}

$targetVersion = "$($requested.VersionName)+$targetBuildNumber"

$updatedPubspec = [regex]::Replace(
    $pubspecContent,
    "(?m)^version:\s*.+$",
    "version: $targetVersion"
)

Write-Host "Current version: $($currentVersion.VersionName)+$($currentVersion.VersionCode)" -ForegroundColor Yellow
Write-Host "Target version : $targetVersion" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "Dry run mode: no files were changed." -ForegroundColor Green
    exit 0
}

Write-Utf8NoBom -Path $pubspecPath -Content $updatedPubspec
Write-Host "Updated pubspec.yaml" -ForegroundColor Green

if (Test-Path $localPropertiesPath) {
    $localContent = Get-Content -Path $localPropertiesPath -Raw

    if ($localContent -match "(?m)^flutter\.versionName=") {
        $localContent = [regex]::Replace($localContent, "(?m)^flutter\.versionName=.*$", "flutter.versionName=$($requested.VersionName)")
    }
    else {
        $separator = if ($localContent.EndsWith("`r`n") -or $localContent.EndsWith("`n")) { "" } else { "`r`n" }
        $localContent += "${separator}flutter.versionName=$($requested.VersionName)`r`n"
    }

    if ($localContent -match "(?m)^flutter\.versionCode=") {
        $localContent = [regex]::Replace($localContent, "(?m)^flutter\.versionCode=.*$", "flutter.versionCode=$targetBuildNumber")
    }
    else {
        $separator = if ($localContent.EndsWith("`r`n") -or $localContent.EndsWith("`n")) { "" } else { "`r`n" }
        $localContent += "${separator}flutter.versionCode=$targetBuildNumber`r`n"
    }

    Write-Utf8NoBom -Path $localPropertiesPath -Content $localContent
    Write-Host "Updated android/local.properties" -ForegroundColor Green
}
else {
    Write-Host "android/local.properties not found. Skipped syncing version there." -ForegroundColor Yellow
}

Write-Host "Done." -ForegroundColor Green
