#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="$PWD/build"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -n 1)"
[ -n "$VERSION" ] || { echo "error: could not read MARKETING_VERSION from project.yml" >&2; exit 1; }

command -v xcodegen >/dev/null || { echo "error: xcodegen is not installed (brew install xcodegen)" >&2; exit 1; }

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodegen generate

xcodebuild \
  -project BetterHours.xcodeproj \
  -scheme BetterHours \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$BUILD_DIR/DerivedData/Build/Products/Release/Better Hours.app"
[ -d "$APP" ] || { echo "error: $APP was not produced" >&2; exit 1; }

ZIP="$BUILD_DIR/BetterHours-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "$ZIP"
