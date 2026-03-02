# Flutter Release Build and Install Script
# PowerShell version with better error handling and features

param(
    [switch]$IncrementVersion,
    [switch]$SkipInstall,
    [switch]$StartLogcat,
    [string]$NewVersion
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Flutter Release Build and Install Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to check if command exists
function Test-Command($cmdname) {
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

# Function to get current version from pubspec.yaml
function Get-CurrentVersion {
    try {
        $content = Get-Content "pubspec.yaml" -ErrorAction Stop
        $versionLine = $content | Where-Object { $_ -match "^version:\s*(.+)" }
        if ($versionLine) {
            return $Matches[1].Trim()
        }
    }
    catch {
        Write-Host "ERROR: Could not read pubspec.yaml" -ForegroundColor Red
        return $null
    }
    return $null
}

# Function to increment version
function Set-NewVersion($currentVersion, $incrementType) {
    if ($currentVersion -match "^(\d+)\.(\d+)\.(\d+)\+(\d+)$") {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2] 
        $patch = [int]$Matches[3]
        $build = [int]$Matches[4]
        
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
        
        $newVersion = "$major.$minor.$patch+$build"
        
        # Update pubspec.yaml
        try {
            $content = Get-Content "pubspec.yaml"
            $content = $content -replace "^version:\s*.+", "version: $newVersion"
            $content | Set-Content "pubspec.yaml"
            Write-Host "✅ Version updated to: $newVersion" -ForegroundColor Green
            return $newVersion
        }
        catch {
            Write-Host "ERROR: Could not update pubspec.yaml" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "ERROR: Invalid version format in pubspec.yaml" -ForegroundColor Red
        return $null
    }
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
$currentVersion = Get-CurrentVersion
if ($currentVersion) {
    Write-Host "Current version: $currentVersion" -ForegroundColor Green
}
else {
    Write-Host "Could not determine current version" -ForegroundColor Yellow
}

# Handle version increment
if ($IncrementVersion -or $NewVersion) {
    if ($NewVersion) {
        # Custom version provided
        try {
            $content = Get-Content "pubspec.yaml"
            $content = $content -replace "^version:\s*.+", "version: $NewVersion"
            $content | Set-Content "pubspec.yaml"
            Write-Host "✅ Version updated to: $NewVersion" -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR: Could not update version" -ForegroundColor Red
            exit 1
        }
    }
    else {
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
            $newVersion = Set-NewVersion $currentVersion $incrementType
            if (-not $newVersion) {
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
        
        adb install -r $apkPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "ERROR: Installation failed" -ForegroundColor Red
            Write-Host ""
            Write-Host "Troubleshooting:" -ForegroundColor Yellow
            Write-Host "1. Make sure USB debugging is enabled"
            Write-Host "2. Check if device is authorized (check device screen for prompt)"
            Write-Host "3. Try: adb kill-server && adb start-server"
            Write-Host "4. Manual install: adb install -r `"$apkPath`""
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