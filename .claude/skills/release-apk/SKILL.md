---
name: release-apk
description: Build a release Android APK for this Flutter app and install it on a connected device. Use when the user asks to build/ship/install a release build or asks for an APK.
disable-model-invocation: true
---

# release-apk

Build the signed release APK and install it via the project's script. Usage: `/release-apk $ARGUMENTS`

## Preconditions

- `.env.json` exists at the project root (holds `BASE_URL`). If missing, copy `.env.json.example` and ask the user for the URL before building.
- `android/key.properties` exists for release signing. If missing, warn that the build will fall back to debug signing.
- A device/emulator is connected (`flutter devices`) if installing.

## Steps

1. Run `./build_and_install.sh $ARGUMENTS` from the project root. Useful flags to pass through:
   - `--skip-install` — build the APK only, don't `adb install`.
   - `--start-logcat` — tail flutter logcat after install.
2. The script builds `build/app/outputs/flutter-apk/app-release.apk` (with `--dart-define-from-file=.env.json`) and installs it for package `com.example.flutter_messenger_v2`.
3. Report the resulting APK path and whether install succeeded. Surface any signing or device-connection errors verbatim.
