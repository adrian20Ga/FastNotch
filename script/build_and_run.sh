#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FastNotch"
BUNDLE_ID="com.adriangonzalez.FastNotch"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/FastNotch.entitlements"
ICON_SOURCE="$ROOT_DIR/Resources/FastNotch.icns"
INSTALLED_APP="/Applications/$APP_NAME.app"
OLD_INSTALLED_APPS=("/Applications/NotchFinder.app" "/Applications/NotchUIX.app" "/Applications/NiceNotch.app" "/Applications/UtilNotch.app")

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "NotchFinder" >/dev/null 2>&1 || true
pkill -x "UtilNotch" >/dev/null 2>&1 || true

xcodebuild -scheme "$APP_NAME" -destination 'platform=macOS' -derivedDataPath "$ROOT_DIR/.build/xcode" build
BUILD_BINARY="$ROOT_DIR/.build/xcode/Build/Products/Debug/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ICON_SOURCE" "$APP_RESOURCES/FastNotch.icns"
chmod +x "$APP_BINARY"

/usr/libexec/PlistBuddy -c "Clear dict" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string FastNotch" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string FastNotch" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string FastNotch controls selected apps only to hide them from the notch." "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$INFO_PLIST"

codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --install|install)
    rm -rf "$INSTALLED_APP"
    for old_app in "${OLD_INSTALLED_APPS[@]}"; do
      rm -rf "$old_app"
    done
    ditto "$APP_BUNDLE" "$INSTALLED_APP"
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$INSTALLED_APP" >/dev/null
    /usr/bin/open -n "$INSTALLED_APP"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--install]" >&2
    exit 2
    ;;
esac
