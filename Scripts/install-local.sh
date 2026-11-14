#!/bin/bash
# Patched fork: build Release as com.tinycast.app, install over /Applications/Tinycast.app, relaunch.
# Signs with the "Tinycast Self-Signed" identity (docs/signing.md §1), so TCC grants survive rebuilds.
# The version is the newest stable tag this build contains, so About and update checks stay honest.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BUNDLE_ID=com.tinycast.app
INSTALLED=/Applications/Tinycast.app
DERIVED=build/DerivedData-local
APP="$DERIVED/Build/Products/Release/Tinycast.app"
VERSION=$(git describe --tags --abbrev=0 --exclude '*-beta*' HEAD | sed 's/^v//')
BUILD=$(defaults read "$INSTALLED/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 1)

security find-identity -p codesigning | grep -q "Tinycast Self-Signed" ||
    { echo "Missing the Tinycast Self-Signed identity: see docs/signing.md §1" >&2; exit 1; }

xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" build \
    | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
codesign --verify --deep --strict "$APP"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
sleep 2
[ -e "$INSTALLED" ] && trash "$INSTALLED"
ditto "$APP" "$INSTALLED"
open "$INSTALLED"
echo "Installed Tinycast $VERSION ($BUILD) from $(git rev-parse --short HEAD) on $(git branch --show-current)"
