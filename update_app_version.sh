#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBSPEC_PATH="$SCRIPT_DIR/pubspec.yaml"
LOCAL_PROPERTIES_PATH="$SCRIPT_DIR/android/local.properties"

VERSION=""
BUILD_NUMBER=""
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./update_app_version.sh [--dry-run]

Options:
  (no options)        Automatically increments patch and build number.
  --version, -v       Optional manual version x.y.z or x.y.z+n.
  --build-number, -b  Optional manual build number override.
  --dry-run           Print target changes without editing files.
  --help, -h          Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number|-b)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
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

if [[ ! -f "$PUBSPEC_PATH" ]]; then
  echo "Error: pubspec.yaml not found at $PUBSPEC_PATH" >&2
  exit 1
fi

current_line="$(grep -E '^version:[[:space:]]*' "$PUBSPEC_PATH" | head -n1 || true)"
if [[ -z "$current_line" ]]; then
  echo "Error: Could not find a valid version line in pubspec.yaml." >&2
  exit 1
fi

current_raw="${current_line#version:}"
current_raw="$(echo "$current_raw" | xargs)"

if [[ "$current_raw" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(\+([0-9]+))?$ ]]; then
  current_version_name="${BASH_REMATCH[1]}"
  current_version_code="${BASH_REMATCH[3]:-0}"
else
  echo "Error: Invalid current version format in pubspec.yaml: $current_raw" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current_version_name"
if [[ -n "$VERSION" ]]; then
  if [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(\+([0-9]+))?$ ]]; then
    target_version_name="${BASH_REMATCH[1]}"
    inline_build="${BASH_REMATCH[3]:-}"
  else
    echo "Error: Invalid --version value '$VERSION'. Use x.y.z or x.y.z+n." >&2
    exit 1
  fi

  if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: --build-number must be a positive integer." >&2
    exit 1
  fi

  if [[ -n "$BUILD_NUMBER" && -n "$inline_build" && "$BUILD_NUMBER" != "$inline_build" ]]; then
    echo "Error: Conflicting build numbers: --version includes +$inline_build but --build-number is $BUILD_NUMBER" >&2
    exit 1
  fi

  if [[ -n "$BUILD_NUMBER" ]]; then
    target_build_number="$BUILD_NUMBER"
  elif [[ -n "$inline_build" ]]; then
    target_build_number="$inline_build"
  else
    target_build_number=$((current_version_code + 1))
  fi
else
  target_patch=$((patch + 1))
  target_version_name="${major}.${minor}.${target_patch}"
  if [[ -n "$BUILD_NUMBER" ]]; then
    if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
      echo "Error: --build-number must be a positive integer." >&2
      exit 1
    fi
    target_build_number="$BUILD_NUMBER"
  else
    target_build_number=$((current_version_code + 1))
  fi
fi

if (( target_build_number < 1 )); then
  target_build_number=1
fi

target_version="${target_version_name}+${target_build_number}"

echo "Current version: ${current_version_name}+${current_version_code}"
echo "Target version : ${target_version}"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run mode: no files were changed."
  exit 0
fi

pubspec_tmp="$(mktemp)"
awk -v target="$target_version" '
  BEGIN { replaced=0 }
  /^version:[[:space:]]*/ && replaced==0 {
    print "version: " target
    replaced=1
    next
  }
  { print }
  END {
    if (replaced==0) {
      exit 2
    }
  }
' "$PUBSPEC_PATH" > "$pubspec_tmp"
mv "$pubspec_tmp" "$PUBSPEC_PATH"

echo "Updated pubspec.yaml"

if [[ -f "$LOCAL_PROPERTIES_PATH" ]]; then
  update_or_append_property() {
    local file_path="$1"
    local key="$2"
    local value="$3"
    local tmp_file
    tmp_file="$(mktemp)"

    if grep -Eq "^${key}=" "$file_path"; then
      awk -v k="$key" -v v="$value" '
        BEGIN { replaced=0 }
        $0 ~ ("^" k "=") && replaced==0 {
          print k "=" v
          replaced=1
          next
        }
        { print }
      ' "$file_path" > "$tmp_file"
    else
      cat "$file_path" > "$tmp_file"
      if [[ -s "$tmp_file" ]]; then
        printf "\n" >> "$tmp_file"
      fi
      printf "%s=%s\n" "$key" "$value" >> "$tmp_file"
    fi

    mv "$tmp_file" "$file_path"
  }

  update_or_append_property "$LOCAL_PROPERTIES_PATH" "flutter.versionName" "$target_version_name"
  update_or_append_property "$LOCAL_PROPERTIES_PATH" "flutter.versionCode" "$target_build_number"
  echo "Updated android/local.properties"
else
  echo "android/local.properties not found. Skipped syncing version there."
fi

echo "Done."
