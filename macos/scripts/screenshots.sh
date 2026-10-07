#!/usr/bin/env bash
# Renders README screenshots from made-up data into ../docs/screenshots/macos/.
# Uses a Debug build's --render-screenshots mode: no network, Keychain or real settings.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project PRChecker.xcodeproj -scheme PRChecker -configuration Debug \
  -derivedDataPath build -quiet build
"build/Build/Products/Debug/PR Checker.app/Contents/MacOS/PR Checker" \
  --render-screenshots "$PWD/../docs/screenshots/macos"
