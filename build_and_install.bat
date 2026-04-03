@echo off
setlocal enabledelayedexpansion

set "APP_ID=com.example.flutter_messenger_v2"
set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
set "INSTALL_LOG=%TEMP%\flutter_messenger_install_%RANDOM%.log"

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
if not exist "%APK_PATH%" (
    echo ERROR: APK file not found after build
    pause
    exit /b 1
)

:: Get APK size
for %%i in ("%APK_PATH%") do set APK_SIZE=%%~zi
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
    echo APK location: %APK_PATH%
    echo.
    echo To install manually:
    echo   adb install -r %APK_PATH%
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
adb install -r "%APK_PATH%" >"%INSTALL_LOG%" 2>&1
set "INSTALL_EXIT=!ERRORLEVEL!"
type "%INSTALL_LOG%"
if not !INSTALL_EXIT! EQU 0 (
    findstr /C:"INSTALL_FAILED_UPDATE_INCOMPATIBLE" "%INSTALL_LOG%" >nul
    if !ERRORLEVEL! EQU 0 (
        echo.
        echo Package conflict detected for %APP_ID%.
        set /p remove_existing="Uninstall the existing app and reinstall? This removes app data. (y/N): "
        if /i "!remove_existing!"=="y" (
            adb uninstall %APP_ID%
            if errorlevel 1 (
                echo Could not uninstall existing app.
                del "%INSTALL_LOG%" >nul 2>&1
                pause
                exit /b 1
            )

            adb install "%APK_PATH%"
            if not errorlevel 1 (
                echo.
                echo ========================================
                echo ✅ SUCCESS!
                echo ========================================
                echo.
                echo Release APK built and installed successfully!
                echo APK location: %APK_PATH%
                echo Size: !APK_SIZE_MB! MB
                echo.
                del "%INSTALL_LOG%" >nul 2>&1
                goto after_install
            )
        )
    )

    findstr /C:"INSTALL_FAILED_VERSION_DOWNGRADE" "%INSTALL_LOG%" >nul
    if !ERRORLEVEL! EQU 0 (
        echo.
        echo The device already has a newer build installed.
        echo Increase the build number before rebuilding.
    )

    echo.
    echo ERROR: Installation failed
    echo.
    echo Troubleshooting:
    echo 1. Make sure USB debugging is enabled
    echo 2. Check if device is authorized (check device screen for prompt)
    echo 3. If this is a package conflict, uninstall %APP_ID% from the device and retry
    echo 4. If this is a downgrade, bump the build number before rebuilding
    echo 5. Manual install: adb install -r %APK_PATH%
    echo.
    del "%INSTALL_LOG%" >nul 2>&1
    pause
    exit /b 1
)

del "%INSTALL_LOG%" >nul 2>&1

echo.
echo ========================================
echo ✅ SUCCESS!
echo ========================================
echo.
echo Release APK built and installed successfully!
echo APK location: %APK_PATH%
echo Size: !APK_SIZE_MB! MB
echo.

:after_install

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