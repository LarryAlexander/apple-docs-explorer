#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -d AppleDocsExplorer.xcodeproj ]]; then
  ./scripts/generate_project.sh
fi

xcodebuild -project AppleDocsExplorer.xcodeproj -scheme AppleDocsExplorer -configuration Debug build >/dev/null

APP_PATH="$(
  xcodebuild -project AppleDocsExplorer.xcodeproj -scheme AppleDocsExplorer -configuration Debug -showBuildSettings |
    awk -F ' = ' '$1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ { dir=$2 } $1 ~ /^[[:space:]]*FULL_PRODUCT_NAME$/ { name=$2 } END { print dir "/" name }'
)"
open "$APP_PATH"
