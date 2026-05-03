#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NAME="com.example.flutter_messenger_v2"
APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-release.apk"
ENV_FILE_PATH="$SCRIPT_DIR/.env.json"
SKIP_INSTALL=false
START_LOGCAT=false

usage() {
  cat <<'EOF'
Usage: ./build_and_install.sh [options]

Options:
  --skip-install          Build only, skip adb install.
  --start-logcat          Start flutter logcat after script completes.
  --help, -h              Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=true
      shift
      ;;
    --start-logcat)
      START_LOGCAT=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

print_header() {
  printf '========================================\n'
  printf 'Flutter Release Build and Install Script\n'
  printf '========================================\n\n'
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' not found in PATH." >&2
    exit 1
  fi
}

connected_device_count() {
  adb devices | awk 'NR>1 && $2=="device" {count++} END {print count+0}'
}

install_apk() {
  local apk_path="$1"
  local app_id="$2"
  local install_output status

  install_output="$(adb install -r "$apk_path" 2>&1)"
  status=$?
  if [[ -n "$install_output" ]]; then
    echo "$install_output"
  fi

  if [[ $status -eq 0 ]]; then
    return 0
  fi

  if grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE" <<<"$install_output"; then
    echo
    echo "The installed app uses the same package name but a different signing key."
    echo "Package: $app_id"
    read -r -p "Uninstall the existing app and reinstall? This removes app data. (y/N): " remove_existing
    if [[ "$remove_existing" == "y" || "$remove_existing" == "Y" ]]; then
      adb uninstall "$app_id" || {
        echo "Could not uninstall the existing app." >&2
        return 1
      }
      adb install "$apk_path"
      return $?
    fi
  fi

  return 1
}

print_header
require_cmd flutter
require_cmd adb

echo
echo "Checking for connected devices..."
initial_device_count="$(connected_device_count)"
if [[ "$initial_device_count" -eq 0 && "$SKIP_INSTALL" != true ]]; then
  echo
  echo "Warning: No devices found."
  echo "Connect via USB or use wireless adb before installation."
  read -r -p "Continue anyway? (y/N): " continue_anyway
  if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
    echo "Build cancelled."
    exit 1
  fi
fi

echo
echo "Cleaning previous build..."
flutter clean

echo "Getting dependencies..."
flutter pub get

echo
echo "========================================"
echo "Building Release APK..."
echo "========================================"

SECONDS=0
if [[ -f "$ENV_FILE_PATH" ]]; then
  echo "Using dart define file: $ENV_FILE_PATH"
  flutter build apk --release --dart-define-from-file="$ENV_FILE_PATH"
else
  echo "Warning: $ENV_FILE_PATH not found. Falling back to ApiConfig default BASE_URL."
  flutter build apk --release
fi
build_time="$SECONDS"

if [[ ! -f "$APK_PATH" ]]; then
  echo "Error: APK file not found after build at $APK_PATH" >&2
  exit 1
fi

apk_size_bytes="$(stat -f%z "$APK_PATH")"
apk_size_mb="$(awk -v b="$apk_size_bytes" 'BEGIN { printf "%.1f", b/1024/1024 }')"

echo
echo "Build successful!"
echo "APK size: ${apk_size_mb} MB"
echo "Build time: ${build_time} seconds"

if [[ "$SKIP_INSTALL" != true ]]; then
  echo
  echo "Checking for devices before installation..."
  install_device_count="$(connected_device_count)"
  if [[ "$install_device_count" -eq 0 ]]; then
    echo "No devices connected. Skipping installation."
    echo "APK location: $APK_PATH"
    echo "Manual install: adb install -r \"$APK_PATH\""
  else
    echo
    echo "========================================"
    echo "Installing APK to device..."
    echo "========================================"

    if ! install_apk "$APK_PATH" "$PACKAGE_NAME"; then
      echo
      echo "Error: Installation failed."
      echo "Troubleshooting:"
      echo "1. Make sure USB debugging is enabled"
      echo "2. Check device authorization prompt"
      echo "3. If package conflict, uninstall $PACKAGE_NAME and retry"
      echo "4. Manual install: adb install -r \"$APK_PATH\""
      exit 1
    fi

    echo
    echo "Installation successful!"
  fi
fi

echo
echo "========================================"
echo "SUCCESS"
echo "========================================"
echo "Release APK built successfully."
echo "APK location: $APK_PATH"
echo "Size: ${apk_size_mb} MB"
echo "Build time: ${build_time} seconds"

if [[ "$START_LOGCAT" == true ]]; then
  echo
  echo "Starting logcat... Press Ctrl+C to stop"
  adb logcat -s flutter:V
else
  read -r -p "Start logcat for debugging? (y/N): " start_logcat_input
  if [[ "$start_logcat_input" == "y" || "$start_logcat_input" == "Y" ]]; then
    echo
    echo "Starting logcat... Press Ctrl+C to stop"
    adb logcat -s flutter:V
  fi
fi

echo
echo "Build and install completed!"
