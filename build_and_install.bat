@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Flutter Release Build and Install Script
echo ========================================
echo.

:: Check if Flutter is available
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter not found in PATH
    echo Please install Flutter and add it to your PATH
    pause
    exit /b 1
)

:: Check if ADB is available
adb version >nul 2>&1
if errorlevel 1 (
    echo ERROR: ADB not found in PATH
    echo Please install Android SDK and add ADB to your PATH
    pause
    exit /b 1
)

:: Check for connected devices
echo Checking for connected devices...
adb devices | findstr "device$" >nul
if errorlevel 1 (
    echo.
    echo WARNING: No devices found!
    echo Please connect your device via USB or wireless ADB
    echo.
    echo To connect via wireless ADB:
    echo   1. Enable Developer Options and USB Debugging on your device
    echo   2. Connect via USB first, then run: adb tcpip 5555
    echo   3. Find your device IP and run: adb connect [IP]:5555
    echo.
    set /p continue="Continue anyway? (y/N): "
    if /i not "!continue!"=="y" (
        echo Build cancelled.
        pause
        exit /b 1
    )
) else (
    echo Connected devices:
    adb devices
    echo.
)

:: Get current version from pubspec.yaml
echo Reading current version...
for /f "tokens=2" %%i in ('findstr "^version:" pubspec.yaml') do set CURRENT_VERSION=%%i
echo Current version: %CURRENT_VERSION%
echo.

:: Ask if user wants to increment version
set /p increment="Increment version? (y/N): "
if /i "!increment!"=="y" (
    echo.
    echo Version increment options:
    echo 1. Patch (1.0.5+5 -> 1.0.6+6)
    echo 2. Minor (1.0.5+5 -> 1.1.0+6)  
    echo 3. Major (1.0.5+5 -> 2.0.0+6)
    echo 4. Build only (1.0.5+5 -> 1.0.5+6)
    echo 5. Custom
    echo.
    set /p version_choice="Choose option (1-5): "
    
    if "!version_choice!"=="1" (
        echo Incrementing patch version...
        :: This is a simplified increment - you might want to use a more robust version parser
        echo Note: Manual version increment required in pubspec.yaml
    ) else if "!version_choice!"=="4" (
        echo Incrementing build number...
        echo Note: Manual build increment required in pubspec.yaml
    ) else if "!version_choice!"=="5" (
        set /p new_version="Enter new version (e.g., 1.0.7+7): "
        echo Note: Please update pubspec.yaml with version: !new_version!
    )
    echo.
    echo Please update the version in pubspec.yaml if needed, then press any key to continue...
    pause >nul
)

:: Clean previous build
echo Cleaning previous build...
flutter clean
if errorlevel 1 (
    echo ERROR: Flutter clean failed
    pause
    exit /b 1
)

:: Get dependencies
echo Getting dependencies...
flutter pub get
if errorlevel 1 (
    echo ERROR: Flutter pub get failed
    pause
    exit /b 1
)

:: Build release APK
echo.
echo ========================================
echo Building Release APK...
echo ========================================
echo.
flutter build apk --release
if errorlevel 1 (
    echo ERROR: Flutter build failed
    pause
    exit /b 1
)

:: Check if APK was created
if not exist "build\app\outputs\flutter-apk\app-release.apk" (
    echo ERROR: APK file not found after build
    pause
    exit /b 1
)

:: Get APK size
for %%i in ("build\app\outputs\flutter-apk\app-release.apk") do set APK_SIZE=%%~zi
set /a APK_SIZE_MB=!APK_SIZE!/1024/1024
echo.
echo ✅ Build successful! APK size: !APK_SIZE_MB! MB

:: Check for devices again before installation
echo.
echo Checking for devices before installation...
adb devices | findstr "device$" >nul
if errorlevel 1 (
    echo.
    echo No devices connected. Skipping installation.
    echo APK location: build\app\outputs\flutter-apk\app-release.apk
    echo.
    echo To install manually:
    echo   adb install -r build\app\outputs\flutter-apk\app-release.apk
    echo.
    pause
    exit /b 0
)

:: Install APK
echo.
echo ========================================
echo Installing APK to device...
echo ========================================
echo.
adb install -r "build\app\outputs\flutter-apk\app-release.apk"
if errorlevel 1 (
    echo.
    echo ERROR: Installation failed
    echo.
    echo Troubleshooting:
    echo 1. Make sure USB debugging is enabled
    echo 2. Check if device is authorized (check device screen for prompt)
    echo 3. Try: adb kill-server && adb start-server
    echo 4. Manual install: adb install -r build\app\outputs\flutter-apk\app-release.apk
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo ✅ SUCCESS!
echo ========================================
echo.
echo Release APK built and installed successfully!
echo APK location: build\app\outputs\flutter-apk\app-release.apk
echo Size: !APK_SIZE_MB! MB
echo.

:: Ask if user wants to start logcat for debugging
set /p start_logcat="Start logcat for debugging? (y/N): "
if /i "!start_logcat!"=="y" (
    echo.
    echo Starting logcat... Press Ctrl+C to stop
    echo.
    adb logcat -s flutter:V
)

echo.
echo Build and install completed!
pause