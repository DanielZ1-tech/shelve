#!/bin/bash
# Usage: ./make-icon.sh path/to/your-image.png
# Requires: macOS built-in sips + iconutil (no installs needed)

set -e

SOURCE="${1:-icon-source.png}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONSET="$SCRIPT_DIR/Shelve.iconset"
OUTPUT="$SCRIPT_DIR/Sources/Shelve/Assets/Shelve.icns"

if [ ! -f "$SOURCE" ]; then
    echo "❌ No source image found."
    echo "   Put a 1024×1024 PNG in the shelve-native folder and run:"
    echo "   ./make-icon.sh your-image.png"
    exit 1
fi

echo "🎨 Generating icon from $SOURCE..."
rm -rf "$ICONSET"
mkdir "$ICONSET"

sips -z 16   16   "$SOURCE" --out "$ICONSET/icon_16x16.png"      > /dev/null
sips -z 32   32   "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null
sips -z 32   32   "$SOURCE" --out "$ICONSET/icon_32x32.png"      > /dev/null
sips -z 64   64   "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null
sips -z 128  128  "$SOURCE" --out "$ICONSET/icon_128x128.png"    > /dev/null
sips -z 256  256  "$SOURCE" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256  256  "$SOURCE" --out "$ICONSET/icon_256x256.png"    > /dev/null
sips -z 512  512  "$SOURCE" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512  512  "$SOURCE" --out "$ICONSET/icon_512x512.png"    > /dev/null
sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png" > /dev/null

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"

echo "✅ Icon saved to Sources/Shelve/Assets/Shelve.icns"
echo "   Now run ./build-app.sh to package the app."
