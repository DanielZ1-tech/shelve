#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Shelve"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "🔍 Looking for Xcode-built binary..."

# Find the most recently built Shelve binary in DerivedData
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -name "$APP_NAME" -type f \
    ! -name "*.swift" ! -name "*.o" \
    -path "*/Products/*/$APP_NAME" \
    2>/dev/null | xargs ls -t 2>/dev/null | head -1)

if [ -z "$BINARY" ]; then
    echo "❌ No Xcode build found. Build the project in Xcode first (⌘B), then run this script."
    exit 1
fi

echo "✅ Found: $BINARY"
echo "📦 Packaging $APP_NAME.app..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Sources/Shelve/Assets/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icon
ICNS="$SCRIPT_DIR/Sources/Shelve/Assets/Shelve.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP_BUNDLE/Contents/Resources/Shelve.icns"
    echo "🎨 Icon applied."
else
    echo "⚠️  No icon found — run ./make-icon.sh first to add one."
fi

echo ""
echo "✅ Shelve.app is ready in: $SCRIPT_DIR"
echo "   Drag it to /Applications to install."
echo ""

read -p "Open Shelve now? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    open "$APP_BUNDLE"
fi
