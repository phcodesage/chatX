@echo off
setlocal enabledelayedexpansion

set "APP_ID=com.example.flutter_messenger_v2"
set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
set "INSTALL_LOG=%TEMP%\flutter_messenger_install_%RANDOM%.log"

echo Installing release APK...
adb install -r "%APK_PATH%" >"%INSTALL_LOG%" 2>&1
set "INSTALL_EXIT=%ERRORLEVEL%"
type "%INSTALL_LOG%"

if %INSTALL_EXIT% EQU 0 (
    echo.
    echo Installation successful!
    echo.
    echo Starting logcat filtered for Flutter...
    echo Press Ctrl+C to stop logging
    echo.
    adb logcat -s flutter:V
) else (
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
                echo Installation successful after reinstall!
                echo.
                adb logcat -s flutter:V
                del "%INSTALL_LOG%" >nul 2>&1
                exit /b 0
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
    echo Installation failed! Make sure device is connected.
    del "%INSTALL_LOG%" >nul 2>&1
    pause
)

del "%INSTALL_LOG%" >nul 2>&1
