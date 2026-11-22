#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${CADENCE_BUILD_DIR:-/tmp/cadence-build}"
APP="${CADENCE_APP_DIR:-$ROOT/build/Cadence.app}"
SUPPORT="$ROOT/Support"

echo "▸ Cadence build"
echo "  root:    $ROOT"
echo "  scratch: $SCRATCH"

mkdir -p "$SUPPORT"
if [ ! -f "$SUPPORT/AppIcon.icns" ] || [ "${CADENCE_REBUILD_ICON:-0}" = "1" ]; then
    echo "▸ icon"
    swift "$SUPPORT/make_icon.swift" "$SUPPORT"
fi

echo "▸ swift build (release)"
cd "$ROOT"
swift build -c release --scratch-path "$SCRATCH" --product Cadence

BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"
BIN="$BIN_DIR/Cadence"
if [ ! -x "$BIN" ]; then
    echo "Executable not found at $BIN" >&2
    exit 1
fi

echo "▸ bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cadence"
cp "$SUPPORT/Info.plist" "$APP/Contents/Info.plist"
cp "$SUPPORT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/Cadence"

xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "▸ done: $APP"
echo "  open \"$APP\""
