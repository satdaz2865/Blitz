#!/bin/bash
set -e

echo "=== Building VIC-20 Blitz for macOS ==="

# Compile native binary with Swift compiler
swiftc -O -o "VIC Blitz" \
    FontData.swift \
    BlitzAudio.swift \
    BlitzGame.swift \
    BlitzView.swift \
    main.swift

# Create App Bundle Structure
APP_DIR="VIC Blitz.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp -f "VIC Blitz" "$APP_DIR/Contents/MacOS/VIC Blitz"
cp -f "Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "AppIcon.icns" ]; then
    cp -f "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

xattr -cr "$APP_DIR" || true

echo "✓ Build complete: $APP_DIR"
echo "Run with: open \"$APP_DIR\""
