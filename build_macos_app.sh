#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_MODE="release"
OPEN_APP=false
SKIP_PUB_GET=false
ENV_FILE_PATH="$SCRIPT_DIR/.env.json"
XCODE_DEV_DIR="/Applications/Xcode.app/Contents/Developer"

usage() {
  cat <<'EOF'
Usage: ./build_macos_app.sh [options]

Options:
  --debug              Build a debug macOS app.
  --release            Build a release macOS app (default).
  --open               Open the generated .app after build.
  --skip-pub-get       Skip "flutter pub get".
  --help, -h           Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      BUILD_MODE="debug"
      shift
      ;;
    --release)
      BUILD_MODE="release"
      shift
      ;;
    --open)
      OPEN_APP=true
      shift
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=true
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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' not found in PATH." >&2
    exit 1
  fi
}

ensure_flutter_sound_macos_podspec() {
  local cache_root="$HOME/.pub-cache/hosted/pub.dev"
  local plugin_dir

  plugin_dir="$(find "$cache_root" -maxdepth 1 -type d -name 'flutter_sound-*' | sort | tail -n 1)"
  if [[ -z "$plugin_dir" ]]; then
    return 0
  fi

  local macos_dir="$plugin_dir/macos"
  local taudio_spec="$macos_dir/taudio.podspec"
  local flutter_sound_spec="$macos_dir/flutter_sound.podspec"
  local plugin_pubspec="$plugin_dir/pubspec.yaml"

  if [[ -f "$plugin_pubspec" ]]; then
    echo "Applying flutter_sound macOS pluginClass compatibility fix..."
    python3 - "$plugin_pubspec" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text()
pattern = r"(\n\s*macos:\n\s*pluginClass:\s*)([^\n]+)"
replacement = r"\1TaudioPlugin"
text2 = re.sub(pattern, replacement, text, count=1)
if text2 != text:
    p.write_text(text2)
PY
  fi

  if [[ -f "$taudio_spec" ]]; then
    echo "Applying flutter_sound macOS podspec compatibility fix..."
    sed "s/s.name[[:space:]]*=[[:space:]]*'taudio'/s.name             = 'flutter_sound'/" "$taudio_spec" > "$flutter_sound_spec"
  fi
}

print_header() {
  printf '========================================\n'
  printf 'Flutter macOS Desktop Build Script\n'
  printf '========================================\n\n'
}

print_header
require_cmd flutter

# Help CocoaPods/Ruby trust HTTPS endpoints on macOS where cert paths vary.
if [[ -f "/etc/ssl/cert.pem" ]]; then
  export SSL_CERT_FILE="/etc/ssl/cert.pem"
  export CURL_CA_BUNDLE="/etc/ssl/cert.pem"
fi

if [[ ! -d "$XCODE_DEV_DIR" ]]; then
  echo "Error: Full Xcode is required at: $XCODE_DEV_DIR" >&2
  echo "Install Xcode from the App Store, then open it once to finish setup." >&2
  exit 1
fi

if ! DEVELOPER_DIR="$XCODE_DEV_DIR" xcodebuild -version >/dev/null 2>&1; then
  echo "Error: Could not run xcodebuild with DEVELOPER_DIR=$XCODE_DEV_DIR" >&2
  echo "Open Xcode once and complete any first-run setup prompts." >&2
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "Error: CocoaPods is not installed. macOS plugin builds require CocoaPods." >&2
  echo "Install with one of these commands:" >&2
  echo "  sudo gem install cocoapods" >&2
  echo "  brew install cocoapods" >&2
  exit 1
fi

cd "$SCRIPT_DIR"

# Stale plugin symlinks can break pod install with "File exists".
if [[ -d "$SCRIPT_DIR/macos/Flutter/ephemeral/.symlinks" ]]; then
  echo "Removing stale macOS plugin symlinks..."
  rm -rf "$SCRIPT_DIR/macos/Flutter/ephemeral/.symlinks"
fi

echo "Running flutter clean..."
flutter clean

if [[ "$SKIP_PUB_GET" != true ]]; then
  echo "Running flutter pub get..."
  flutter pub get
fi

ensure_flutter_sound_macos_podspec

echo
printf 'Building macOS app in %s mode...\n' "$BUILD_MODE"

build_cmd=(flutter build macos)
if [[ "$BUILD_MODE" == "release" ]]; then
  build_cmd+=(--release)
else
  build_cmd+=(--debug)
fi

if [[ -f "$ENV_FILE_PATH" ]]; then
  echo "Using dart define file: $ENV_FILE_PATH"
  build_cmd+=(--dart-define-from-file="$ENV_FILE_PATH")
else
  echo "Note: $ENV_FILE_PATH not found; using default compile-time config."
fi

DEVELOPER_DIR="$XCODE_DEV_DIR" "${build_cmd[@]}"

products_dir="$SCRIPT_DIR/build/macos/Build/Products"
if [[ "$BUILD_MODE" == "release" ]]; then
  target_dir="$products_dir/Release"
else
  target_dir="$products_dir/Debug"
fi

app_bundles=()
while IFS= read -r app; do
  app_bundles+=("$app")
done < <(find "$target_dir" -maxdepth 1 -name '*.app' -type d 2>/dev/null | sort)

if [[ ${#app_bundles[@]} -eq 0 ]]; then
  while IFS= read -r app; do
    app_bundles+=("$app")
  done < <(find "$SCRIPT_DIR/build/macos" -type d -name '*.app' 2>/dev/null | sort)
fi

if [[ ${#app_bundles[@]} -eq 0 ]]; then
  echo "Error: No .app bundle was found under: $SCRIPT_DIR/build/macos" >&2
  exit 1
fi

echo
echo "Build successful!"
echo "macOS app output(s):"
for app in "${app_bundles[@]}"; do
  echo "  $app"
done

if [[ "$OPEN_APP" == true ]]; then
  echo
  echo "Opening: ${app_bundles[0]}"
  open "${app_bundles[0]}"
fi
