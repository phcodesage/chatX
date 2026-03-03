@echo off
echo Installing release APK...
adb install -r build\app\outputs\flutter-apk\app-release.apk

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Installation successful!
    echo.
    echo Starting logcat filtered for Flutter...
    echo Press Ctrl+C to stop logging
    echo.
    adb logcat -s flutter:V
) else (
    echo.
    echo Installation failed! Make sure device is connected.
    pause
)
