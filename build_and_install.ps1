# Flutter Release Build and Install Script
# PowerShell version with better error handling and features

param(
    [switch]$IncrementVersion,
    [switch]$SkipInstall,
    [switch]$StartLogcat,
    [string]$NewVersion
)

$PackageName = "com.example.flutter_messenger_v2"
$VersionScriptPath = Join-Path $PSScriptRoot "update_app_version.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Flutter Release Build and Install Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to check if command exists
function Test-Command($cmdname) {
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

# Function to get current version from pubspec.yaml
function Get-VersionInfo {
    try {
        $content = Get-Content "pubspec.yaml" -Raw -ErrorAction Stop
        $match = [regex]::Match($content, "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$")
        if ($match.Success) {
            $versionName = $match.Groups[1].Value
            $versionCode = if ($match.Groups[2].Success) { [int]$match.Groups[2].Value } else { 0 }
            return @{
                VersionName = $versionName
                VersionCode = $versionCode
                DisplayVersion = if ($versionCode -gt 0) { "$versionName+$versionCode" } else { $versionName }
            }
        }
    }
    catch {
        Write-Host "ERROR: Could not read pubspec.yaml" -ForegroundColor Red
        return $null
    }
    return $null
}

# Function to compute the next version string.
function Get-NextVersion($currentVersion, $incrementType) {
    if ($currentVersion -match "^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$") {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $patch = [int]$Matches[3]
        $build = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
        
        switch ($incrementType) {
            "patch" { 
                $patch++
                $build++
            }
            "minor" { 
                $minor++
                $patch = 0
                $build++
            }
            "major" { 
                $major++
                $minor = 0
                $patch = 0
                $build++
            }
            "build" { 
                $build++
            }
        }
        
        return "$major.$minor.$patch+$build"
    }
    else {
        Write-Host "ERROR: Invalid version format in pubspec.yaml" -ForegroundColor Red
        return $null
    }
}

function Sync-Version($targetVersion) {
    if (-not (Test-Path $VersionScriptPath)) {
        throw "Version sync script not found at $VersionScriptPath"
    }

    & $VersionScriptPath -Version $targetVersion
    if ($LASTEXITCODE -ne 0) {
        throw "Version sync failed for $targetVersion"
    }
}

function Install-Apk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApkPath,
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId
    )

    $installOutput = & adb install -r $ApkPath 2>&1
    $installText = ($installOutput | Out-String).Trim()

    if ($installText) {
        Write-Host $installText
    }

    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    if ($installText -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
        Write-Host "" 
        Write-Host "The installed app uses the same package name but a different signing key." -ForegroundColor Yellow
        Write-Host "Package: $ApplicationId" -ForegroundColor Yellow
        $removeExisting = Read-Host "Uninstall the existing app and reinstall? This removes app data. (y/N)"
        if ($removeExisting -eq "y" -or $removeExisting -eq "Y") {
            & adb uninstall $ApplicationId
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Could not uninstall the existing app." -ForegroundColor Red
                return $false
            }

            $retryOutput = & adb install $ApkPath 2>&1
            $retryText = ($retryOutput | Out-String).Trim()
            if ($retryText) {
                Write-Host $retryText
            }

            return $LASTEXITCODE -eq 0
        }
    }
    elseif ($installText -match "INSTALL_FAILED_VERSION_DOWNGRADE") {
        Write-Host "" 
        Write-Host "The device already has a newer build installed." -ForegroundColor Yellow
        Write-Host "Increase the build number in pubspec.yaml and rebuild, or use update_app_version.ps1." -ForegroundColor Yellow
    }

    return $false
}

# Check Flutter
if (-not (Test-Command "flutter")) {
    Write-Host "ERROR: Flutter not found in PATH" -ForegroundColor Red
    Write-Host "Please install Flutter and add it to your PATH" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check ADB
if (-not (Test-Command "adb")) {
    Write-Host "ERROR: ADB not found in PATH" -ForegroundColor Red
    Write-Host "Please install Android SDK and add ADB to your PATH" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Get current version
$currentVersionInfo = Get-VersionInfo
if ($currentVersionInfo) {
    Write-Host "Current version: $($currentVersionInfo.DisplayVersion)" -ForegroundColor Green
}
else {
    Write-Host "Could not determine current version" -ForegroundColor Yellow
}

# Handle version increment
if ($IncrementVersion -or $NewVersion) {
    if ($NewVersion) {
        try {
            Sync-Version $NewVersion
            $currentVersionInfo = Get-VersionInfo
            Write-Host "✅ Version updated to: $($currentVersionInfo.DisplayVersion)" -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR: Could not update version" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            exit 1
        }
    }
    else {
        if (-not $currentVersionInfo) {
            Write-Host "ERROR: Could not determine the current version for incrementing" -ForegroundColor Red
            exit 1
        }

        # Interactive version increment
        Write-Host ""
        Write-Host "Version increment options:" -ForegroundColor Yellow
        Write-Host "1. Patch (e.g., 1.0.5+5 -> 1.0.6+6)"
        Write-Host "2. Minor (e.g., 1.0.5+5 -> 1.1.0+6)"
        Write-Host "3. Major (e.g., 1.0.5+5 -> 2.0.0+6)"
        Write-Host "4. Build only (e.g., 1.0.5+5 -> 1.0.5+6)"
        Write-Host ""
        
        $choice = Read-Host "Choose option (1-4)"
        
        $incrementType = switch ($choice) {
            "1" { "patch" }
            "2" { "minor" }
            "3" { "major" }
            "4" { "build" }
            default { 
                Write-Host "Invalid choice, skipping version increment" -ForegroundColor Yellow
                $null
            }
        }
        
        if ($incrementType) {
            $newVersion = Get-NextVersion $currentVersionInfo.DisplayVersion $incrementType
            if (-not $newVersion) {
                exit 1
            }

            try {
                Sync-Version $newVersion
                $currentVersionInfo = Get-VersionInfo
                Write-Host "✅ Version updated to: $($currentVersionInfo.DisplayVersion)" -ForegroundColor Green
            }
            catch {
                Write-Host "ERROR: Could not update version" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                exit 1
            }
        }
    }
}

# Check for connected devices
Write-Host ""
Write-Host "Checking for connected devices..." -ForegroundColor Yellow
$devices = adb devices | Select-String "device$"
if ($devices.Count -eq 0) {
    Write-Host ""
    Write-Host "WARNING: No devices found!" -ForegroundColor Yellow
    Write-Host "Please connect your device via USB or wireless ADB" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To connect via wireless ADB:" -ForegroundColor Cyan
    Write-Host "  1. Enable Developer Options and USB Debugging on your device"
    Write-Host "  2. Connect via USB first, then run: adb tcpip 5555"
    Write-Host "  3. Find your device IP and run: adb connect [IP]:5555"
    Write-Host ""
    
    if (-not $SkipInstall) {
        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            Write-Host "Build cancelled." -ForegroundColor Yellow
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}
else {
    Write-Host "Connected devices:" -ForegroundColor Green
    adb devices
    Write-Host ""
}

# Clean previous build
Write-Host "Cleaning previous build..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Flutter clean failed" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Flutter pub get failed" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Build release APK
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building Release APK..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$buildStart = Get-Date
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Flutter build failed" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
$buildEnd = Get-Date
$buildTime = ($buildEnd - $buildStart).TotalSeconds

# Check if APK was created
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkPath)) {
    Write-Host "ERROR: APK file not found after build" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Get APK size
$apkSize = (Get-Item $apkPath).Length
$apkSizeMB = [math]::Round($apkSize / 1MB, 1)

Write-Host ""
Write-Host "✅ Build successful!" -ForegroundColor Green
Write-Host "APK size: $apkSizeMB MB" -ForegroundColor Green
Write-Host "Build time: $([math]::Round($buildTime, 1)) seconds" -ForegroundColor Green
if ($currentVersionInfo) {
    Write-Host "APK version: $($currentVersionInfo.DisplayVersion)" -ForegroundColor Green
}

# Install APK if not skipped
if (-not $SkipInstall) {
    # Check for devices again before installation
    Write-Host ""
    Write-Host "Checking for devices before installation..." -ForegroundColor Yellow
    $devices = adb devices | Select-String "device$"
    if ($devices.Count -eq 0) {
        Write-Host ""
        Write-Host "No devices connected. Skipping installation." -ForegroundColor Yellow
        Write-Host "APK location: $apkPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "To install manually:" -ForegroundColor Cyan
        Write-Host "  adb install -r `"$apkPath`""
    }
    else {
        # Install APK
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Installing APK to device..." -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        $installed = Install-Apk -ApkPath $apkPath -ApplicationId $PackageName
        if (-not $installed) {
            Write-Host ""
            Write-Host "ERROR: Installation failed" -ForegroundColor Red
            Write-Host ""
            Write-Host "Troubleshooting:" -ForegroundColor Yellow
            Write-Host "1. Make sure USB debugging is enabled"
            Write-Host "2. Check if device is authorized (check device screen for prompt)"
            Write-Host "3. If this is a package conflict, uninstall $PackageName from the device and retry"
            Write-Host "4. If this is a downgrade, bump the build number before rebuilding"
            Write-Host "5. Manual install: adb install -r `"$apkPath`""
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
        
        Write-Host ""
        Write-Host "✅ Installation successful!" -ForegroundColor Green
    }
}

# Final summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ SUCCESS!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Release APK built successfully!" -ForegroundColor Green
Write-Host "APK location: $apkPath" -ForegroundColor Cyan
Write-Host "Size: $apkSizeMB MB" -ForegroundColor Cyan
Write-Host "Build time: $([math]::Round($buildTime, 1)) seconds" -ForegroundColor Cyan

# Start logcat if requested
if ($StartLogcat) {
    Write-Host ""
    Write-Host "Starting logcat... Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""
    adb logcat -s flutter:V
}
else {
    Write-Host ""
    $startLogcatInput = Read-Host "Start logcat for debugging? (y/N)"
    if ($startLogcatInput -eq "y" -or $startLogcatInput -eq "Y") {
        Write-Host ""
        Write-Host "Starting logcat... Press Ctrl+C to stop" -ForegroundColor Yellow
        Write-Host ""
        adb logcat -s flutter:V
    }
}

Write-Host ""
Write-Host "Build and install completed!" -ForegroundColor Green
Read-Host "Press Enter to exit"